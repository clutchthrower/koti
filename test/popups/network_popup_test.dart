import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/network_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showNetworkPopup', () {
    testWidgets('shows download/upload/ping when all three sensors are present', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showNetworkPopup(
          context,
          downloadSensorEntityId: 'sensor.download',
          uploadSensorEntityId: 'sensor.upload',
          pingSensorEntityId: 'sensor.ping',
        ),
        entities: [
          fakeEntity('sensor.download', '42.5'),
          fakeEntity('sensor.upload', '8.25'),
          fakeEntity('sensor.ping', '12'),
        ],
      );
      await harness.open(tester);

      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Download: 42.5 Mbps'), findsOneWidget);
      expect(find.text('Upload: 8.3 Mbps'), findsOneWidget);
      expect(find.text('Ping: 12 ms'), findsOneWidget);
    });

    testWidgets('with no upload/ping sensors, only download is shown', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showNetworkPopup(context, downloadSensorEntityId: 'sensor.download'),
        entities: [fakeEntity('sensor.download', '10')],
      );
      await harness.open(tester);

      expect(find.text('Download: 10.0 Mbps'), findsOneWidget);
      expect(find.textContaining('Upload'), findsNothing);
      expect(find.textContaining('Ping'), findsNothing);
    });

    testWidgets('a restart tile requires a confirm tap before calling the domain service',
        (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showNetworkPopup(
          context,
          downloadSensorEntityId: 'sensor.download',
          device1Name: 'Router',
          device1RestartEntityId: 'button.router_restart',
        ),
        entities: [fakeEntity('sensor.download', '10')],
      );
      await harness.open(tester);

      expect(find.text('Router'), findsOneWidget);
      await tester.tap(find.text('Router'));
      await tester.pump();
      expect(find.text('Confirm?'), findsOneWidget);
      expect(harness.calls, isEmpty);

      await tester.tap(find.text('Confirm?'));
      await tester.pump();
      expect(harness.calls, ['button.press button.router_restart']);
      expect(find.text('Done'), findsOneWidget);

      // "Done" reverts after 3s via a real Timer (HelperStore.handleRestartTap)
      // — let it fire so the test doesn't end with a pending timer.
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
