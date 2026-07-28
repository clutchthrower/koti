/// Replicates `sensor.hemma_mobile_dynamic_background`: derives a phase from
/// `sun.sun`'s elevation/rising attributes, maps it to a background bucket,
/// and appends the `-dark` suffix when the sun is below the horizon.
enum SunPhase { sunset, dawn, morning, goldenhour, afternoon, midday }

SunPhase computeSunPhase({required double elevation, required bool rising}) {
  if (elevation < -6) return SunPhase.sunset;
  if (elevation < 6) return rising ? SunPhase.dawn : SunPhase.sunset;
  if (elevation < 24) return rising ? SunPhase.morning : SunPhase.goldenhour;
  if (elevation < 50) return rising ? SunPhase.morning : SunPhase.afternoon;
  return SunPhase.midday;
}

String computeDynamicBackgroundFile({
  required double elevation,
  required bool rising,
  required bool belowHorizon,
}) {
  final phase = computeSunPhase(elevation: elevation, rising: rising);
  final bucket = switch (phase) {
    SunPhase.morning || SunPhase.dawn => 'morning',
    SunPhase.sunset => 'night',
    _ => 'day',
  };
  final darkSuffix = belowHorizon ? '-dark' : '';
  return 'mobile-$bucket$darkSuffix.jpg';
}
