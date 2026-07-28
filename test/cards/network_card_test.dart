import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/network_card.dart';

import 'card_test_harness.dart';

void main() {
  group('NetworkCard', () {
    testWidgets('labels Download when download exceeds upload', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const NetworkCard(
          downloadSensorEntityId: 'sensor.download_speed',
          uploadSensorEntityId: 'sensor.upload_speed',
        ),
        entities: [
          fakeEntity('sensor.download_speed', '42.3'),
          fakeEntity('sensor.upload_speed', '5.1'),
        ],
      );

      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Download 42.3 Mbps'), findsOneWidget);
    });

    testWidgets('labels Upload when upload exceeds download', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const NetworkCard(
          downloadSensorEntityId: 'sensor.download_speed',
          uploadSensorEntityId: 'sensor.upload_speed',
        ),
        entities: [
          fakeEntity('sensor.download_speed', '2.0'),
          fakeEntity('sensor.upload_speed', '20.0'),
        ],
      );

      expect(find.text('Upload 20.0 Mbps'), findsOneWidget);
    });

    testWidgets('with no upload sensor, only download is considered', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const NetworkCard(downloadSensorEntityId: 'sensor.download_speed'),
        entities: [fakeEntity('sensor.download_speed', '15.0')],
      );

      expect(find.text('Download 15.0 Mbps'), findsOneWidget);
    });

    testWidgets('tapping opens the network popup', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const NetworkCard(downloadSensorEntityId: 'sensor.download_speed'),
        entities: [fakeEntity('sensor.download_speed', '15.0')],
      );

      await tester.tap(find.text('Network'));
      await tester.pumpAndSettle();
      expect(find.text('Network'), findsWidgets);
    });
  });
}
