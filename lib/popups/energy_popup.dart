import 'package:flutter/material.dart';

import '../theme/koti_theme.dart';
import '../utils/color_utils.dart';
import '../widgets/entity_watcher.dart';
import 'popup_base.dart';

Color _wattageColor(double watts) {
  if (watts < 200) return kSeverityColors[SeverityTier.good]!;
  if (watts < 1000) return kSeverityColors[SeverityTier.warning]!;
  if (watts < 3000) return kSeverityColors[SeverityTier.elevated]!;
  return kSeverityColors[SeverityTier.critical]!;
}

void showEnergyPopup(BuildContext context, String powerEntityId) {
  showKotiPopup(
    context,
    title: 'Energy',
    builder: (context) => EntityWatcher(
      entityIds: [powerEntityId],
      builder: (context, states) {
        final tokens = KotiTheme.of(context);
        final watts = double.tryParse(states[powerEntityId]?.state ?? '') ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${watts.toStringAsFixed(0)} W',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: _wattageColor(watts),
              ),
            ),
            const SizedBox(height: 8),
            Text('Real-time power draw', style: TextStyle(color: tokens.textSecondary)),
          ],
        );
      },
    ),
  );
}
