import 'package:flutter_test/flutter_test.dart';

import 'package:koti/utils/sun_phase.dart';

void main() {
  group('computeSunPhase', () {
    test('below -6 degrees is always sunset, regardless of rising', () {
      expect(computeSunPhase(elevation: -10, rising: true), SunPhase.sunset);
      expect(computeSunPhase(elevation: -10, rising: false), SunPhase.sunset);
    });

    test('between -6 and 6 degrees is dawn while rising, sunset while setting', () {
      expect(computeSunPhase(elevation: 0, rising: true), SunPhase.dawn);
      expect(computeSunPhase(elevation: 0, rising: false), SunPhase.sunset);
    });

    test('between 6 and 24 degrees is morning while rising, goldenhour while setting', () {
      expect(computeSunPhase(elevation: 12, rising: true), SunPhase.morning);
      expect(computeSunPhase(elevation: 12, rising: false), SunPhase.goldenhour);
    });

    test('between 24 and 50 degrees is morning while rising, afternoon while setting', () {
      expect(computeSunPhase(elevation: 40, rising: true), SunPhase.morning);
      expect(computeSunPhase(elevation: 40, rising: false), SunPhase.afternoon);
    });

    test('50 degrees and above is always midday', () {
      expect(computeSunPhase(elevation: 60, rising: true), SunPhase.midday);
      expect(computeSunPhase(elevation: 60, rising: false), SunPhase.midday);
    });

    test('boundaries are inclusive on the lower phase', () {
      expect(computeSunPhase(elevation: 6, rising: true), SunPhase.morning);
      expect(computeSunPhase(elevation: 24, rising: true), SunPhase.morning);
      expect(computeSunPhase(elevation: 50, rising: true), SunPhase.midday);
    });
  });

  group('computeDynamicBackgroundFile', () {
    test('morning and dawn both map to the morning bucket', () {
      expect(
        computeDynamicBackgroundFile(elevation: 12, rising: true, belowHorizon: false),
        'mobile-morning.jpg',
      );
      expect(
        computeDynamicBackgroundFile(elevation: 0, rising: true, belowHorizon: false),
        'mobile-morning.jpg',
      );
    });

    test('sunset maps to the night bucket', () {
      expect(
        computeDynamicBackgroundFile(elevation: -10, rising: false, belowHorizon: true),
        'mobile-night-dark.jpg',
      );
    });

    test('goldenhour, afternoon, and midday all fall back to the day bucket', () {
      expect(
        computeDynamicBackgroundFile(elevation: 12, rising: false, belowHorizon: false),
        'mobile-day.jpg',
      );
      expect(
        computeDynamicBackgroundFile(elevation: 40, rising: false, belowHorizon: false),
        'mobile-day.jpg',
      );
      expect(
        computeDynamicBackgroundFile(elevation: 60, rising: true, belowHorizon: false),
        'mobile-day.jpg',
      );
    });

    test('appends -dark only when below the horizon', () {
      expect(
        computeDynamicBackgroundFile(elevation: 60, rising: true, belowHorizon: true),
        'mobile-day-dark.jpg',
      );
      expect(
        computeDynamicBackgroundFile(elevation: 60, rising: true, belowHorizon: false),
        'mobile-day.jpg',
      );
    });
  });
}
