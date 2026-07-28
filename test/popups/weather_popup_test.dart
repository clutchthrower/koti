import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/weather_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showWeatherForecastPopup', () {
    testWidgets('shows the current temperature and a readable condition label', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showWeatherForecastPopup(context, 'weather.home'),
        entities: [fakeEntity('weather.home', 'partlycloudy', {'temperature': 71.6})],
      );
      await harness.open(tester);

      expect(find.text('Weather'), findsOneWidget);
      expect(find.text('72°'), findsOneWidget);
      expect(find.text('Partly Cloudy'), findsOneWidget);

      // get_forecasts has no real HA server to answer it here — let that
      // network attempt fail and settle to the "unavailable" fallback
      // rather than asserting on data this harness can't actually supply.
      await tester.pumpAndSettle();
      expect(find.text('Forecast unavailable for this weather entity'), findsOneWidget);
    });

    testWidgets('falls back to the raw state when temperature is missing', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showWeatherForecastPopup(context, 'weather.home'),
        entities: [fakeEntity('weather.home', 'sunny')],
      );
      await harness.open(tester);

      expect(find.text('sunny'), findsOneWidget);
      expect(find.text('Sunny'), findsOneWidget);
    });
  });
}
