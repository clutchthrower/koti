import 'package:flutter/material.dart';

enum ColorModePref { system, light, dark }

/// Token architecture per SPECIFICATIONS.md Section 3, with literal values
/// pulled from the original `themes/hemma/hemma.yaml` / `hemma_glass.yaml`.
/// Per CLAUDE.md, no BackdropFilter/real-time blur is used — the original's
/// `backdrop-filter: blur()` surfaces are reproduced as solid low-opacity
/// colors at the same alpha the original used underneath its blur.
///
/// Always renders the Glass look (the original's Base variant is gone —
/// one considered default beats a user-facing toggle nobody needs).
class KotiTokens {
  final Brightness brightness;
  final Color accentColor;
  final double cardTransparency; // 0..1, alpha multiplier for surfaces

  const KotiTokens({
    required this.brightness,
    required this.accentColor,
    required this.cardTransparency,
  });

  bool get isDark => brightness == Brightness.dark;

  // --- Card surfaces (hemma-entity-background) ---
  Color get entityBackground => (isDark
          ? const Color.fromRGBO(0, 0, 0, 0.4)
          : const Color.fromRGBO(0, 0, 0, 0.25))
      .withValues(alpha: (isDark ? 0.4 : 0.25) * cardTransparency);

  Color get entityBackgroundActive =>
      isDark ? const Color.fromRGBO(255, 255, 255, 0.30) : const Color.fromRGBO(255, 255, 255, 0.35);

  Color get cardBackground =>
      isDark ? const Color.fromRGBO(0, 0, 0, 0.4) : const Color.fromRGBO(0, 0, 0, 0.2);

  // Warm brown-charcoal instead of a cold near-black — reads as neutral
  // rather than "dark UI slapped on top", and harmonizes with the tan
  // splash/brand color instead of clashing with it.
  Color get dialogBackground => isDark
      ? const Color.fromRGBO(33, 29, 24, 0.9)
      : const Color.fromRGBO(33, 29, 24, 0.9);

  Color get navBackground =>
      isDark ? const Color.fromRGBO(33, 29, 24, 0.55) : const Color.fromRGBO(33, 29, 24, 0.5);

  Color get badgeBackground =>
      isDark ? const Color.fromRGBO(0, 0, 0, 0.5) : const Color.fromRGBO(0, 0, 0, 0.35);

  Color get activeColor => accentColor;
  static const defaultAccent = Color(0xFF6EBAFF); // --primary-color / --accent-color

  Color get puckCoolColor => const Color(0xFF0091FF); // hemma-color-deep-blue
  Color get puckHeatColor => const Color(0xFFff9230); // hemma-color-orange

  Color get iconCircleBackground => const Color.fromRGBO(255, 255, 255, 0.10);

  // --- Text ---
  Color get textPrimary =>
      isDark ? const Color.fromRGBO(255, 255, 255, 0.98) : const Color.fromRGBO(255, 255, 255, 0.95);
  Color get textSecondary => const Color.fromRGBO(240, 240, 240, 0.9);

  Color get entityName => const Color.fromRGBO(255, 255, 255, 0.95);
  Color get entityState => const Color.fromRGBO(255, 255, 255, 0.65);
  Color get entityStateActive => const Color.fromRGBO(255, 255, 255, 0.80);

  // --- Layout constants (hemma_entity_layout.yaml) ---
  double get navHeight => 64;
  double get cardRadius => 28;
  double get badgeRadius => 9999;
  double get pageGutterMobile => 11;
  double get tilesTopPortrait => 350;

  /// Fixed tile size per breakpoint, from `hemma_entity_layout.yaml`.
  static const tileSizeDesktop = Size(290, 200);
  static const tileSizeTablet = Size(220, 160);
  static const tileSizeMobilePortrait = Size(180, 116);
  static const tileSizeMobileLandscape = Size(160, 120);

  /// Specular 1px gradient border — the Glass look's glass-edge highlight.
  Gradient get borderGradient {
    final start = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.20)
        : const Color.fromRGBO(255, 255, 255, 0.24);
    final mid = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.13)
        : const Color.fromRGBO(255, 255, 255, 0.16);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [start, mid, mid, start],
    );
  }

  KotiTokens copyWith({
    Brightness? brightness,
    Color? accentColor,
    double? cardTransparency,
  }) {
    return KotiTokens(
      brightness: brightness ?? this.brightness,
      accentColor: accentColor ?? this.accentColor,
      cardTransparency: cardTransparency ?? this.cardTransparency,
    );
  }
}
