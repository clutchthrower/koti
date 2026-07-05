import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/ha_rest_client.dart';
import '../api/ha_websocket_client.dart';
import '../models/entity_state.dart';

/// In-memory mirror of `hass.states`, kept in sync via the WebSocket
/// `state_changed` event stream. Persists a snapshot to local storage so the
/// UI can render instantly on cold launch before the socket reconnects.
class StateStore extends ChangeNotifier {
  static const _cacheKey = 'hemma_state_cache_v1';

  final HaWebSocketClient ws;
  final HaRestClient rest;

  final Map<String, EntityState> _states = {};
  final Map<String, List<VoidCallback>> _entityListeners = {};

  StreamSubscription? _eventSub;
  StreamSubscription? _statusSub;
  HaConnectionStatus connectionStatus = HaConnectionStatus.disconnected;

  StateStore({required this.ws, required this.rest});

  Map<String, EntityState> get all => Map.unmodifiable(_states);

  EntityState? get(String entityId) => _states[entityId];

  /// Test seam: inject states directly, bypassing the socket.
  @visibleForTesting
  void debugSetStates(Iterable<EntityState> entities) {
    for (final e in entities) {
      _states[e.entityId] = e;
    }
    notifyListeners();
    _notifyAllEntityListeners();
  }

  Future<void> init() async {
    await _loadCache();
    _statusSub = ws.statusStream.listen((status) {
      connectionStatus = status;
      notifyListeners();
      if (status == HaConnectionStatus.connected) {
        _onConnected();
      }
    });
    _eventSub = ws.events.listen(_onEvent);
    await ws.connect();
  }

  Future<void> _onConnected() async {
    await ws.subscribeEvents('state_changed');
    final result = await ws.getStates();
    final list = result['result'] as List? ?? [];
    for (final raw in list) {
      final entity = EntityState.fromJson((raw as Map).cast<String, dynamic>());
      _states[entity.entityId] = entity;
    }
    notifyListeners();
    _notifyAllEntityListeners();
    unawaited(_saveCache());
  }

  void _onEvent(Map<String, dynamic> msg) {
    final event = msg['event'] as Map<String, dynamic>?;
    if (event == null || event['event_type'] != 'state_changed') return;
    final data = event['data'] as Map<String, dynamic>;
    final newStateJson = data['new_state'] as Map<String, dynamic>?;
    if (newStateJson == null) return;
    final entity = EntityState.fromJson(newStateJson);
    _states[entity.entityId] = entity;
    notifyListeners();
    _notifyEntityListeners(entity.entityId);
    unawaited(_saveCache());
  }

  /// Selective subscription so a single card can rebuild without the whole
  /// entity grid repainting on unrelated state changes.
  void subscribe(String entityId, VoidCallback callback) {
    _entityListeners.putIfAbsent(entityId, () => []).add(callback);
  }

  void unsubscribe(String entityId, VoidCallback callback) {
    _entityListeners[entityId]?.remove(callback);
  }

  void _notifyEntityListeners(String entityId) {
    for (final cb in _entityListeners[entityId] ?? const []) {
      cb();
    }
  }

  void _notifyAllEntityListeners() {
    for (final entry in _entityListeners.entries) {
      for (final cb in entry.value) {
        cb();
      }
    }
  }

  /// Test seam: capture service calls instead of hitting the network.
  @visibleForTesting
  void Function(String domain, String service, Map<String, dynamic>? data,
      String? entityId)? debugServiceInterceptor;

  Future<void> callService(
    String domain,
    String service, {
    Map<String, dynamic>? data,
    String? entityId,
  }) async {
    final interceptor = debugServiceInterceptor;
    if (interceptor != null) {
      interceptor(domain, service, data, entityId);
      return;
    }
    if (ws.status == HaConnectionStatus.connected) {
      await ws.callService(
        domain,
        service,
        serviceData: data,
        target: entityId != null ? {'entity_id': entityId} : null,
      );
    } else {
      await rest.callService(domain, service, data: {
        ...?data,
        if (entityId != null) 'entity_id': entityId,
      });
    }
  }

  Future<void> forceRefresh() async {
    final list = await rest.states();
    for (final raw in list) {
      final entity = EntityState.fromJson((raw as Map).cast<String, dynamic>());
      _states[entity.entityId] = entity;
    }
    notifyListeners();
    _notifyAllEntityListeners();
    await _saveCache();
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    final serializable = _states.map((key, value) => MapEntry(key, {
          'entity_id': value.entityId,
          'state': value.state,
          'attributes': value.attributes,
          'last_changed': value.lastChanged.toIso8601String(),
          'last_updated': value.lastUpdated.toIso8601String(),
        }));
    await prefs.setString(_cacheKey, jsonEncode(serializable));
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    for (final entry in decoded.entries) {
      _states[entry.key] =
          EntityState.fromJson((entry.value as Map).cast<String, dynamic>());
    }
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    _states.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
