import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/koti_theme.dart';
import '../utils/color_utils.dart';
import '../utils/device_mode.dart';
import '../widgets/koti_icon.dart';

/// Base tile every entity card in the grid is built from
/// (`hemma_entity.yaml` / `hemma_default.yaml` in the original dashboard).
/// Sizing/typography/colors below are literal values pulled from that file
/// and `themes/hemma/hemma.yaml`, not approximations.
///
/// Reproduces, without BackdropFilter or any per-frame blur:
/// - a 1px gradient "specular" border on the Glass variant only (the base
///   theme zeroes these colors to transparent in the original too)
/// - an active-state overlay driven by [active]
/// - a staggered fade/slide entrance keyed off [position]
/// - an optional circular progress ring and battery pill
class KotiEntityCard extends StatefulWidget {
  final String? iconName;
  /// Alternative to [iconName] for concepts the bundled icon set has no
  /// asset for (settings tiles, mostly) — a Material icon instead.
  final IconData? materialIcon;
  final String label;
  final String stateText;
  final bool active;
  final int position;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? progress; // 0..1, shown as a ring behind the icon
  final int? batteryPercent;
  final Widget? trailing; // used by KotiEntityActions variant

  const KotiEntityCard({
    super.key,
    this.iconName,
    this.materialIcon,
    required this.label,
    required this.stateText,
    required this.active,
    this.position = 0,
    this.onTap,
    this.onLongPress,
    this.progress,
    this.batteryPercent,
    this.trailing,
  }) : assert(iconName != null || materialIcon != null);

  @override
  State<KotiEntityCard> createState() => _KotiEntityCardState();
}

class _KotiEntityCardState extends State<KotiEntityCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // cubic-bezier(0.16, 1, 0.3, 1) from hemmaFadeInRight/hemmaFadeIn
    const easeOutExpo = Cubic(0.16, 1, 0.3, 1);
    _fade = CurvedAnimation(parent: _controller, curve: easeOutExpo);
    _slide = Tween<Offset>(
      begin: const Offset(0.10, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: easeOutExpo));
    // Stagger: desktop i*40ms, mobile floor(i/2)*60ms (2-col grid) — 40ms is
    // a safe single approximation good on both layouts.
    Future.delayed(Duration(milliseconds: widget.position * 40), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final mode = deviceModeFor(context);
    final portrait = mode == DeviceMode.mobile && isPortrait(context);

    final circleDiameter = portrait ? 38.0 : 44.0;
    final iconSize = portrait ? 22.0 : 25.0;
    final padding = mode == DeviceMode.desktop
        ? 20.0
        : mode == DeviceMode.tablet
            ? 18.0
            : 14.0;
    final nameSize = mode == DeviceMode.desktop
        ? 18.0
        : mode == DeviceMode.tablet
            ? 15.0
            : 14.0;
    final stateSize = mode == DeviceMode.desktop
        ? 15.0
        : mode == DeviceMode.tablet
            ? 13.0
            : 14.0;

    final nameColor = widget.active
        ? (portrait ? const Color.fromRGBO(0, 0, 0, 0.88) : tokens.entityName)
        : tokens.entityName;
    final stateColor = widget.active ? tokens.entityStateActive : tokens.entityState;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              gradient: tokens.borderGradient,
            ),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.cardRadius - 1),
                color: widget.active
                    ? Color.alphaBlend(tokens.entityBackgroundActive, tokens.entityBackground)
                    : tokens.entityBackground,
              ),
              // Original card anatomy: icon circle top-left, controls
              // top-right, name + state pinned to the bottom-left.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (widget.progress != null)
                            SizedBox(
                              width: circleDiameter + 6,
                              height: circleDiameter + 6,
                              child: CustomPaint(
                                painter: _RingPainter(
                                  progress: widget.progress!,
                                  color: tokens.activeColor,
                                  track: tokens.iconCircleBackground,
                                ),
                              ),
                            ),
                          KotiIconCircle(
                            iconName: widget.iconName,
                            iconColor: widget.active ? tokens.activeColor : tokens.textPrimary,
                            backgroundColor: tokens.iconCircleBackground,
                            diameter: circleDiameter,
                            iconSize: iconSize,
                            child: widget.materialIcon != null
                                ? Icon(widget.materialIcon,
                                    size: iconSize,
                                    color: widget.active
                                        ? tokens.activeColor
                                        : tokens.textPrimary)
                                : null,
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (widget.trailing != null) widget.trailing!,
                    ],
                  ),
                  const Spacer(),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontWeight: FontWeight.w600,
                      fontSize: nameSize,
                      height: 1.15,
                      color: nameColor,
                      shadows: const [Shadow(color: Color.fromRGBO(0, 0, 0, 0.35), blurRadius: 4, offset: Offset(0, 1))],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.stateText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Hanken Grotesk',
                            fontWeight: FontWeight.w500,
                            fontSize: stateSize,
                            height: 1.15,
                            color: stateColor,
                          ),
                        ),
                      ),
                      if (widget.batteryPercent != null)
                        _BatteryPill(percent: widget.batteryPercent!),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  _RingPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(1.5), 0, 2 * math.pi, false, trackPaint);
    canvas.drawArc(
      rect.deflate(1.5),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0, 1),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _BatteryPill extends StatelessWidget {
  final int percent;
  const _BatteryPill({required this.percent});

  @override
  Widget build(BuildContext context) {
    final color = percent <= 20
        ? kSeverityColors[SeverityTier.critical]!
        : percent <= 50
            ? kSeverityColors[SeverityTier.warning]!
            : kSeverityColors[SeverityTier.good]!;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$percent%',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
