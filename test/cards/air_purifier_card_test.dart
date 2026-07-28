import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/air_purifier_card.dart';

import 'card_test_harness.dart';

void main() {
  group('AirPurifierCard', () {
    testWidgets('a fan-domain purifier toggles via the fan domain', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const AirPurifierCard(entityId: 'fan.air_purifier'),
        entities: [fakeEntity('fan.air_purifier', 'off', {'friendly_name': 'Air Purifier'})],
      );

      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.text('Air Purifier'));
      await tester.pump();
      expect(harness.calls, ['fan.toggle fan.air_purifier']);
    });

    testWidgets('a humidifier-domain purifier toggles via the humidifier domain', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const AirPurifierCard(entityId: 'humidifier.air_purifier'),
        entities: [fakeEntity('humidifier.air_purifier', 'on', {'friendly_name': 'Air Purifier'})],
      );

      expect(find.text('On'), findsOneWidget);
      await tester.tap(find.text('Air Purifier'));
      await tester.pump();
      expect(harness.calls, ['humidifier.toggle humidifier.air_purifier']);
    });
  });
}
