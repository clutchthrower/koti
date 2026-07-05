import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/settings_store.dart';
import '../store/state_store.dart';
import '../theme/hemma_theme.dart';
import '../widgets/entity_watcher.dart';
import 'popup_base.dart';

/// Media player controls in an anchored popup: artwork, track info,
/// previous/play-pause/next, a volume slider, and power.
void showMediaPopup(BuildContext context, {required String entityId, String? title}) {
  showHemmaPopup(
    context,
    title: title ?? 'Media',
    builder: (context) => _MediaControls(entityId: entityId),
  );
}

class _MediaControls extends StatefulWidget {
  final String entityId;
  const _MediaControls({required this.entityId});

  @override
  State<_MediaControls> createState() => _MediaControlsState();
}

class _MediaControlsState extends State<_MediaControls> {
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    final tokens = HemmaTheme.of(context);
    final store = Provider.of<StateStore>(context, listen: false);
    final settings = Provider.of<SettingsStore>(context, listen: false);

    void call(String service, [Map<String, dynamic>? data]) => store
        .callService('media_player', service, entityId: widget.entityId, data: data);

    return EntityWatcher(
      entityIds: [widget.entityId],
      builder: (context, states) {
        final entity = states[widget.entityId];
        final state = entity?.state ?? 'off';
        final playing = state == 'playing' || state == 'buffering';
        final off = state == 'off' || state == 'unavailable' || state == 'standby';
        final trackTitle = entity?.attr<String>('media_title', '');
        final artist = entity?.attr<String>('media_artist', '');
        final volume = entity?.attrDouble('volume_level');
        final picture = entity?.attr<String>('entity_picture', '');
        final pictureUrl = (picture != null && picture.isNotEmpty)
            ? (picture.startsWith('http')
                ? picture
                : '${settings.activeUrl}$picture')
            : null;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: pictureUrl != null
                      ? Image.network(
                          pictureUrl,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          headers: {
                            'Authorization':
                                'Bearer ${settings.accessToken ?? ''}'
                          },
                          errorBuilder: (_, __, ___) =>
                              _artFallback(tokens),
                        )
                      : _artFallback(tokens),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (trackTitle?.isNotEmpty ?? false)
                            ? trackTitle!
                            : _stateLabel(state),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15),
                      ),
                      if (artist?.isNotEmpty ?? false)
                        Text(
                          artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: tokens.textSecondary, fontSize: 13),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: off ? 'Turn on' : 'Turn off',
                  icon: Icon(Icons.power_settings_new,
                      color: off ? tokens.textSecondary : tokens.activeColor),
                  onPressed: () => call(off ? 'turn_on' : 'turn_off'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 32,
                  icon: Icon(Icons.skip_previous, color: tokens.textPrimary),
                  onPressed: () => call('media_previous_track'),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 36,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () => call('media_play_pause'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 32,
                  icon: Icon(Icons.skip_next, color: tokens.textPrimary),
                  onPressed: () => call('media_next_track'),
                ),
              ],
            ),
            if (volume != null)
              Row(
                children: [
                  Icon(Icons.volume_down, color: tokens.textSecondary, size: 20),
                  Expanded(
                    child: Slider(
                      value: (_dragVolume ?? volume).clamp(0.0, 1.0),
                      onChanged: (v) => setState(() => _dragVolume = v),
                      onChangeEnd: (v) {
                        call('volume_set', {'volume_level': v});
                        setState(() => _dragVolume = null);
                      },
                    ),
                  ),
                  Icon(Icons.volume_up, color: tokens.textSecondary, size: 20),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _artFallback(dynamic tokens) => Container(
        width: 64,
        height: 64,
        color: const Color.fromRGBO(255, 255, 255, 0.1),
        child: const Icon(Icons.music_note, color: Colors.white54),
      );

  String _stateLabel(String state) => switch (state) {
        'off' => 'Off',
        'idle' => 'Idle',
        'paused' => 'Paused',
        'standby' => 'Standby',
        'unavailable' => 'Unavailable',
        _ => state[0].toUpperCase() + state.substring(1),
      };
}
