import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../popups/popup_base.dart';
import '../store/state_store.dart';
import '../theme/hemma_theme.dart';
import '../widgets/entity_watcher.dart';
import 'base_entity_card.dart';

class CurtainCard extends StatelessWidget {
  final String entityId;
  final int position;
  /// Optional display-name override from the card config.
  final String? label;

  const CurtainCard(
      {super.key, required this.entityId, this.label, this.position = 0});

  @override
  Widget build(BuildContext context) {
    return EntityWatcher(
      entityIds: [entityId],
      builder: (context, states) {
        final entity = states[entityId];
        final open = entity?.state == 'open' || entity?.state == 'opening';
        final positionPct = entity?.attrDouble('current_position');
        final name =
            label ?? entity?.attr<String>('friendly_name', entityId) ?? entityId;
        return HemmaEntityCard(
          iconName: open ? 'curtain-open' : 'curtain-closed',
          label: name,
          stateText: positionPct != null
              ? '${positionPct.toStringAsFixed(0)}%'
              : (entity?.state ?? 'Closed'),
          active: open,
          position: position,
          progress: positionPct != null ? positionPct / 100 : null,
          onTap: () => showHemmaPopup(
            context,
            title: name,
            builder: (context) => _CoverControls(entityId: entityId),
          ),
        );
      },
    );
  }
}

class _CoverControls extends StatefulWidget {
  final String entityId;
  const _CoverControls({required this.entityId});

  @override
  State<_CoverControls> createState() => _CoverControlsState();
}

class _CoverControlsState extends State<_CoverControls> {
  double? _dragPos;

  @override
  Widget build(BuildContext context) {
    final tokens = HemmaTheme.of(context);
    final store = Provider.of<StateStore>(context, listen: false);

    void call(String service, [Map<String, dynamic>? data]) =>
        store.callService('cover', service, entityId: widget.entityId, data: data);

    return EntityWatcher(
      entityIds: [widget.entityId],
      builder: (context, states) {
        final entity = states[widget.entityId];
        final positionPct = entity?.attrDouble('current_position');

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entity?.state == null
                  ? 'Unknown'
                  : entity!.state[0].toUpperCase() + entity.state.substring(1),
              style: TextStyle(color: tokens.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  tooltip: 'Open',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: () => call('open_cover'),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Stop',
                  icon: const Icon(Icons.stop),
                  onPressed: () => call('stop_cover'),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Close',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: () => call('close_cover'),
                ),
              ],
            ),
            if (positionPct != null) ...[
              const SizedBox(height: 8),
              Text('Position',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
              Slider(
                value: (_dragPos ?? positionPct).clamp(0.0, 100.0),
                max: 100,
                divisions: 20,
                label: '${(_dragPos ?? positionPct).toStringAsFixed(0)}%',
                onChanged: (v) => setState(() => _dragPos = v),
                onChangeEnd: (v) {
                  call('set_cover_position', {'position': v.round()});
                  setState(() => _dragPos = null);
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
