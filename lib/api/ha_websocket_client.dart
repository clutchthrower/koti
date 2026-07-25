import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum HaConnectionStatus { disconnected, connecting, connected, reconnecting }

/// One captured WebSocket frame, for the Diagnostics page's debug log.
class WsDebugFrame {
  final bool outgoing;
  final String raw;
  final DateTime timestamp;
  WsDebugFrame(this.outgoing, this.raw, this.timestamp);
}

/// Persistent WebSocket connection to Home Assistant's `/api/websocket`
/// endpoint. Implements the standard auth handshake, silent auto-reconnect
/// with exponential backoff, and a queue for outgoing service calls made
/// while disconnected so nothing is lost on a dropped Wi-Fi signal.
class HaWebSocketClient {
  final String baseUrl;
  final String token;
  final Duration reconnectInterval;
  final Duration requestTimeout;

  HaWebSocketClient({
    required this.baseUrl,
    required this.token,
    this.reconnectInterval = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 15),
  });

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int _messageId = 1;
  bool _authenticated = false;
  bool _closedByUser = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  final _statusController = StreamController<HaConnectionStatus>.broadcast();
  Stream<HaConnectionStatus> get statusStream => _statusController.stream;
  HaConnectionStatus _status = HaConnectionStatus.disconnected;
  HaConnectionStatus get status => _status;

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  /// Diagnostics page toggle — off by default so this never captures
  /// traffic (or holds it in memory) unless someone's actually debugging.
  bool debugLoggingEnabled = false;
  static const _debugLogCap = 200;
  final ValueNotifier<List<WsDebugFrame>> debugLog = ValueNotifier(const []);

  void _captureDebugFrame(bool outgoing, String raw) {
    if (!debugLoggingEnabled) return;
    final next = List<WsDebugFrame>.from(debugLog.value)
      ..add(WsDebugFrame(outgoing, raw, DateTime.now()));
    if (next.length > _debugLogCap) next.removeAt(0);
    debugLog.value = next;
  }

  void clearDebugLog() => debugLog.value = const [];

  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final List<Map<String, dynamic>> _outgoingQueue = [];
  final List<Map<String, dynamic>> _resubscribeQueue = [];

  String get _wsUrl {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.authority}/api/websocket';
  }

  void _setStatus(HaConnectionStatus s) {
    _status = s;
    _statusController.add(s);
  }

  Future<void> connect() async {
    _closedByUser = false;
    _setStatus(_reconnectAttempt == 0
        ? HaConnectionStatus.connecting
        : HaConnectionStatus.reconnecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await _channel!.ready;
      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    _captureDebugFrame(false, raw as String);
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'auth_required':
        _send({'type': 'auth', 'access_token': token});
        break;
      case 'auth_ok':
        _authenticated = true;
        _reconnectAttempt = 0;
        _setStatus(HaConnectionStatus.connected);
        _flushQueue();
        break;
      case 'auth_invalid':
        _authenticated = false;
        _setStatus(HaConnectionStatus.disconnected);
        _sub?.cancel();
        break;
      case 'event':
        _eventController.add(msg);
        break;
      case 'result':
        final id = msg['id'] as int?;
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(msg);
        }
        break;
      case 'pong':
        break;
    }
  }

  void _onDisconnected() {
    _authenticated = false;
    if (_closedByUser) {
      _setStatus(HaConnectionStatus.disconnected);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _setStatus(HaConnectionStatus.reconnecting);
    _reconnectAttempt++;
    final backoff = Duration(
      milliseconds: (reconnectInterval.inMilliseconds *
              (1 << (_reconnectAttempt.clamp(0, 5))))
          .clamp(reconnectInterval.inMilliseconds, 60000),
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, connect);
  }

  void _send(Map<String, dynamic> payload) {
    final raw = jsonEncode(payload);
    _captureDebugFrame(true, raw);
    _channel?.sink.add(raw);
  }

  int _nextId() => _messageId++;

  /// Sends a command and awaits its `result` response. Queues the command
  /// if the socket isn't authenticated yet, replaying it once reconnected.
  Future<Map<String, dynamic>> sendCommand(Map<String, dynamic> payload) {
    final id = _nextId();
    final message = {...payload, 'id': id};
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    if (_authenticated) {
      _send(message);
    } else {
      _outgoingQueue.add(message);
    }

    return completer.future.timeout(
      requestTimeout,
      onTimeout: () => {'success': false, 'error': 'timeout'},
    );
  }

  /// Subscriptions must be re-sent after every reconnect since HA has no
  /// memory of a previous connection's subscriptions.
  Future<void> subscribeEvents(String eventType) async {
    final payload = {'type': 'subscribe_events', 'event_type': eventType};
    _resubscribeQueue.add(payload);
    await sendCommand(payload);
  }

  Future<Map<String, dynamic>> getStates() =>
      sendCommand({'type': 'get_states'});

  Future<void> callService(
    String domain,
    String service, {
    Map<String, dynamic>? serviceData,
    Map<String, dynamic>? target,
  }) async {
    await sendCommand({
      'type': 'call_service',
      'domain': domain,
      'service': service,
      if (serviceData != null) 'service_data': serviceData,
      if (target != null) 'target': target,
    });
  }

  /// For "response" services (e.g. Music Assistant's search/get_library/
  /// get_queue) that return data rather than just acting. Returns the
  /// `result.response` payload, or an empty map if the service gave none.
  Future<Map<String, dynamic>> callServiceForResponse(
    String domain,
    String service, {
    Map<String, dynamic>? serviceData,
    Map<String, dynamic>? target,
  }) async {
    final msg = await sendCommand({
      'type': 'call_service',
      'domain': domain,
      'service': service,
      if (serviceData != null) 'service_data': serviceData,
      if (target != null) 'target': target,
      'return_response': true,
    });
    if (msg['success'] != true) {
      final error = msg['error'] as Map<String, dynamic>?;
      throw HaServiceException(
          error?['message'] as String? ?? 'Service call failed');
    }
    final result = msg['result'] as Map<String, dynamic>?;
    return (result?['response'] as Map<String, dynamic>?) ?? const {};
  }

  /// Lists config entries (admin API) — used to resolve the `config_entry_id`
  /// some services require (e.g. Music Assistant's search/get_library).
  Future<List<Map<String, dynamic>>> getConfigEntries({String? domain}) async {
    final msg = await sendCommand({
      'type': 'config_entries/get',
      if (domain != null) 'domain': domain,
    });
    final result = msg['result'];
    if (result is! List) return const [];
    return result.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  /// Admin API, WebSocket-only — used to find an entity that shares a
  /// device with a given entity but isn't itself returned by get_states
  /// filtering alone (e.g. Music Assistant's per-player "favorite" button,
  /// resolved by matching device_id — see MusicFavoriteResolver).
  Future<List<Map<String, dynamic>>> getEntityRegistry() async {
    final msg = await sendCommand({'type': 'config/entity_registry/list'});
    final result = msg['result'];
    if (result is! List) return const [];
    return result.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  /// Hierarchical media browsing (`media_player/browse_media`) — the
  /// standard HA media_player API, which Music Assistant's integration
  /// implements to expose real drill-down (artist -> their albums, album/
  /// playlist -> their tracks) instead of the flat get_library/search
  /// results this app used to always instant-play. Omit both content
  /// params for the root listing (Artists/Albums/Playlists/Radio/Tracks).
  Future<Map<String, dynamic>> browseMedia(
    String entityId, {
    String? mediaContentType,
    String? mediaContentId,
  }) async {
    final msg = await sendCommand({
      'type': 'media_player/browse_media',
      'entity_id': entityId,
      if (mediaContentType != null) 'media_content_type': mediaContentType,
      if (mediaContentId != null) 'media_content_id': mediaContentId,
    });
    if (msg['success'] != true) {
      final error = msg['error'] as Map<String, dynamic>?;
      throw HaServiceException(error?['message'] as String? ?? 'Browse failed');
    }
    return (msg['result'] as Map<String, dynamic>?) ?? const {};
  }

  void _flushQueue() {
    for (final payload in _resubscribeQueue) {
      final id = _nextId();
      _send({...payload, 'id': id});
    }
    final queued = List<Map<String, dynamic>>.from(_outgoingQueue);
    _outgoingQueue.clear();
    for (final message in queued) {
      _send(message);
    }
  }

  void close() {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _setStatus(HaConnectionStatus.disconnected);
  }

  void dispose() {
    close();
    _statusController.close();
    _eventController.close();
    debugLog.dispose();
  }
}

/// A "response" service call that HA rejected (bad/missing fields, no
/// matching entity, etc.) — carries HA's own error message so the UI can
/// show exactly what went wrong instead of a silent empty result.
class HaServiceException implements Exception {
  final String message;
  HaServiceException(this.message);
  @override
  String toString() => message;
}
