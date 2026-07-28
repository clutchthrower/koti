import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../popups/popup_base.dart';
import '../store/state_store.dart';
import '../theme/koti_theme.dart';
import '../widgets/entity_watcher.dart';
import 'base_entity_card.dart';

/// Replicates `hemma_thermostat.yaml`: tapping the card opens a popup with
/// a temperature slider and cool/heat mode selectors. (A popup, not the
/// original's inline overlay — the card lives in a fixed-size tile, so
/// expanding in place can't fit.)
class ThermostatCard extends StatelessWidget {
  final String entityId;
  final String? tempSensorEntityId;

  /// Optional display-name override from the card config.
  final String? label;
  final int position;

  const ThermostatCard({
    super.key,
    required this.entityId,
    this.tempSensorEntityId,
    this.label,
    this.position = 0,
  });

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<StateStore>(context, listen: false);
    final entityIds = [entityId, if (tempSensorEntityId != null) tempSensorEntityId!];

    return EntityWatcher(
      entityIds: entityIds,
      builder: (context, states) {
        final climate = states[entityId];
        final currentTemp = tempSensorEntityId != null
            ? double.tryParse(states[tempSensorEntityId]?.state ?? '')
            : climate?.attrDouble('current_temperature');
        final active = climate?.state == 'cool' || climate?.state == 'heat';
        final name =
            label ?? climate?.attr<String>('friendly_name', entityId) ?? entityId;

        return KotiEntityCard(
          iconName: 'thermostat',
          label: name,
          stateText: currentTemp != null
              ? '${currentTemp.toStringAsFixed(0)}°'
              : (climate?.state ?? 'Off'),
          active: active,
          position: position,
          onTap: () => showKotiPopup(
            context,
            title: name,
            builder: (context) => _ThermostatOverlay(entityId: entityId, store: store),
          ),
        );
      },
    );
  }
}

/// Live thermostat controls, driven entirely by the climate entity's real
/// state: its current temperature, its actual target, and whichever HVAC
/// modes it reports supporting (off/cool/heat/auto/...).
class _ThermostatOverlay extends StatefulWidget {
  final String entityId;
  final StateStore store;

  const _ThermostatOverlay({
    required this.entityId,
    required this.store,
  });

  @override
  State<_ThermostatOverlay> createState() => _ThermostatOverlayState();
}

class _ThermostatOverlayState extends State<_ThermostatOverlay> {
  double? _dragTemp; // non-null only while the slider is being dragged

  Color _modeColor(String mode, dynamic tokens) => switch (mode) {
        'cool' => tokens.puckCoolColor,
        'heat' => tokens.puckHeatColor,
        'off' => Colors.white70,
        _ => tokens.activeColor,
      };

  String _modeLabel(String mode) =>
      mode.isEmpty ? mode : mode[0].toUpperCase() + mode.substring(1).replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);

    return EntityWatcher(
      entityIds: [widget.entityId],
      builder: (context, states) {
        final climate = states[widget.entityId];
        if (climate == null || climate.state == 'unavailable') {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Thermostat is unavailable',
                style: TextStyle(color: Colors.white70)),
          );
        }

        final mode = climate.state;
        final modes = (climate.attributes['hvac_modes'] as List?)?.cast<String>() ??
            const ['off', 'cool', 'heat'];
        final current = climate.attrDouble('current_temperature');
        final target = climate.attrDouble('temperature');
        final minTemp = climate.attrDouble('min_temp') ?? 55;
        final maxTemp = climate.attrDouble('max_temp') ?? 90;
        final shown = (_dragTemp ?? target ?? (minTemp + maxTemp) / 2)
            .clamp(minTemp, maxTemp);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current != null)
              Text(
                'Currently ${current.toStringAsFixed(0)}°',
                style: TextStyle(color: tokens.textSecondary, fontSize: 14),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in modes)
                  _ModeButton(
                    label: _modeLabel(m),
                    selected: mode == m,
                    color: _modeColor(m, tokens),
                    onTap: () => widget.store.callService(
                        'climate', 'set_hvac_mode',
                        entityId: widget.entityId, data: {'hvac_mode': m}),
                  ),
              ],
            ),
            if (mode != 'off') ...[
              const SizedBox(height: 16),
              Text(
                'Set to',
                style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              ),
              Row(
                children: [
                  Text(
                    '${shown.toStringAsFixed(0)}°',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: shown.toDouble(),
                      min: minTemp,
                      max: maxTemp,
                      divisions: (maxTemp - minTemp).round().clamp(1, 100),
                      label: '${shown.toStringAsFixed(0)}°',
                      activeColor:
                          mode == 'heat' ? tokens.puckHeatColor : tokens.puckCoolColor,
                      onChanged: (v) => setState(() => _dragTemp = v),
                      onChangeEnd: (v) {
                        widget.store.callService('climate', 'set_temperature',
                            entityId: widget.entityId,
                            data: {'temperature': v.roundToDouble()});
                        setState(() => _dragTemp = null);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : Colors.transparent),
        ),
        child: Text(label, style: TextStyle(color: selected ? color : null)),
      ),
    );
  }
}
