import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koti/cards/media_card.dart';

import 'card_test_harness.dart';

void main() {
  group('MediaCard', () {
    testWidgets('shows "artist — title" when both are present', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const MediaCard(entityId: 'media_player.living_room'),
        entities: [
          fakeEntity('media_player.living_room', 'playing', {
            'friendly_name': 'Living Room',
            'media_artist': 'Daft Punk',
            'media_title': 'One More Time',
          }),
        ],
      );

      expect(find.text('Daft Punk — One More Time'), findsOneWidget);
    });

    testWidgets('falls back to app_name with no track metadata', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const MediaCard(entityId: 'media_player.living_room'),
        entities: [
          fakeEntity('media_player.living_room', 'playing', {'app_name': 'Spotify'}),
        ],
      );

      expect(find.text('Spotify'), findsOneWidget);
    });

    testWidgets('falls back to the raw state with no metadata at all', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const MediaCard(entityId: 'media_player.living_room'),
        entities: [fakeEntity('media_player.living_room', 'idle')],
      );

      expect(find.text('idle'), findsOneWidget);
    });

    testWidgets('the trailing play/pause button calls media_play_pause directly', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const MediaCard(entityId: 'media_player.living_room'),
        entities: [fakeEntity('media_player.living_room', 'playing', {'media_title': 'Song'})],
      );

      await tester.tap(find.byIcon(Icons.pause_circle_outline));
      await tester.pump();
      expect(harness.calls, ['media_player.media_play_pause media_player.living_room']);
    });

    testWidgets('a label override wins over friendly_name', (tester) async {
      final harness = CardTestHarness();
      await harness.pump(
        tester,
        const MediaCard(entityId: 'media_player.living_room', label: 'Custom'),
        entities: [
          fakeEntity('media_player.living_room', 'idle', {'friendly_name': 'Living Room'}),
        ],
      );

      expect(find.text('Custom'), findsOneWidget);
    });
  });
}
