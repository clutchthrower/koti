import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/entity_state.dart';
import '../models/room_config.dart';

/// Pulls Home Assistant's Area Registry + Entity/Device Registries and
/// turns each Area into a [RoomConfig] with its entities auto-assigned by
/// domain/device_class — spec 1.5's "Auto Discovery" extended to rooms, not
/// just the server itself. Registry access requires an admin-level user;
/// callers should fall back to manual room creation if this throws or
/// returns nothing.
class RoomAutoProvisioner {
  final String baseUrl;
  final String accessToken;

  RoomAutoProvisioner({required this.baseUrl, required this.accessToken});

  Future<ProvisionResult> provision() async {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final channel = WebSocketChannel.connect(Uri.parse('$scheme://${uri.authority}/api/websocket'));
    await channel.ready;

    final pending = <int, Completer<Map<String, dynamic>>>{};
    var nextId = 1;
    final authCompleter = Completer<void>();

    late StreamSubscription sub;
    sub = channel.stream.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'auth_required':
          channel.sink.add(jsonEncode({'type': 'auth', 'access_token': accessToken}));
          break;
        case 'auth_ok':
          if (!authCompleter.isCompleted) authCompleter.complete();
          break;
        case 'auth_invalid':
          if (!authCompleter.isCompleted) {
            authCompleter.completeError(StateError('Authentication rejected'));
          }
          break;
        case 'result':
          final id = msg['id'] as int?;
          pending.remove(id)?.complete(msg);
          break;
      }
    });

    Future<Map<String, dynamic>> send(Map<String, dynamic> payload) {
      final id = nextId++;
      final completer = Completer<Map<String, dynamic>>();
      pending[id] = completer;
      channel.sink.add(jsonEncode({...payload, 'id': id}));
      return completer.future.timeout(const Duration(seconds: 10));
    }

    try {
      await authCompleter.future.timeout(const Duration(seconds: 10));

      final statesResult = await send({'type': 'get_states'});
      final states = ((statesResult['result'] as List?) ?? [])
          .map((e) => EntityState.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

      List<Map<String, dynamic>>? areas;
      List<Map<String, dynamic>>? entityRegistry;
      List<Map<String, dynamic>>? deviceRegistry;
      try {
        final areasResult = await send({'type': 'config/area_registry/list'});
        areas = ((areasResult['result'] as List?) ?? []).cast<Map<String, dynamic>>();
        final entitiesResult = await send({'type': 'config/entity_registry/list'});
        entityRegistry = ((entitiesResult['result'] as List?) ?? []).cast<Map<String, dynamic>>();
        final devicesResult = await send({'type': 'config/device_registry/list'});
        deviceRegistry = ((devicesResult['result'] as List?) ?? []).cast<Map<String, dynamic>>();
      } catch (_) {
        // Registry access needs an admin account; a non-admin login still
        // gets full state access, just no auto room provisioning.
      }

      final weatherEntity = states.where((e) => e.domain == 'weather').isEmpty
          ? null
          : states.firstWhere((e) => e.domain == 'weather').entityId;

      if (areas == null || areas.isEmpty || entityRegistry == null) {
        return ProvisionResult(rooms: const [], weatherEntityId: weatherEntity, adminAccess: areas != null);
      }

      final deviceAreaById = <String, String?>{
        for (final d in deviceRegistry ?? const <Map<String, dynamic>>[])
          d['id'] as String: d['area_id'] as String?,
      };

      final entitiesByArea = <String, List<String>>{};
      for (final reg in entityRegistry) {
        final entityId = reg['entity_id'] as String?;
        if (entityId == null) continue;
        final areaId = (reg['area_id'] as String?) ??
            deviceAreaById[reg['device_id'] as String? ?? ''];
        if (areaId == null) continue;
        entitiesByArea.putIfAbsent(areaId, () => []).add(entityId);
      }

      final stateById = {for (final s in states) s.entityId: s};
      final personEntities =
          states.where((e) => e.domain == 'person').map((e) => e.entityId).take(4).toList();

      final rooms = <RoomConfig>[];
      for (final area in areas) {
        final areaId = area['area_id'] as String;
        final areaName = area['name'] as String? ?? areaId;
        final entityIds = entitiesByArea[areaId] ?? const [];
        if (entityIds.isEmpty) continue;

        String? firstWhere(bool Function(EntityState) test) {
          for (final id in entityIds) {
            final s = stateById[id];
            if (s != null && test(s)) return id;
          }
          return null;
        }

        List<String> allWhere(bool Function(EntityState) test) => entityIds
            .where((id) => stateById[id] != null && test(stateById[id]!))
            .toList();

        final lights = allWhere((e) => e.domain == 'light').take(8).toList();
        final mediaPlayers = allWhere((e) => e.domain == 'media_player').take(14).toList();
        final cameras = allWhere((e) => e.domain == 'camera').take(2).toList();
        final slug = areaId.replaceAll(RegExp(r'[^a-z0-9_]'), '-');

        final cards = <CardConfig>[
          for (final id in lights)
            CardConfig(id: 'auto-$id', type: KotiCardType.light, entityId: id),
          for (final id in mediaPlayers)
            CardConfig(id: 'auto-$id', type: KotiCardType.media, entityId: id),
          for (final id in cameras)
            CardConfig(id: 'auto-$id', type: KotiCardType.camera, entityId: id),
        ];

        rooms.add(RoomConfig(
          id: slug,
          name: areaName,
          climateEntity: firstWhere((e) => e.domain == 'climate'),
          temperatureSensor:
              firstWhere((e) => e.domain == 'sensor' && e.attr('device_class', '') == 'temperature'),
          humiditySensor:
              firstWhere((e) => e.domain == 'sensor' && e.attr('device_class', '') == 'humidity'),
          lightEntities: lights,
          mediaPlayers: mediaPlayers,
          motionSensor:
              firstWhere((e) => e.domain == 'binary_sensor' && e.attr('device_class', '') == 'motion'),
          presenceEntities: personEntities,
          cards: cards,
        ));
      }

      final securityRoom = buildSecurityRoom(states);
      if (securityRoom != null) rooms.add(securityRoom);

      return ProvisionResult(rooms: rooms, weatherEntityId: weatherEntity, adminAccess: true);
    } finally {
      await sub.cancel();
      await channel.sink.close();
    }
  }
}

class ProvisionResult {
  final List<RoomConfig> rooms;
  final String? weatherEntityId;
  final bool adminAccess;

  ProvisionResult({required this.rooms, required this.weatherEntityId, required this.adminAccess});
}

/// Synthesizes a whole-house "Security" room from every camera/lock/doorbell/
/// motion entity, regardless of which Area (or no Area) it belongs to —
/// unlike the rooms above, this isn't a 1:1 mapping of an HA Area, it's a
/// cross-cutting overview so security-relevant entities don't only live
/// buried inside whichever room they happen to be assigned to. Returns null
/// if the instance has none of these (nothing to show).
@visibleForTesting
RoomConfig? buildSecurityRoom(List<EntityState> states) {
  final cameras = states.where((e) => e.domain == 'camera').take(8).toList();
  final locks = states.where((e) => e.domain == 'lock').take(8).toList();
  final doorbells = states
      .where((e) => e.domain == 'binary_sensor' && e.entityId.contains('doorbell'))
      .take(4)
      .toList();
  final motion = states
      .where((e) => e.domain == 'binary_sensor' && e.attr('device_class', '') == 'motion')
      .take(10)
      .toList();

  if (cameras.isEmpty && locks.isEmpty && doorbells.isEmpty && motion.isEmpty) return null;

  final cards = <CardConfig>[
    for (final e in cameras)
      CardConfig(id: 'auto-security-${e.entityId}', type: KotiCardType.camera, entityId: e.entityId),
    for (final e in locks)
      CardConfig(id: 'auto-security-${e.entityId}', type: KotiCardType.lock, entityId: e.entityId),
    for (final e in doorbells)
      CardConfig(
          id: 'auto-security-${e.entityId}', type: KotiCardType.doorbell, entityId: e.entityId),
    if (motion.isNotEmpty)
      CardConfig(
        id: 'auto-security-motion',
        type: KotiCardType.motion,
        entityId: motion.first.entityId,
        extraEntityIds: motion.skip(1).map((e) => e.entityId).toList(),
      ),
  ];

  return RoomConfig(
    id: 'security',
    name: 'Security',
    iconAsset: 'lock',
    lockEntities: locks.map((e) => e.entityId).toList(),
    cards: cards,
  );
}
