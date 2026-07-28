import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/battery_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showBatteryPopup', () {
    testWidgets('summarizes critical/low/good counts and lists each battery', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showBatteryPopup(context, null, 20),
        entities: [
          fakeEntity('sensor.a_battery', '5', {'device_class': 'battery', 'friendly_name': 'A'}),
          fakeEntity('sensor.b_battery', '15', {'device_class': 'battery', 'friendly_name': 'B'}),
          fakeEntity('sensor.c_battery', '90', {'device_class': 'battery', 'friendly_name': 'C'}),
        ],
      );
      await harness.open(tester);

      expect(find.text('Critical: 1  ·  Low: 1  ·  Good: 1'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('5%'), findsOneWidget);
    });

    testWidgets('an entityFilter restricts which batteries are listed', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showBatteryPopup(context, ['sensor.a_battery'], 20),
        entities: [
          fakeEntity('sensor.a_battery', '50', {'device_class': 'battery', 'friendly_name': 'A'}),
          fakeEntity('sensor.b_battery', '50', {'device_class': 'battery', 'friendly_name': 'B'}),
        ],
      );
      await harness.open(tester);

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsNothing);
      expect(find.text('Critical: 0  ·  Low: 0  ·  Good: 1'), findsOneWidget);
    });
  });
}
