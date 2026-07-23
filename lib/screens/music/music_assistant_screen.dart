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
        if (_blurredArt != null)
          Image(image: _blurredArt!, fit: BoxFit.cover),
        // A dark scrim over the blurred art keeps card text legible
        // regardless of how bright the source artwork is.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tokens.dialogBackground.withValues(alpha: 0.55),
                tokens.dialogBackground.withValues(alpha: 0.94),
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
