import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/state_store.dart';
import '../theme/koti_theme.dart';
import '../utils/color_utils.dart';
import 'popup_base.dart';

void showBatteryPopup(BuildContext context, List<String>? entityFilter, int lowThreshold) {
  final store = Provider.of<StateStore>(context, listen: false);
  showKotiPopup(
    context,
    title: 'Batteries',
    builder: (context) {
      final tokens = KotiTheme.of(context);
      final batteries = store.all.values
          .where((e) =>
              e.attr<String>('device_class', '') == 'battery' &&
              (entityFilter == null || entityFilter.contains(e.entityId)))
          .toList()
        ..sort((a, b) =>
            (double.tryParse(a.state) ?? 100).compareTo(double.tryParse(b.state) ?? 100));

      final critical = batteries.where((e) => (double.tryParse(e.state) ?? 100) < 20).length;
      final low = batteries.where((e) {
        final v = double.tryParse(e.state) ?? 100;
        return v >= 20 && v < 50;
      }).length;
      final good = batteries.length - critical - low;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Critical: $critical  ·  Low: $low  ·  Good: $good',
              style: TextStyle(color: tokens.textSecondary)),
          const SizedBox(height: 12),
          ...batteries.map((e) {
            final level = double.tryParse(e.state) ?? 0;
            final color = level < 20
                ? kSeverityColors[SeverityTier.critical]!
                : level < 50
                    ? kSeverityColors[SeverityTier.warning]!
                    : kSeverityColors[SeverityTier.good]!;
            return ListTile(
              title: Text(e.attr<String>('friendly_name', e.entityId),
                  style: TextStyle(color: tokens.textPrimary)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration:
                    BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text('${level.toStringAsFixed(0)}%', style: TextStyle(color: color)),
              ),
            );
          }),
        ],
      );
    },
  );
}
