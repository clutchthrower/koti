import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/camera_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showCameraPopup', () {
    testWidgets('defaults the title to "Camera" with no override', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showCameraPopup(context, entityId: 'camera.front_door'),
      );
      await harness.open(tester);

      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('uses the provided title when given', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showCameraPopup(context, entityId: 'camera.front_door', title: 'Front Door'),
      );
      await harness.open(tester);

      expect(find.text('Front Door'), findsOneWidget);
      expect(find.text('Camera'), findsNothing);
    });
  });
}
