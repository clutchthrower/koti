import 'package:flutter/material.dart';

import '../theme/koti_theme.dart';
import '../theme/tokens.dart';
import '../utils/device_mode.dart';
import '../widgets/koti_icon.dart';

/// Shared visual shell for the four hero-card group badges
/// (`hemma_badge_climate_group`, `_media_group`, `_light_group`,
/// `_presence_group`). Pill shape, padding, min-height, icon/font sizes are
/// literal values from `hemma_badge_base` / `themes/hemma/hemma.yaml`. Solid
/// translucent background stands in for the original's `backdrop-filter:
/// blur(14px)` per CLAUDE.md — no BackdropFilter.
class GroupBadge extends StatelessWidget {
  final String iconName;
  final String label;
  final String? subLabel;
  final Color? accent;
  final VoidCallback onTap;

  const GroupBadge({
    super.key,
    required this.iconName,
    required this.label,
    required this.onTap,
    this.subLabel,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final mode = deviceModeFor(context);
    final color = accent ?? tokens.activeColor;

    final iconSize = mode == DeviceMode.mobile ? 24.0 : 30.0;
    final fontSize = mode == DeviceMode.desktop || mode == DeviceMode.tablet ? 15.0 : 13.0;
    final minHeight = mode == DeviceMode.mobile ? 43.0 : 50.0;
    final padding = mode == DeviceMode.desktop
        ? const EdgeInsets.fromLTRB(9, 4, 15, 4)
        : mode == DeviceMode.tablet
            ? const EdgeInsets.fromLTRB(8, 3, 14, 3)
            : const EdgeInsets.fromLTRB(5, 4, 12, 4);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: padding,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: tokens.badgeBackground,
          borderRadius: BorderRadius.circular(tokens.badgeRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KotiIcon(iconName, size: iconSize, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Hanken Grotesk',
                    fontWeight: FontWeight.w600,
                    fontSize: fontSize,
                    color: const Color.fromRGBO(255, 255, 255, 0.85),
                  ),
                ),
                if (subLabel != null)
                  Text(
                    subLabel!,
                    style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontWeight: FontWeight.w500,
                      fontSize: fontSize - 2,
                      color: KotiTokens.secondaryOnDark,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
