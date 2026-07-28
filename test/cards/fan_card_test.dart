import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/fan_card.dart';
import 'package:koti/widgets/koti_switch.dart';

import 'card_test_harness.dart';

void main() {
  group('FanCard', () {
    testWidgets('off with no percentage shows Off', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const FanCard(entityId: 'fan.bedroom'),
        entities: [fakeEntity('fan.bedroom', 'off', {'friendly_name': 'Bedroom Fan'})],
      );

      expect(find.text('Bedroom Fan'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('on with a percentage shows the rounded speed', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const FanCard(entityId: 'fan.bedroom'),
        entities: [
          fakeEntity('fan.bedroom', 'on', {'friendly_name': 'Bedroom Fan', 'percentage': 66.7}),
        ],
      );

      expect(find.text('67%'), findsOneWidget);
    });

    testWidgets('on with no percentage falls back to plain "On"', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const FanCard(entityId: 'fan.bedroom'),
        entities: [fakeEntity('fan.bedroom', 'on')],
      );

      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('the trailing switch toggles the fan directly', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const FanCard(entityId: 'fan.bedroom'),
        entities: [fakeEntity('fan.bedroom', 'off')],
      );

      await tester.tap(find.byType(KotiSwitch));
      await tester.pump();
      expect(harness.calls, ['fan.toggle fan.bedroom']);
    });

    testWidgets('tapping the card opens fan controls with a speed slider', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const FanCard(entityId: 'fan.bedroom'),
        entities: [
          fakeEntity('fan.bedroom', 'on', {'friendly_name': 'Bedroom Fan', 'percentage': 50.0}),
        ],
      );

      await tester.tap(find.text('Bedroom Fan'));
      await tester.pumpAndSettle();
      expect(find.text('Speed'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });
  });
}
