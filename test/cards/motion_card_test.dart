import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/motion_card.dart';
import 'package:koti/models/entity_state.dart';

import 'card_test_harness.dart';

void main() {
  group('MotionCard', () {
    testWidgets('no sensor on reports No Motion', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const MotionCard(sensorEntityIds: ['binary_sensor.hallway', 'binary_sensor.kitchen']),
        entities: [
          fakeEntity('binary_sensor.hallway', 'off'),
          fakeEntity('binary_sensor.kitchen', 'off'),
        ],
      );

      expect(find.text('No Motion'), findsOneWidget);
    });

    testWidgets('the first sensor reporting on drives the label', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const MotionCard(
          sensorEntityIds: ['binary_sensor.hallway', 'binary_sensor.kitchen'],
          labels: ['Hallway', 'Kitchen'],
        ),
        entities: [
          fakeEntity('binary_sensor.hallway', 'off'),
          fakeEntity('binary_sensor.kitchen', 'on'),
        ],
      );

      expect(find.text('Kitchen'), findsOneWidget);
    });

    testWidgets('an active sensor beyond the labels list falls back to "Motion"', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const MotionCard(sensorEntityIds: ['binary_sensor.hallway']),
        entities: [fakeEntity('binary_sensor.hallway', 'on')],
      );

      expect(find.text('Motion'), findsWidgets);
    });

    testWidgets('tapping while idle surfaces the most recently changed sensor', (tester) async {
      final harness = CardTestHarness();
      final now = DateTime.now();
      await harness.pump(
        tester,
        const MotionCard(sensorEntityIds: ['binary_sensor.hallway', 'binary_sensor.kitchen']),
        entities: [
          EntityState(
            entityId: 'binary_sensor.hallway',
            state: 'off',
            attributes: const {},
            lastChanged: now.subtract(const Duration(minutes: 10)),
            lastUpdated: now,
          ),
          EntityState(
            entityId: 'binary_sensor.kitchen',
            state: 'off',
            attributes: const {},
            lastChanged: now,
            lastUpdated: now,
          ),
        ],
      );

      await tester.tap(find.text('Motion').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('binary_sensor.kitchen'), findsOneWidget);
    });
  });
}
