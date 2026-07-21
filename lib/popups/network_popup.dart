import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/helper_store.dart';
import '../store/state_store.dart';
import '../theme/koti_theme.dart';
import '../utils/color_utils.dart';
import '../widgets/entity_watcher.dart';
import 'popup_base.dart';

/// Replicates `script.hemma_restart_toggle`: idle -> confirm -> done(3s) ->
/// idle per device, gated so a restart can never fire without the confirm
/// tap first.
void showNetworkPopup(
  BuildContext context, {
  required String downloadSensorEntityId,
  String? uploadSensorEntityId,
  String? pingSensorEntityId,
  String? device1Name,
  String? device1RestartEntityId,
  String? device2Name,
  String? device2RestartEntityId,
}) {
  final ids = [
    downloadSensorEntityId,
    if (uploadSensorEntityId != null) uploadSensorEntityId,
    if (pingSensorEntityId != null) pingSensorEntityId,
  ];

  showKotiPopup(
    context,
    title: 'Network',
    builder: (context) => EntityWatcher(
      entityIds: ids,
      builder: (context, states) {
        final tokens = KotiTheme.of(context);
        final down = double.tryParse(states[downloadSensorEntityId]?.state ?? '') ?? 0;
        final up = uploadSensorEntityId != null
            ? double.tryParse(states[uploadSensorEntityId]?.state ?? '') ?? 0
            : null;
        final ping = pingSensorEntityId != null
            ? double.tryParse(states[pingSensorEntityId]?.state ?? '')
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Download: ${down.toStringAsFixed(1)} Mbps',
                style: TextStyle(color: tokens.textPrimary)),
            if (up != null)
              Text('Upload: ${up.toStringAsFixed(1)} Mbps',
                  style: TextStyle(color: tokens.textPrimary)),
            if (ping != null)
              Text('Ping: ${ping.toStringAsFixed(0)} ms',
                  style: TextStyle(color: tokens.textPrimary)),
            const SizedBox(height: 16),
            if (device1RestartEntityId != null)
              _RestartTile(
                slot: 1,
                name: device1Name ?? 'Router',
                restartEntityId: device1RestartEntityId,
              ),
            if (device2RestartEntityId != null)
              _RestartTile(
                slot: 2,
                name: device2Name ?? 'Access Point',
                restartEntityId: device2RestartEntityId,
              ),
          ],
        );
      },
    ),
  );
}

class _RestartTile extends StatelessWidget {
  final int slot;
  final String name;
  final String restartEntityId;

  const _RestartTile({required this.slot, required this.name, required this.restartEntityId});

  @override
  Widget build(BuildContext context) {
    final helpers = context.watch<HelperStore>();
    final store = Provider.of<StateStore>(context, listen: false);
    final confirming = slot == 1 ? helpers.restartConfirm1 : helpers.restartConfirm2;
    final done = slot == 1 ? helpers.restartDone1 : helpers.restartDone2;

    final label = done ? 'Done' : (confirming ? 'Confirm?' : name);
    final color = done
        ? kSeverityColors[SeverityTier.good]
        : confirming
            ? kSeverityColors[SeverityTier.elevated]
            : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: done
            ? null
            : () => helpers.handleRestartTap(slot, () async {
                  final domain = restartEntityId.split('.').first;
                  await store.callService(
                    domain,
                    domain == 'button' ? 'press' : 'turn_on',
                    entityId: restartEntityId,
                  );
                }),
        style: OutlinedButton.styleFrom(foregroundColor: color),
        child: Text(label),
      ),
    );
  }
}
