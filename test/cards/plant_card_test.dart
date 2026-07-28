import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/plant_card.dart';

import 'card_test_harness.dart';

void main() {
  group('PlantCard', () {
    testWidgets('all status attributes good reports Healthy and isn\'t active', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const PlantCard(plantEntityId: 'plant.monstera'),
        entities: [
          fakeEntity('plant.monstera', 'ok', {
            'friendly_name': 'Monstera',
            'moisture_status': 'good',
            'temperature_status': 'ok',
            'illuminance_status': 'good',
            'conductivity_status': 'ok',
          }),
        ],
      );

      expect(find.text('Monstera'), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);
    });

    testWidgets('no status attributes at all defaults to a healthy ratio of 1.0', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const PlantCard(plantEntityId: 'plant.monstera'),
        entities: [fakeEntity('plant.monstera', 'ok')],
      );

      expect(find.text('Healthy'), findsOneWidget);
    });

    testWidgets('a majority of bad statuses reports Critical', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const PlantCard(plantEntityId: 'plant.monstera'),
        entities: [
          fakeEntity('plant.monstera', 'problem', {
            'moisture_status': 'low',
            'temperature_status': 'low',
            'illuminance_status': 'low',
            'conductivity_status': 'ok',
          }),
        ],
      );

      expect(find.text('Critical'), findsOneWidget);
    });

    testWidgets('tapping opens the plant popup', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const PlantCard(plantEntityId: 'plant.monstera'),
        entities: [fakeEntity('plant.monstera', 'ok', {'friendly_name': 'Monstera'})],
      );

      await tester.tap(find.text('Monstera'));
      await tester.pumpAndSettle();
      expect(find.text('Plant'), findsOneWidget);
    });
  });
}
