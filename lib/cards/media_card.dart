import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../popups/media_popup.dart';
import '../store/state_store.dart';
import '../widgets/entity_watcher.dart';
import 'base_entity_card.dart';

/// Replicates `hemma_media.yaml`: shows "{artist} — {title}" when metadata
/// is available, else the app/input name, plus a playback progress ring.
class MediaCard extends StatelessWidget {
  final String entityId;
  final int position;
  /// Optional display-name override from the card config.
  final String? label;

  const MediaCard(
      {super.key, required this.entityId, this.label, this.position = 0});

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<StateStore>(context, listen: false);
    return EntityWatcher(
      entityIds: [entityId],
      builder: (context, states) {
        final entity = states[entityId];
        final playing = entity?.state == 'playing' || entity?.state == 'buffering';
        final artist = entity?.attributes['media_artist'] as String?;
        final title = entity?.attributes['media_title'] as String?;
        final appName = entity?.attr<String>('app_name', '');
        final label = this.label ?? entity?.attr<String>('friendly_name', entityId) ?? entityId;

        String stateText;
        if (artist != null && title != null) {
          stateText = '$artist — $title';
        } else if (title != null) {
          stateText = title;
        } else if (appName != null && appName.isNotEmpty) {
          stateText = appName;
        } else {
          stateText = entity?.state ?? 'Off';
        }

        final position0 = entity?.attrDouble('media_position');
        final duration = entity?.attrDouble('media_duration');
        final progress = (position0 != null && duration != null && duration > 0)
            ? (position0 / duration).clamp(0.0, 1.0)
            : null;

        return HemmaEntityCard(
          iconName: 'speaker',
          label: label,
          stateText: stateText,
          active: playing,
          position: position,
          progress: playing ? progress : null,
          // Tap opens full controls; the trailing button keeps quick
          // play/pause one touch away like the original.
          onTap: () => showMediaPopup(context, entityId: entityId, title: label),
          trailing: IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(playing ? Icons.pause_circle_outline : Icons.play_circle_outline,
                color: Colors.white70, size: 28),
            onPressed: () => store.callService('media_player', 'media_play_pause',
                entityId: entityId),
          ),
        );
      },
    );
  }
}
