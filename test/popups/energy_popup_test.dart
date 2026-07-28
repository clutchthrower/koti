import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/energy_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showEnergyPopup', () {
    testWidgets('shows the current wattage rounded to a whole watt', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showEnergyPopup(context, 'sensor.home_power'),
        entities: [fakeEntity('sensor.home_power', '842.6')],
      );
      await harness.open(tester);

      expect(find.text('Energy'), findsOneWidget);
      expect(find.text('843 W'), findsOneWidget);
      expect(find.text('Real-time power draw'), findsOneWidget);
    });

    testWidgets('an unparsable state reads as 0 W', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showEnergyPopup(context, 'sensor.home_power'),
        entities: [fakeEntity('sensor.home_power', 'unavailable')],
      );
      await harness.open(tester);

      expect(find.text('0 W'), findsOneWidget);
    });
  });
}
