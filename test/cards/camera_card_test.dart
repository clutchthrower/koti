import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/camera_card.dart';

import 'card_test_harness.dart';

void main() {
  group('CameraCard', () {
    testWidgets('with no entity state, shows Unavailable and has no tap action', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CameraCard(entityId: 'camera.front_door'),
        entities: const [],
      );

      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Tap for live view'), findsNothing);
    });

    testWidgets('an available camera invites a tap for the live view', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CameraCard(entityId: 'camera.front_door'),
        entities: [fakeEntity('camera.front_door', 'idle', {'friendly_name': 'Front Door'})],
      );

      expect(find.text('Front Door'), findsOneWidget);
      expect(find.text('Tap for live view'), findsOneWidget);

      await tester.tap(find.text('Front Door'));
      await tester.pumpAndSettle();
      expect(find.text('Front Door'), findsWidgets);
    });

    testWidgets('an unavailable state string is treated as not available', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CameraCard(entityId: 'camera.front_door'),
        entities: [fakeEntity('camera.front_door', 'unavailable')],
      );

      expect(find.text('Unavailable'), findsOneWidget);
    });

    testWidgets('a motion sensor going active shows the "Motion detected" caption', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CameraCard(entityId: 'camera.front_door', motionEntityId: 'binary_sensor.front_motion'),
        entities: [
          fakeEntity('camera.front_door', 'idle', {'friendly_name': 'Front Door'}),
          fakeEntity('binary_sensor.front_motion', 'on'),
        ],
      );

      expect(find.text('Motion detected'), findsOneWidget);
    });

    testWidgets('a label override wins over friendly_name', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CameraCard(entityId: 'camera.front_door', label: 'Custom'),
        entities: [fakeEntity('camera.front_door', 'idle', {'friendly_name': 'Front Door'})],
      );

      expect(find.text('Custom'), findsOneWidget);
    });
  });
}
