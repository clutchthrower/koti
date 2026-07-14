import 'package:flutter_test/flutter_test.dart';

import 'package:koti/api/ha_registry.dart';
import 'package:koti/models/entity_state.dart';
import 'package:koti/models/room_config.dart';

EntityState _e(String id, String state, [Map<String, dynamic>? attrs]) =>
    EntityState(
      entityId: id,
      state: state,
      attributes: attrs ?? const {},
      lastChanged: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

void main() {
  test('buildSecurityRoom returns null when nothing security-relevant exists', () {
    final states = [
      _e('light.kitchen', 'on'),
      _e('media_player.tv', 'playing'),
    ];
    expect(buildSecurityRoom(states), isNull);
  });

  test('buildSecurityRoom collects cameras, locks, doorbells, and motion', () {
    final states = [
      _e('camera.front_door', 'idle'),
      _e('camera.backyard', 'idle'),
      _e('lock.front_door', 'locked'),
      _e('lock.back_door', 'unlocked'),
      _e('binary_sensor.front_doorbell', 'off'),
      _e('binary_sensor.hallway_motion', 'off', {'device_class': 'motion'}),
      _e('binary_sensor.garage_motion', 'on', {'device_class': 'motion'}),
      // Noise that should be ignored.
      _e('light.kitchen', 'on'),
      _e('binary_sensor.window_open', 'off', {'device_class': 'window'}),
    ];

    final room = buildSecurityRoom(states);

    expect(room, isNotNull);
    expect(room!.id, 'security');
    expect(room.name, 'Security');
    expect(room.lockEntities, ['lock.front_door', 'lock.back_door']);

    final cameraCards =
        room.cards.where((c) => c.type == KotiCardType.camera).toList();
    expect(cameraCards.map((c) => c.entityId),
        containsAll(['camera.front_door', 'camera.backyard']));

    final lockCards = room.cards.where((c) => c.type == KotiCardType.lock).toList();
    expect(lockCards.map((c) => c.entityId),
        containsAll(['lock.front_door', 'lock.back_door']));

    final doorbellCards =
        room.cards.where((c) => c.type == KotiCardType.doorbell).toList();
    expect(doorbellCards.single.entityId, 'binary_sensor.front_doorbell');

    final motionCards = room.cards.where((c) => c.type == KotiCardType.motion).toList();
    expect(motionCards, hasLength(1));
    expect(
      [motionCards.single.entityId, ...motionCards.single.extraEntityIds],
      containsAll(['binary_sensor.hallway_motion', 'binary_sensor.garage_motion']),
    );

    // The unrelated window sensor shouldn't have produced a card of its own.
    expect(room.cards.length,
        cameraCards.length + lockCards.length + doorbellCards.length + motionCards.length);
  });

  test('buildSecurityRoom caps each category so a huge instance stays usable', () {
    final states = [
      for (var i = 0; i < 12; i++) _e('camera.cam_$i', 'idle'),
      for (var i = 0; i < 12; i++) _e('lock.lock_$i', 'locked'),
    ];

    final room = buildSecurityRoom(states)!;
    expect(room.cards.where((c) => c.type == KotiCardType.camera).length, 8);
    expect(room.cards.where((c) => c.type == KotiCardType.lock).length, 8);
    expect(room.lockEntities.length, 8);
  });
}
