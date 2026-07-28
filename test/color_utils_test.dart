import 'package:flutter_test/flutter_test.dart';

import 'package:koti/utils/color_utils.dart';

void main() {
  group('tempColorTier / colorForTempF', () {
    test('tiers follow the documented Fahrenheit breakpoints', () {
      expect(tempColorTier(65), TempColorTier.veryCold);
      expect(tempColorTier(66), TempColorTier.cool);
      expect(tempColorTier(70), TempColorTier.cool);
      expect(tempColorTier(71), TempColorTier.comfortable);
      expect(tempColorTier(76), TempColorTier.comfortable);
      expect(tempColorTier(77), TempColorTier.warm);
      expect(tempColorTier(81), TempColorTier.warm);
      expect(tempColorTier(82), TempColorTier.hot);
      expect(tempColorTier(85), TempColorTier.hot);
      expect(tempColorTier(86), TempColorTier.veryHot);
    });

    test('colorForTempF resolves through kTempColors', () {
      expect(colorForTempF(50), kTempColors[TempColorTier.veryCold]);
      expect(colorForTempF(90), kTempColors[TempColorTier.veryHot]);
    });
  });

  group('humidityColorTier / colorForHumidity', () {
    test('tiers follow the documented percent breakpoints', () {
      expect(humidityColorTier(29.99), HumidityColorTier.dry);
      expect(humidityColorTier(30), HumidityColorTier.normal);
      expect(humidityColorTier(60.99), HumidityColorTier.normal);
      expect(humidityColorTier(61), HumidityColorTier.high);
    });

    test('colorForHumidity resolves through kHumidityColors', () {
      expect(colorForHumidity(10), kHumidityColors[HumidityColorTier.dry]);
      expect(colorForHumidity(75), kHumidityColors[HumidityColorTier.high]);
    });
  });

  group('batteryTier / colorForBattery', () {
    test('tiers follow the documented percent breakpoints', () {
      expect(batteryTier(10), BatteryTier.critical);
      expect(batteryTier(11), BatteryTier.low);
      expect(batteryTier(20), BatteryTier.low);
      expect(batteryTier(21), BatteryTier.good);
    });

    test('colorForBattery resolves through kBatteryColors', () {
      expect(colorForBattery(5), kBatteryColors[BatteryTier.critical]);
      expect(colorForBattery(100), kBatteryColors[BatteryTier.good]);
    });
  });

  test('kSeverityColors defines all four tiers', () {
    expect(kSeverityColors.keys.toSet(), SeverityTier.values.toSet());
  });
}
