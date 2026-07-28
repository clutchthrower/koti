import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/plant_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showPlantPopup', () {
    testWidgets('shows every present sensor reading', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showPlantPopup(context, 'plant.monstera'),
        entities: [
          fakeEntity('plant.monstera', 'ok', {
            'moisture': 45,
            'illuminance': 3200,
            'temperature': 21,
            'conductivity': 800,
          }),
        ],
      );
      await harness.open(tester);

      expect(find.text('Plant'), findsOneWidget);
      expect(find.text('Moisture: 45'), findsOneWidget);
      expect(find.text('Illuminance: 3200'), findsOneWidget);
      expect(find.text('Temperature: 21'), findsOneWidget);
      expect(find.text('Conductivity: 800'), findsOneWidget);
    });

    testWidgets('missing sensor attributes are simply omitted', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showPlantPopup(context, 'plant.monstera'),
        entities: [fakeEntity('plant.monstera', 'ok', {'moisture': 45})],
      );
      await harness.open(tester);

      expect(find.text('Moisture: 45'), findsOneWidget);
      expect(find.textContaining('Illuminance'), findsNothing);
    });
  });
}
