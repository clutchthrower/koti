import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/doorbell_card.dart';

import 'card_test_harness.dart';

void main() {
  group('DoorbellCard', () {
    testWidgets('a binary_sensor doorbell shows its raw state and has no tap action',
        (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const DoorbellCard(entityId: 'binary_sensor.front_doorbell'),
        entities: [
          fakeEntity('binary_sensor.front_doorbell', 'off', {'friendly_name': 'Front Door'}),
        ],
      );

      expect(find.text('Front Door'), findsOneWidget);
      expect(find.text('off'), findsOneWidget);
      expect(find.text('Tap for live view'), findsNothing);
    });

    testWidgets('a camera-backed doorbell always shows the live-view prompt', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const DoorbellCard(entityId: 'camera.front_doorbell'),
        entities: [
          fakeEntity('camera.front_doorbell', 'idle', {'friendly_name': 'Front Door'}),
        ],
      );

      expect(find.text('Tap for live view'), findsOneWidget);
    });

    testWidgets('a label override wins over friendly_name', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const DoorbellCard(entityId: 'binary_sensor.front_doorbell', label: 'Custom Name'),
        entities: [
          fakeEntity('binary_sensor.front_doorbell', 'off', {'friendly_name': 'Front Door'}),
        ],
      );

      expect(find.text('Custom Name'), findsOneWidget);
      expect(find.text('Front Door'), findsNothing);
    });
  });
}
