import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/humidifier_card.dart';

import 'card_test_harness.dart';

void main() {
  group('HumidifierCard', () {
    testWidgets('off state shows Off and toggles on tap', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const HumidifierCard(entityId: 'humidifier.bedroom'),
        entities: [fakeEntity('humidifier.bedroom', 'off', {'friendly_name': 'Bedroom'})],
      );

      expect(find.text('Bedroom'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);

      await tester.tap(find.text('Bedroom'));
      await tester.pump();
      expect(harness.calls, ['humidifier.toggle humidifier.bedroom']);
    });

    testWidgets('on state shows On', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const HumidifierCard(entityId: 'humidifier.bedroom'),
        entities: [fakeEntity('humidifier.bedroom', 'on', {'friendly_name': 'Bedroom'})],
      );

      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('falls back to the entityId when friendly_name is missing', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const HumidifierCard(entityId: 'humidifier.bedroom'),
        entities: [fakeEntity('humidifier.bedroom', 'off')],
      );

      expect(find.text('humidifier.bedroom'), findsOneWidget);
    });
  });
}
