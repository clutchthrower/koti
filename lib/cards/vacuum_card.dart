import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../popups/popup_base.dart';
import '../store/state_store.dart';
import '../theme/hemma_theme.dart';
import '../widgets/entity_watcher.dart';
import 'base_entity_card.dart';

class VacuumCard extends StatelessWidget {
  final String entityId;
  final int position;
  /// Optional display-name override from the card config.
  final String? label;

  const VacuumCard(
      {super.key, required this.entityId, this.label, this.position = 0});

  @override
  Widget build(BuildContext context) {
    return EntityWatcher(
      entityIds: [entityId],
      builder: (context, states) {
        final entity = states[entityId];
        final state = entity?.state ?? 'docked';
        final icon = switch (state) {
          'cleaning' || 'returning' => 'vacuum-clean',
          'charging' => 'vacuum-charge',
          _ => 'vacuum',
        };
        final progress = entity?.attrDouble('battery_level') != null
            ? entity!.attrDouble('battery_level')! / 100
            : null;
        final name =
            label ?? entity?.attr<String>('friendly_name', entityId) ?? entityId;
        return HemmaEntityCard(
          iconName: icon,
          label: name,
          stateText: state[0].toUpperCase() + state.substring(1),
          active: state == 'cleaning' || state == 'returning',
          position: position,
          progress: progress,
          onTap: () => _showControls(context, name),
        );
      },
    );
  }

  void _showControls(BuildContext context, String name) {
    showHemmaPopup(
      context,
      title: name,
      builder: (context) => _VacuumControls(entityId: entityId),
    );
  }
}

class _VacuumControls extends StatelessWidget {
  final String entityId;
  const _VacuumControls({required this.entityId});

  @override
  Widget build(BuildContext context) {
    final tokens = HemmaTheme.of(context);
    final store = Provider.of<StateStore>(context, listen: false);

    void call(String service) =>
        store.callService('vacuum', service, entityId: entityId);

    return EntityWatcher(
      entityIds: [entityId],
      builder: (context, states) {
        final entity = states[entityId];
        final state = entity?.state ?? 'unknown';
        final battery = entity?.attrDouble('battery_level');
        final cleaning = state == 'cleaning';

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${state[0].toUpperCase()}${state.substring(1)}'
              '${battery != null ? '  ·  ${battery.toStringAsFixed(0)}% battery' : ''}',
              style: TextStyle(color: tokens.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  icon: Icon(cleaning ? Icons.pause : Icons.play_arrow),
                  label: Text(cleaning ? 'Pause' : 'Start'),
                  onPressed: () => call(cleaning ? 'pause' : 'start'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Dock'),
                  onPressed: () => call('return_to_base'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.location_searching),
                  label: const Text('Locate'),
                  onPressed: () => call('locate'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
