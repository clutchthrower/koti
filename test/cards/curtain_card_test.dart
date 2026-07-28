import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/curtain_card.dart';

import 'card_test_harness.dart';

void main() {
  group('CurtainCard', () {
    testWidgets('shows position percent when available', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CurtainCard(entityId: 'cover.living_room'),
        entities: [
          fakeEntity('cover.living_room', 'open', {
            'friendly_name': 'Living Room Curtains',
            'current_position': 75.0,
          }),
        ],
      );

      expect(find.text('Living Room Curtains'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
    });

    testWidgets('with no position, falls back to the raw state', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CurtainCard(entityId: 'cover.living_room'),
        entities: [fakeEntity('cover.living_room', 'closed')],
      );

      expect(find.text('closed'), findsOneWidget);
    });

    testWidgets('"opening" counts as open for icon/active purposes', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CurtainCard(entityId: 'cover.living_room'),
        entities: [fakeEntity('cover.living_room', 'opening')],
      );

      expect(find.text('opening'), findsOneWidget);
    });

    testWidgets('tapping opens cover controls that call the cover domain', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const CurtainCard(entityId: 'cover.living_room'),
        entities: [
          fakeEntity('cover.living_room', 'open', {
            'friendly_name': 'Living Room Curtains',
            'current_position': 50.0,
          }),
        ],
      );

      await tester.tap(find.text('Living Room Curtains'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open'), findsOneWidget);

      await tester.tap(find.byTooltip('Open'));
      await tester.pump();
      expect(harness.calls, ['cover.open_cover cover.living_room']);
    });
  });
}
