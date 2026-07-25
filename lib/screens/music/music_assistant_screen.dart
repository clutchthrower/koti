import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../store/settings_store.dart';
import '../../store/state_store.dart';
import '../../theme/koti_theme.dart';
import '../../utils/album_art_blur.dart';
import '../../widgets/entity_watcher.dart';
import '../../widgets/glass_tab_strip.dart';
import 'music_assistant_api.dart';
import 'music_browse_tab.dart';
import 'music_now_playing_tab.dart';
import 'music_players_popup.dart';
import 'music_queue_tab.dart';
import 'music_search_tab.dart';

/// The Music tab's content: pick a speaker/group (via the speaker-group
/// icon on Now Playing's volume bar, or the empty-state prompt before any
/// player's picked), then Now Playing / Search / Browse / Queue
/// underneath. Styled after HOMEii Flow's Music Assistant dashboard
/// (github.com/r11a/homeii-music-flow) — most visibly its background: the
/// current track's own album art, heavily blurred and stretched full-tab
/// (see [AlbumArtBlurCache] — a one-off blur baked into a cached bitmap,
/// not a live filter; CLAUDE.md bans BackdropFilter and other per-frame
/// blur work). Lives inside [AppShell]'s own swipe-navigation Stack (to
/// the left of Home) rather than owning a Scaffold/AppBar of its own — so
/// it paints its own full-bleed background and leaves clearance for the
/// shell's floating top nav instead. Works against any `media_player`
/// entity — MA-specific actions (search, browse, queue, play_media) go
/// through the `music_assistant.*` HA services, so it needs Music
/// Assistant installed, but doesn't care how each player got there (native
/// or this tablet's own Koti speaker, if set up as one).
class MusicAssistantScreen extends StatefulWidget {
  const MusicAssistantScreen({super.key});

  @override
  State<MusicAssistantScreen> createState() => _MusicAssistantScreenState();
}

class _MusicAssistantScreenState extends State<MusicAssistantScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 4, vsync: this);
  // Created once (not per build) so its config_entry_id cache actually
  // sticks instead of being rediscovered on every rebuild.
  late final MusicAssistantApi _api =
      MusicAssistantApi(Provider.of<StateStore>(context, listen: false));
  String? _selectedPlayer;

  ImageProvider? _blurredArt;
  String? _blurredForUrl;

  @override
  void initState() {
    super.initState();
    _selectOwnPlayerIfAvailable();
  }

  /// Defaults to this tablet's own player (Koti/Sendspin) rather than
  /// leaving the tab on its empty state every launch — same shared-
  /// unique_id trick `dedupedPlayerIds` already uses to recognize this
  /// device's entities: "up" + this device's own id is what both the
  /// direct-control `koti` entity and (once Sendspin/MA is connected) the
  /// Music-Assistant-mirrored entity share. Prefers the `music_assistant`
  /// one when both exist, since only that one gets full search/browse/
  /// queue support via MA's own services. Silently leaves the empty state
  /// in place (unchanged behavior) if the registry's unavailable (needs an
  /// admin token) or this tablet isn't registered as a player at all.
  Future<void> _selectOwnPlayerIfAvailable() async {
    final store = Provider.of<StateStore>(context, listen: false);
    final settings = Provider.of<SettingsStore>(context, listen: false);
    final ownUniqueId = 'up${settings.deviceId}';
    List<Map<String, dynamic>> registry;
    try {
      registry = await store.getEntityRegistry();
    } catch (_) {
      return;
    }
    final matches = registry.where((e) =>
        e['unique_id'] == ownUniqueId &&
        (e['entity_id'] as String?)?.startsWith('media_player.') == true &&
        _isAvailable(store, e['entity_id'] as String));
    if (matches.isEmpty) return;
    final entry = matches.firstWhere(
      (e) => e['platform'] == 'music_assistant',
      orElse: () => matches.first,
    );
    final entityId = entry['entity_id'] as String;
    // Only auto-select if nothing else was picked while the (admin-only,
    // occasionally slow) registry fetch was in flight.
    if (mounted && _selectedPlayer == null) {
      setState(() => _selectedPlayer = entityId);
    }
  }

  bool _isAvailable(StateStore store, String entityId) {
    final state = store.get(entityId)?.state;
    return state != null && state != 'unavailable' && state != 'unknown';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _selectPlayer(String id) {
    setState(() {
      _selectedPlayer = id;
      // Clear the stale art immediately rather than let the previous
      // player's background linger until the new one's art (if any) loads.
      _blurredArt = null;
      _blurredForUrl = null;
    });
  }

  Future<void> _updateBlurredArt(String? pictureUrl, String? token) async {
    if (pictureUrl == _blurredForUrl) return;
    _blurredForUrl = pictureUrl;
    if (pictureUrl == null) {
      if (mounted) setState(() => _blurredArt = null);
      return;
    }
    final art = await AlbumArtBlurCache.blurred(
      pictureUrl,
      headers: {'Authorization': 'Bearer ${token ?? ''}'},
    );
    // Guard against a stale response landing after the track changed again.
    if (mounted && _blurredForUrl == pictureUrl) {
      setState(() => _blurredArt = art);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    final tokens = KotiTheme.of(context);
    final settings = context.watch<SettingsStore>();
    final selected = _selectedPlayer;

    // Watching the selected player here (rather than only inside
    // MusicNowPlayingTab) is what lets the background follow the track
    // even while Search/Browse/Queue are the visible tab.
    final pictureWatcher = selected == null
        ? null
        : EntityWatcher(
            entityIds: [selected],
            builder: (context, states) {
              final picture = states[selected]?.attr<String>('entity_picture', '');
              final pictureUrl = (picture != null && picture.isNotEmpty)
                  ? (picture.startsWith('http') ? picture : '${settings.activeUrl}$picture')
                  : null;
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _updateBlurredArt(pictureUrl, settings.accessToken));
              return const SizedBox.shrink();
            },
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: tokens.dialogBackground),
        // Crossfades between tracks' blurred art instead of popping
        // instantly — keyed on the source URL so AnimatedSwitcher only
        // animates on an actual track/album change, not every rebuild.
        // AnimatedSwitcher's default internal Stack doesn't use
        // StackFit.expand, so without this custom layoutBuilder the image
        // sizes itself to its own small intrinsic (pre-blur decode target)
        // size instead of covering the screen — BoxFit.cover then has
        // nothing to actually stretch into.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [...previousChildren, if (currentChild != null) currentChild],
          ),
          child: _blurredArt == null
              ? const SizedBox.shrink(key: ValueKey('no-art'))
              : Image(
                  key: ValueKey(_blurredForUrl),
                  image: _blurredArt!,
                  fit: BoxFit.cover,
                ),
        ),
        // A soft scrim — just enough to keep text legible over bright
        // artwork, brightest near the hero art itself and only deepening
        // toward the transport controls at the bottom. This used to run
        // 55%-94% opaque, which crushed out virtually all of the album
        // art's own color and made the tab look the same flat near-black
        // no matter what was playing — the opposite of the ambient,
        // color-led HOMEii Flow look this screen is meant to match.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.45, 1.0],
              colors: [
                tokens.dialogBackground.withValues(alpha: 0.12),
                tokens.dialogBackground.withValues(alpha: 0.32),
                tokens.dialogBackground.withValues(alpha: 0.70),
              ],
            ),
          ),
        ),
        if (pictureWatcher != null) pictureWatcher,
        SafeArea(
          bottom: false,
          // Clears the shell's floating hamburger/nav-pill/clock row,
          // which floats on top of this content rather than reserving
          // space for it.
          child: Padding(
            padding: EdgeInsets.only(top: tokens.navHeight),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: GlassTabStrip(
                    controller: _tabController,
                    labels: const ['Now Playing', 'Search', 'Browse', 'Queue'],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: selected == null
                      ? _EmptyState(onSelectPlayer: _selectPlayer)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            MusicNowPlayingTab(
                              entityId: selected,
                              api: api,
                              onSelectPlayer: _selectPlayer,
                            ),
                            MusicSearchTab(entityId: selected, api: api),
                            MusicBrowseTab(entityId: selected, api: api),
                            MusicQueueTab(entityId: selected, api: api),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ValueChanged<String> onSelectPlayer;

  const _EmptyState({required this.onSelectPlayer});

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    return Center(
      child: TextButton.icon(
        onPressed: () =>
            showMusicPlayersPopup(context, selected: null, onSelect: onSelectPlayer),
        icon: Icon(Icons.speaker_group, color: tokens.textSecondary),
        label: Text('Pick a speaker to get started',
            style: TextStyle(color: tokens.textSecondary)),
      ),
    );
  }
}
