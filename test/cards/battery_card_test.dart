import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/battery_card.dart';

import 'card_test_harness.dart';

void main() {
  group('BatteryCard', () {
    testWidgets('all batteries above threshold reports All Good', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const BatteryCard(),
        entities: [
          fakeEntity('sensor.tablet_battery', '80', {'device_class': 'battery'}),
          fakeEntity('sensor.remote_battery', '95', {'device_class': 'battery'}),
        ],
      );

      expect(find.text('Batteries'), findsOneWidget);
      expect(find.text('All Good'), findsOneWidget);
    });

    testWidgets('any battery at or below the threshold needs attention', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const BatteryCard(lowThreshold: 20),
        entities: [
          fakeEntity('sensor.tablet_battery', '80', {'device_class': 'battery'}),
          fakeEntity('sensor.remote_battery', '15', {'device_class': 'battery'}),
        ],
      );

      expect(find.text('Needs Attention'), findsOneWidget);
    });

    testWidgets('non-battery sensors are ignored', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const BatteryCard(),
        entities: [
          fakeEntity('sensor.temperature', '5', {'device_class': 'temperature'}),
        ],
      );

      expect(find.text('All Good'), findsOneWidget);
    });

    testWidgets('an entityFilter restricts which batteries are considered', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const BatteryCard(entityFilter: ['sensor.tablet_battery']),
        entities: [
          fakeEntity('sensor.tablet_battery', '80', {'device_class': 'battery'}),
          fakeEntity('sensor.remote_battery', '5', {'device_class': 'battery'}),
        ],
      );

      // remote_battery would flip this to "Needs Attention" if the filter
      // weren't applied.
      expect(find.text('All Good'), findsOneWidget);
    });

    testWidgets('tapping opens the battery popup', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const BatteryCard(),
        entities: [fakeEntity('sensor.tablet_battery', '80', {'device_class': 'battery'})],
      );

      await tester.tap(find.text('Batteries'));
      await tester.pumpAndSettle();
      expect(find.text('sensor.tablet_battery'), findsOneWidget);
    });
  });
}
