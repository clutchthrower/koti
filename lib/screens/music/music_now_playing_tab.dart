import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/entity_state.dart';
import '../../store/settings_store.dart';
import '../../store/state_store.dart';
import '../../theme/koti_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/device_mode.dart';
import '../../widgets/entity_watcher.dart';
import '../../widgets/koti_icon.dart';
import 'music_assistant_api.dart';
import 'music_players_popup.dart';

class MusicNowPlayingTab extends StatefulWidget {
  final String entityId;
  final MusicAssistantApi api;
  final ValueChanged<String> onSelectPlayer;

  const MusicNowPlayingTab({
    super.key,
    required this.entityId,
    required this.api,
    required this.onSelectPlayer,
  });

  @override
  State<MusicNowPlayingTab> createState() => _MusicNowPlayingTabState();
}

class _MusicNowPlayingTabState extends State<MusicNowPlayingTab> {
  double? _dragVolume;
  Timer? _positionTicker;
  String? _favoriteButtonId;

  @override
  void initState() {
    super.initState();
    // Ticks the elapsed-time label between state updates so the progress
    // bar doesn't sit frozen between MA's periodic position reports.
    _positionTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _resolveFavoriteButton();
  }

  @override
  void didUpdateWidget(covariant MusicNowPlayingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId) {
      _favoriteButtonId = null;
      _resolveFavoriteButton();
    }
  }

  Future<void> _resolveFavoriteButton() async {
    final requestedFor = widget.entityId;
    final id = await widget.api.resolveFavoriteButton(requestedFor);
    // Guard against a stale response landing after the player changed again.
    if (mounted && widget.entityId == requestedFor) {
      setState(() => _favoriteButtonId = id);
    }
  }

  Future<void> _markFavorite() async {
    final buttonId = _favoriteButtonId;
    if (buttonId == null) return;
    await widget.api.pressFavoriteButton(buttonId);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Added to favorites')));
    }
  }

  @override
  void dispose() {
    _positionTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<StateStore>(context, listen: false);
    final settings = Provider.of<SettingsStore>(context, listen: false);
    // Landscape wall-tablet/desktop: art beside the track info, like HOMEii
    // Flow's desktop layout. Portrait/narrow: stacked, art on top.
    final sideBySide = !isPortrait(context) && deviceModeFor(context) != DeviceMode.mobile;

    void call(String service, [Map<String, dynamic>? data]) => store
        .callService('media_player', service, entityId: widget.entityId, data: data);

    return EntityWatcher(
      entityIds: [widget.entityId],
      builder: (context, states) {
        final entity = states[widget.entityId];
        final state = entity?.state ?? 'off';
        final playing = state == 'playing' || state == 'buffering';
        final off = state == 'off' || state == 'unavailable' || state == 'standby';
        final title = entity?.attr<String>('media_title', '');
        final artist = entity?.attr<String>('media_artist', '');
        final album = entity?.attr<String>('media_album_name', '');
        final volume = entity?.attrDouble('volume_level');
        final muted = entity?.attributes['is_volume_muted'] as bool? ?? false;
        final shuffle = entity?.attributes['shuffle'] as bool?;
        final repeat = entity?.attr<String>('repeat', 'off');
        final picture = entity?.attr<String>('entity_picture', '');
        final pictureUrl = (picture != null && picture.isNotEmpty)
            ? (picture.startsWith('http') ? picture : '${settings.activeUrl}$picture')
            : null;

        final position = entity?.attrDouble('media_position');
        final duration = entity?.attrDouble('media_duration');
        final updatedAt = entity?.attributes['media_position_updated_at'] as String?;
        double? elapsed = position;
        if (playing && position != null && updatedAt != null) {
          final updated = DateTime.tryParse(updatedAt);
          if (updated != null) {
            elapsed = position + DateTime.now().difference(updated).inSeconds;
          }
        }
        final progress = (elapsed != null && duration != null && duration > 0)
            ? (elapsed / duration).clamp(0.0, 1.0)
            : null;

        final supported = entity?.attributes['supported_features'] as int?;
        final shuffleOn = shuffle ?? false;
        final supportsShuffle = shuffle != null;
        final supportsGrouping = supported != null && (supported & 524288) != 0;

        final art = _AlbumArt(
          pictureUrl: pictureUrl,
          size: sideBySide ? 300 : 260,
          accessToken: settings.accessToken,
        );

        final titleBlock = _TitleBlock(
          title: (title?.isNotEmpty ?? false) ? title! : _stateLabel(state),
          subtitle: (artist?.isNotEmpty ?? false)
              ? [artist, if (album?.isNotEmpty ?? false) album].join(' — ')
              : null,
          centered: !sideBySide,
        );

        final iconRow = _ActionIconRow(
          off: off,
          supportsGrouping: supportsGrouping,
          onPower: () => call(off ? 'turn_on' : 'turn_off'),
          onGroup: supportsGrouping ? () => _showGroupSheet(context, store) : null,
          onFavorite: _favoriteButtonId == null ? null : _markFavorite,
          centered: !sideBySide,
        );

        final progressBlock = _ProgressBlock(
          progress: progress,
          elapsed: elapsed,
          duration: duration,
        );

        final transport = _TransportRow(
          playing: playing,
          shuffleOn: shuffleOn,
          supportsShuffle: supportsShuffle,
          repeat: repeat,
          onShuffle: () => call('shuffle_set', {'shuffle': !shuffleOn}),
          onPrevious: () => call('media_previous_track'),
          onPlayPause: () => call('media_play_pause'),
          onNext: () => call('media_next_track'),
          onRepeat: repeat == null
              ? null
              : () => call('repeat_set', {
                    'repeat': switch (repeat) {
                      'off' => 'all',
                      'all' => 'one',
                      _ => 'off',
                    }
                  }),
        );

        final volumeRow = _VolumeRow(
          volume: volume == null ? null : (_dragVolume ?? volume),
          muted: muted,
          onChanged: (v) => setState(() => _dragVolume = v),
          onChangeEnd: (v) {
            call('volume_set', {'volume_level': v});
            setState(() => _dragVolume = null);
          },
          onToggleMute: () => call('volume_mute', {'is_volume_muted': !muted}),
          onOpenPlayers: () =>
              showMusicPlayersPopup(context, selected: widget.entityId, onSelect: widget.onSelectPlayer),
        );

        if (sideBySide) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    art,
                    const SizedBox(width: 28),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          titleBlock,
                          const SizedBox(height: 10),
                          iconRow,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              progressBlock,
              const SizedBox(height: 18),
              transport,
              const SizedBox(height: 18),
              volumeRow,
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: art),
            const SizedBox(height: 20),
            titleBlock,
            const SizedBox(height: 10),
            iconRow,
            const SizedBox(height: 16),
            progressBlock,
            const SizedBox(height: 14),
            transport,
            const SizedBox(height: 14),
            volumeRow,
          ],
        );
      },
    );
  }

  Future<void> _showGroupSheet(BuildContext context, StateStore store) async {
    final tokens = KotiTheme.of(context);
    // Same dedup the Players popup applies (music_players_popup.dart) —
    // without it, every Cast/webOS-plus-Music-Assistant pair (and any
    // stale registry leftover) shows up twice as separate checkboxes here
    // too, since this list was built straight off store.all with no
    // filtering at all.
    final candidateIds =
        availablePlayerIds(store).where((id) => id != widget.entityId).toList();
    final dedupedIds = await dedupedPlayerIds(store, candidateIds);
    final others = dedupedIds
        .map((id) => store.get(id))
        .whereType<EntityState>()
        .toList()
      ..sort((a, b) => a.attr<String>('friendly_name', a.entityId)
          .compareTo(b.attr<String>('friendly_name', b.entityId)));
    if (!context.mounted) return;
    final current = store.get(widget.entityId);
    final currentGroup =
        (current?.attributes['group_members'] as List?)?.cast<String>() ?? const [];
    final selected = {...currentGroup}..remove(widget.entityId);

    return showModalBottomSheet(
      context: context,
      backgroundColor: tokens.dialogBackground,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Group with',
                    style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 8),
                for (final other in others)
                  CheckboxListTile(
                    title: Text(other.attr<String>('friendly_name', other.entityId),
                        style: TextStyle(color: tokens.textPrimary)),
                    value: selected.contains(other.entityId),
                    onChanged: (v) => setSheetState(() {
                      if (v ?? false) {
                        selected.add(other.entityId);
                      } else {
                        selected.remove(other.entityId);
                      }
                    }),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        // Ungrouping THIS entity directly (unjoin) is only
                        // safe when it's a follower. If it's currently the
                        // sync leader (confirmed against Music Assistant's
                        // own server source, controllers/players/
                        // controller.py's cmd_ungroup: ungrouping a leader
                        // removes ALL its followers, not just itself),
                        // that would kill the group for everyone else
                        // instead of just dropping this one player — so
                        // reassign leadership to another remaining member
                        // first when there is one, and only unjoin
                        // outright when this is the last/only member.
                        final remaining =
                            currentGroup.where((id) => id != widget.entityId).toList();
                        if (remaining.isNotEmpty) {
                          widget.api.join(remaining.first, remaining.skip(1).toList());
                        } else {
                          widget.api.unjoin(widget.entityId);
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('Ungroup'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        widget.api.join(widget.entityId, selected.toList());
                        Navigator.of(context).pop();
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _stateLabel(String state) => switch (state) {
        'off' => 'Off',
        'idle' => 'Idle',
        'paused' => 'Paused',
        'standby' => 'Standby',
        'unavailable' => 'Unavailable',
        _ => state.isEmpty ? '' : state[0].toUpperCase() + state.substring(1),
      };
}

/// Big rounded album-art tile — the hero of a HOMEii Flow-style now-playing
/// view. A soft shadow (not a blur filter, just a static drop-shadow) lifts
/// it off the ambient-tinted background behind it, and crossfades to the
/// next track's art (keyed on URL) instead of popping instantly.
class _AlbumArt extends StatelessWidget {
  final String? pictureUrl;
  final double size;
  final String? accessToken;

  const _AlbumArt({required this.pictureUrl, required this.size, required this.accessToken});

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          child: pictureUrl != null
              ? Image.network(
                  pictureUrl!,
                  key: ValueKey(pictureUrl),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  headers: {'Authorization': 'Bearer ${accessToken ?? ''}'},
                  errorBuilder: (_, __, ___) => _fallback(tokens, size),
                )
              : _fallback(tokens, size, key: const ValueKey('no-art')),
        ),
      ),
    );
  }

  Widget _fallback(KotiTokens tokens, double size, {Key? key}) => Container(
        key: key,
        width: size,
        height: size,
        color: tokens.iconCircleBackground,
        child: Icon(Icons.music_note, color: tokens.textSecondary, size: size * 0.3),
      );
}

class _TitleBlock extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool centered;

  const _TitleBlock({required this.title, required this.subtitle, required this.centered});

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    // A soft drop-shadow, not a solid outline — lets the now much-lighter
    // ambient background (see music_assistant_screen.dart's scrim) show
    // its color while keeping the title readable over bright artwork.
    final titleShadow = [
      Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 2)),
    ];
    return Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: centered ? 24 : 34,
              letterSpacing: -0.4,
              height: 1.1,
              shadows: titleShadow),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                shadows: titleShadow),
          ),
        ],
      ],
    );
  }
}

/// Small circular icon buttons under the title — HOMEii Flow's
/// favorite/playlist/share row, scoped to the actions this app actually
/// supports (power, favorite, group) rather than inventing unsupported
/// ones. Favorite only shows when [onFavorite] is non-null — HA's
/// music_assistant integration only exposes it as a per-player `button`
/// entity (confirmed against the actual integration source), which some
/// setups won't have (e.g. a non-admin account can't resolve it, or the
/// entity's been disabled) — see MusicAssistantApi.resolveFavoriteButton.
class _ActionIconRow extends StatelessWidget {
  final bool off;
  final bool supportsGrouping;
  final VoidCallback onPower;
  final VoidCallback? onGroup;
  final VoidCallback? onFavorite;
  final bool centered;

  const _ActionIconRow({
    required this.off,
    required this.supportsGrouping,
    required this.onPower,
    required this.onGroup,
    required this.onFavorite,
    required this.centered,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        _RoundIconButton(
          icon: Icons.power_settings_new,
          tooltip: off ? 'Turn on' : 'Turn off',
          active: !off,
          onTap: onPower,
        ),
        if (onFavorite != null) ...[
          const SizedBox(width: 10),
          _RoundIconButton(
            icon: Icons.favorite_border,
            tooltip: 'Add to favorites',
            active: false,
            onTap: onFavorite,
          ),
        ],
        if (supportsGrouping) ...[
          const SizedBox(width: 10),
          _RoundIconButton(
            icon: Icons.speaker_group,
            tooltip: 'Group',
            active: false,
            onTap: onGroup,
          ),
        ],
      ],
    );
  }
}

/// Either [icon] (a Material icon) or [assetIcon] (a bundled SVG name, for
/// icons like the speaker-group glyph Material doesn't have) must be given.
/// Scales down slightly under the finger on press — a purely-transform,
/// no-extra-repaint bit of tactile feedback so these read as physical
/// buttons rather than flat static icons.
class _RoundIconButton extends StatefulWidget {
  static const _size = 38.0;

  final IconData? icon;
  final String? assetIcon;
  final String tooltip;
  final bool active;
  final VoidCallback? onTap;

  const _RoundIconButton({
    this.icon,
    this.assetIcon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  }) : assert(icon != null || assetIcon != null);

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final color = widget.active ? tokens.activeColor : tokens.textSecondary;
    const size = _RoundIconButton._size;
    return Tooltip(
      message: widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Material(
          color: widget.active
              ? tokens.activeColor.withValues(alpha: 0.20)
              : tokens.iconCircleBackground,
          shape: const CircleBorder(
            side: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.08)),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            onTapDown: (_) => _setPressed(true),
            onTapCancel: () => _setPressed(false),
            onTapUp: (_) => _setPressed(false),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: widget.assetIcon != null
                    ? KotiIcon(widget.assetIcon!, size: size * 0.5, color: color)
                    : Icon(widget.icon, size: size * 0.5, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  final double? progress;
  final double? elapsed;
  final double? duration;

  const _ProgressBlock({required this.progress, required this.elapsed, required this.duration});

  @override
  Widget build(BuildContext context) {
    if (progress == null) return const SizedBox.shrink();
    final tokens = KotiTheme.of(context);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: tokens.iconCircleBackground,
            color: tokens.activeColor,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatDuration(elapsed),
                style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
            Text(_formatDuration(duration),
                style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '--:--';
    final d = Duration(seconds: seconds.round());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

/// The five-button transport row — every button gets the same circular
/// pill background (not just play/pause), matching HOMEii Flow's look.
class _TransportRow extends StatelessWidget {
  final bool playing;
  final bool shuffleOn;
  final bool supportsShuffle;
  final String? repeat;
  final VoidCallback onShuffle;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback? onRepeat;

  const _TransportRow({
    required this.playing,
    required this.shuffleOn,
    required this.supportsShuffle,
    required this.repeat,
    required this.onShuffle,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (supportsShuffle) ...[
          _RoundIconButton(
            icon: Icons.shuffle,
            tooltip: 'Shuffle',
            active: shuffleOn,
            onTap: onShuffle,
          ),
          const SizedBox(width: 10),
        ],
        _RoundIconButton(
            icon: Icons.skip_previous, tooltip: 'Previous', active: false, onTap: onPrevious),
        const SizedBox(width: 10),
        _PlayPauseButton(playing: playing, onTap: onPlayPause),
        const SizedBox(width: 10),
        _RoundIconButton(icon: Icons.skip_next, tooltip: 'Next', active: false, onTap: onNext),
        if (repeat != null) ...[
          const SizedBox(width: 10),
          _RoundIconButton(
            icon: repeat == 'one' ? Icons.repeat_one : Icons.repeat,
            tooltip: 'Repeat',
            active: repeat != 'off',
            onTap: onRepeat,
          ),
        ],
      ],
    );
  }
}

/// The transport row's centerpiece — a flat solid fill read as inert next
/// to everything else, so this gets a subtle top-lit gradient, a soft
/// colored glow (echoing the accent instead of a generic black shadow),
/// and the same press-scale the round icon buttons get.
class _PlayPauseButton extends StatefulWidget {
  final bool playing;
  final VoidCallback onTap;

  const _PlayPauseButton({required this.playing, required this.onTap});

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    return AnimatedScale(
      scale: _pressed ? 0.90 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(tokens.activeColor, Colors.white, 0.18)!,
              tokens.activeColor,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.activeColor.withValues(alpha: 0.45),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  widget.playing ? Icons.pause : Icons.play_arrow,
                  key: ValueKey(widget.playing),
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mute on the left, the slider itself (when the player reports a volume
/// level), and a speaker-group icon on the right that opens the players
/// popup — folding player-switching into this row rather than it sitting
/// alone above the tab strip, which read as a lone, oddly-spaced control.
class _VolumeRow extends StatelessWidget {
  final double? volume;
  final bool muted;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onToggleMute;
  final VoidCallback onOpenPlayers;

  const _VolumeRow({
    required this.volume,
    required this.muted,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onToggleMute,
    required this.onOpenPlayers,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    return Row(
      children: [
        _RoundIconButton(
          icon: muted ? Icons.volume_off : Icons.volume_up,
          tooltip: muted ? 'Unmute' : 'Mute',
          active: muted,
          onTap: onToggleMute,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: volume == null
              ? const SizedBox.shrink()
              : SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: tokens.activeColor,
                    inactiveTrackColor: tokens.iconCircleBackground,
                    thumbColor: tokens.activeColor,
                    overlayColor: tokens.activeColor.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: volume!.clamp(0.0, 1.0),
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        _RoundIconButton(
          assetIcon: 'speaker-group',
          tooltip: 'Players',
          active: false,
          onTap: onOpenPlayers,
        ),
      ],
    );
  }
}
