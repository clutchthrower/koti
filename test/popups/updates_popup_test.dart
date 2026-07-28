import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/updates_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showUpdatesPopup', () {
    testWidgets('with no pending updates, shows the up-to-date message', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showUpdatesPopup(context),
        entities: [fakeEntity('update.core', 'off')],
      );
      await harness.open(tester);

      expect(find.text('Everything is up to date'), findsOneWidget);
    });

    testWidgets('lists each pending update with its version bump', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showUpdatesPopup(context),
        entities: [
          fakeEntity('update.core', 'on', {
            'friendly_name': 'Home Assistant Core',
            'installed_version': '2026.6.0',
            'latest_version': '2026.7.0',
          }),
          fakeEntity('update.supervisor', 'off'),
        ],
      );
      await harness.open(tester);

      expect(find.text('Home Assistant Core'), findsOneWidget);
      expect(find.text('2026.6.0 → 2026.7.0'), findsOneWidget);
      expect(find.text('Everything is up to date'), findsNothing);
    });
  });
}
