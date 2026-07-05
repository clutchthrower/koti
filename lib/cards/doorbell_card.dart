import 'package:flutter/material.dart';

import '../popups/camera_popup.dart';
import '../widgets/entity_watcher.dart';
import 'base_entity_card.dart';

class DoorbellCard extends StatelessWidget {
  final String entityId;
  final int position;
  /// Optional display-name override from the card config.
  final String? label;

  const DoorbellCard(
      {super.key, required this.entityId, this.label, this.position = 0});

  @override
  Widget build(BuildContext context) {
    return EntityWatcher(
      entityIds: [entityId],
      builder: (context, states) {
        final entity = states[entityId];
        final name =
            label ?? entity?.attr<String>('friendly_name', entityId) ?? entityId;
        // A doorbell backed by a camera entity opens the live view; a
        // binary_sensor doorbell is status-only.
        final isCamera = entityId.startsWith('camera.');
        return HemmaEntityCard(
          iconName: 'doorbell',
          label: name,
          stateText: isCamera ? 'Tap for live view' : (entity?.state ?? 'Idle'),
          active: entity?.state == 'on',
          position: position,
          onTap: isCamera
              ? () => showCameraPopup(context, entityId: entityId, title: name)
              : null,
        );
      },
    );
  }
}
