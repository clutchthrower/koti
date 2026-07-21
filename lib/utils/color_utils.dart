import 'package:flutter/material.dart';

/// Replicates `sensor.hemma_temp_color` / `sensor.hemma_humidity_color` and
/// the literal color values from `hemma_badge_temp.yaml` /
/// `hemma_badge_humidity.yaml` / `themes/hemma/hemma.yaml`.
enum TempColorTier {
  veryCold,
  cool,
  comfortable,
  warm,
  hot,
  veryHot,
}

TempColorTier tempColorTier(double fahrenheit) {
  if (fahrenheit <= 65) return TempColorTier.veryCold;
  if (fahrenheit <= 70) return TempColorTier.cool;
  if (fahrenheit <= 76) return TempColorTier.comfortable;
  if (fahrenheit <= 81) return TempColorTier.warm;
  if (fahrenheit <= 85) return TempColorTier.hot;
  return TempColorTier.veryHot;
}

const Map<TempColorTier, Color> kTempColors = {
  TempColorTier.veryCold: Color(0xFF0091FF), // hemma-color-deep-blue
  TempColorTier.cool: Color(0xFF3CD3FE), // hemma-color-ice
  TempColorTier.comfortable: Color(0xFF67F5A0), // hemma-color-green-soft
  TempColorTier.warm: Color(0xFFFFCC00), // hemma-color-yellow
  TempColorTier.hot: Color(0xFFFF9230), // hemma-color-orange
  TempColorTier.veryHot: Color(0xFFFF4245), // hemma-color-red
};

Color colorForTempF(double fahrenheit) => kTempColors[tempColorTier(fahrenheit)]!;

enum HumidityColorTier { dry, normal, high }

HumidityColorTier humidityColorTier(double percent) {
  if (percent <= 29.99) return HumidityColorTier.dry;
  if (percent >= 61) return HumidityColorTier.high;
  return HumidityColorTier.normal;
}

const Map<HumidityColorTier, Color> kHumidityColors = {
  HumidityColorTier.dry: Color(0xFFFFB254), // hemma-color-amber
  HumidityColorTier.normal: Color(0xFF00C3D0), // hemma-color-teal
  HumidityColorTier.high: Color(0xFF3CD3FE), // hemma-color-ice
};

Color colorForHumidity(double percent) =>
    kHumidityColors[humidityColorTier(percent)]!;

/// A single good→critical color ramp, shared by every value-to-color popup
/// that isn't temperature/humidity (AQI, battery level, wattage, network
/// restart state) — these used to each declare their own copy of the same
/// four hex values independently; each caller still owns its own
/// thresholds (a battery's "low" cutoff isn't a wattage's), only the colors
/// themselves are shared here.
enum SeverityTier { good, warning, elevated, critical }

const Map<SeverityTier, Color> kSeverityColors = {
  SeverityTier.good: Color(0xFF63C58B),
  SeverityTier.warning: Color(0xFFE8C34F),
  SeverityTier.elevated: Color(0xFFE8934F),
  SeverityTier.critical: Color(0xFFE85D4F),
};
