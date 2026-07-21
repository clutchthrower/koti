import 'package:flutter/material.dart';

import '../theme/koti_theme.dart';
import '../utils/color_utils.dart';
import '../widgets/entity_watcher.dart';
import 'popup_base.dart';

/// Replicates `hemma_popup_climate.yaml`'s detail grid (temperature,
/// humidity, AQI) with the same threshold-based color coding used
/// throughout the app. A full 24h history mini-graph is a good follow-up
/// once `GET /api/history/period` is wired into a chart widget.
void showClimatePopup(
  BuildContext context, {
  required String roomName,
  String? tempSensorEntityId,
  String? humiditySensorEntityId,
  String? aqiSensorEntityId,
}) {
  final ids = [
    if (tempSensorEntityId != null) tempSensorEntityId,
    if (humiditySensorEntityId != null) humiditySensorEntityId,
    if (aqiSensorEntityId != null) aqiSensorEntityId,
  ];

  showKotiPopup(
    context,
    title: roomName,
    builder: (context) => EntityWatcher(
      entityIds: ids,
      builder: (context, states) {
        final temp = tempSensorEntityId != null
            ? double.tryParse(states[tempSensorEntityId]?.state ?? '')
            : null;
        final humidity = humiditySensorEntityId != null
            ? double.tryParse(states[humiditySensorEntityId]?.state ?? '')
            : null;
        final aqi = aqiSensorEntityId != null
            ? double.tryParse(states[aqiSensorEntityId]?.state ?? '')
            : null;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (temp != null)
              _Tile(
                label: 'Temperature',
                value: '${temp.toStringAsFixed(0)}°',
                color: colorForTempF(temp),
              ),
            if (humidity != null)
              _Tile(
                label: 'Humidity',
                value: '${humidity.toStringAsFixed(0)}%',
                color: colorForHumidity(humidity),
              ),
            if (aqi != null)
              _Tile(
                label: 'AQI',
                value: aqi.toStringAsFixed(0),
                color: aqi < 50
                    ? kSeverityColors[SeverityTier.good]!
                    : aqi < 100
                        ? kSeverityColors[SeverityTier.warning]!
                        : kSeverityColors[SeverityTier.critical]!,
              ),
          ],
        );
      },
    ),
  );
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Tile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
      ],
    );
  }
}
