import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koti/popups/media_popup.dart';

import 'popup_test_harness.dart';

void main() {
  group('showMediaPopup', () {
    testWidgets('shows track/artist metadata and a pause icon while playing', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showMediaPopup(context, entityId: 'media_player.living_room', title: 'Living Room'),
        entities: [
          fakeEntity('media_player.living_room', 'playing', {
            'media_title': 'One More Time',
            'media_artist': 'Daft Punk',
          }),
        ],
      );
      await harness.open(tester);

      expect(find.text('Living Room'), findsOneWidget);
      expect(find.text('One More Time'), findsOneWidget);
      expect(find.text('Daft Punk'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('with no track metadata, shows the state label instead', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showMediaPopup(context, entityId: 'media_player.living_room'),
        entities: [fakeEntity('media_player.living_room', 'paused')],
      );
      await harness.open(tester);

      expect(find.text('Media'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('the power button calls turn_on when off, turn_off when on', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showMediaPopup(context, entityId: 'media_player.living_room'),
        entities: [fakeEntity('media_player.living_room', 'off')],
      );
      await harness.open(tester);

      await tester.tap(find.byIcon(Icons.power_settings_new));
      await tester.pump();
      expect(harness.calls, ['media_player.turn_on media_player.living_room']);
    });

    testWidgets('previous/play-pause/next call their respective services', (tester) async {
      final harness = PopupTestHarness();
      await harness.pump(
        tester,
        (context) => showMediaPopup(context, entityId: 'media_player.living_room'),
        entities: [fakeEntity('media_player.living_room', 'playing')],
      );
      await harness.open(tester);

      await tester.tap(find.byIcon(Icons.skip_previous));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.skip_next));
      await tester.pump();

      expect(harness.calls, [
        'media_player.media_previous_track media_player.living_room',
        'media_player.media_play_pause media_player.living_room',
        'media_player.media_next_track media_player.living_room',
      ]);
    });
  });
}
