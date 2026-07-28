import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/energy_card.dart';

import 'card_test_harness.dart';

void main() {
  group('EnergyCard', () {
    testWidgets('shows watts rounded to the nearest whole number', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const EnergyCard(powerSensorEntityId: 'sensor.home_power'),
        entities: [fakeEntity('sensor.home_power', '123.7', {'friendly_name': 'Home Power'})],
      );

      expect(find.text('Home Power'), findsOneWidget);
      expect(find.text('124W'), findsOneWidget);
    });

    testWidgets('an unparsable state falls back to 0W, not active', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const EnergyCard(powerSensorEntityId: 'sensor.home_power'),
        entities: [fakeEntity('sensor.home_power', 'unavailable')],
      );

      expect(find.text('0W'), findsOneWidget);
    });

    testWidgets('tapping opens the energy popup', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const EnergyCard(powerSensorEntityId: 'sensor.home_power'),
        entities: [fakeEntity('sensor.home_power', '150', {'friendly_name': 'Home Power'})],
      );

      await tester.tap(find.text('Home Power'));
      await tester.pumpAndSettle();
      expect(find.text('Energy'), findsOneWidget);
    });
  });
}
