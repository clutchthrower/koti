import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/climate_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showClimatePopup', () {
    testWidgets('titles the popup after the room and shows every provided sensor', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showClimatePopup(
          context,
          roomName: 'Living Room',
          tempSensorEntityId: 'sensor.living_room_temp',
          humiditySensorEntityId: 'sensor.living_room_humidity',
          aqiSensorEntityId: 'sensor.living_room_aqi',
        ),
        entities: [
          fakeEntity('sensor.living_room_temp', '72'),
          fakeEntity('sensor.living_room_humidity', '45'),
          fakeEntity('sensor.living_room_aqi', '30'),
        ],
      );
      await harness.open(tester);

      expect(find.text('Living Room'), findsOneWidget);
      expect(find.text('72°'), findsOneWidget);
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(find.text('Humidity'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('AQI'), findsOneWidget);
    });

    testWidgets('omitted sensors simply don\'t render a tile', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showClimatePopup(
          context,
          roomName: 'Bedroom',
          tempSensorEntityId: 'sensor.bedroom_temp',
        ),
        entities: [fakeEntity('sensor.bedroom_temp', '68')],
      );
      await harness.open(tester);

      expect(find.text('68°'), findsOneWidget);
      expect(find.text('Humidity'), findsNothing);
      expect(find.text('AQI'), findsNothing);
    });
  });
}
