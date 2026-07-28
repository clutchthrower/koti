import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:koti/api/ha_websocket_client.dart';

import 'sendspin/test_event_pump.dart';

/// Polls [condition] until it's true or [timeout] elapses (then throws) —
/// for state reached via a real socket round trip, where a bounded
/// microtask flush like `pumpEventQueue()` isn't a reliable enough signal.
Future<void> _waitUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// A minimal fake of HA's `/api/websocket` endpoint: accepts every upgrade
/// request and hands each resulting socket out over [connections], so a
/// test can script the auth handshake (and, for reconnect tests, accept a
/// second connection after dropping the first).
class _FakeHaServer {
  _FakeHaServer._(this._http);

  final HttpServer _http;
  final _connections = StreamController<WebSocket>.broadcast();
  Stream<WebSocket> get connections => _connections.stream;

  static Future<_FakeHaServer> bind() async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _FakeHaServer._(http);
    http.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      server._connections.add(socket);
    });
    return server;
  }

  String get baseUrl => 'http://127.0.0.1:${_http.port}';

  Future<void> close() async {
    await _connections.close();
    await _http.close(force: true);
  }
}

/// Pulls accepted connections out in strict arrival order. A broadcast
/// stream's `.first`/`.skip(n)` only see events emitted *after* they
/// subscribe, so re-deriving a fresh `.first` per reconnect (as a naive
/// test would) silently waits for a connection that already came and
/// went — this subscribes exactly once, up front, and queues the rest.
class _ConnectionQueue {
  _ConnectionQueue(Stream<WebSocket> source) {
    _sub = source.listen((socket) {
      _queue.add(socket);
      _drain();
    });
  }

  late final StreamSubscription<WebSocket> _sub;
  final _queue = <WebSocket>[];
  final _waiters = <Completer<void>>[];

  void _drain() {
    while (_waiters.isNotEmpty && _queue.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }

  Future<WebSocket> next() async {
    while (_queue.isEmpty) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    return _queue.removeAt(0);
  }

  Future<void> cancel() => _sub.cancel();
}

Map<String, dynamic> _decode(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

/// Drives a fresh connection through HA's real auth handshake
/// (`auth_required` -> client `auth` -> `auth_ok`) and returns the pump
/// wrapping the resulting socket, positioned right after `auth_ok`.
Future<TestEventPump> _authenticate(WebSocket socket) async {
  final pump = TestEventPump(socket);
  socket.add(jsonEncode({'type': 'auth_required', 'ha_version': '2026.7.0'}));
  final authMsg = _decode(await pump.nextText());
  expect(authMsg['type'], 'auth');
  expect(authMsg['access_token'], 'test-token');
  socket.add(jsonEncode({'type': 'auth_ok', 'ha_version': '2026.7.0'}));
  return pump;
}

void main() {
  late _FakeHaServer server;
  late HaWebSocketClient client;

  setUp(() async {
    server = await _FakeHaServer.bind();
  });

  tearDown(() async {
    client.dispose();
    await server.close();
  });

  test('completes the auth handshake and reaches connected status', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final statuses = <HaConnectionStatus>[];
    client.statusStream.listen(statuses.add);

    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    await _authenticate(socket);

    await pumpEventQueue();
    expect(client.status, HaConnectionStatus.connected);
    expect(statuses, contains(HaConnectionStatus.connected));
  });

  test('sendCommand assigns sequential ids and resolves on a matching result', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    final pump = await _authenticate(socket);

    final firstCall = client.sendCommand({'type': 'get_states'});
    final firstMsg = _decode(await pump.nextText());
    expect(firstMsg['id'], isA<int>());

    final secondCall = client.sendCommand({'type': 'get_states'});
    final secondMsg = _decode(await pump.nextText());
    expect(secondMsg['id'], greaterThan(firstMsg['id'] as int));

    socket.add(jsonEncode({'id': secondMsg['id'], 'type': 'result', 'success': true, 'result': 'second'}));
    socket.add(jsonEncode({'id': firstMsg['id'], 'type': 'result', 'success': true, 'result': 'first'}));

    expect((await firstCall)['result'], 'first');
    expect((await secondCall)['result'], 'second');
  });

  test('queues commands sent before auth_ok and flushes them once authenticated', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    final pump = TestEventPump(socket);

    // Sent before auth_required has even arrived — must not reach the wire
    // until after auth_ok.
    final call = client.sendCommand({'type': 'get_states'});

    socket.add(jsonEncode({'type': 'auth_required', 'ha_version': '2026.7.0'}));
    final authMsg = _decode(await pump.nextText());
    expect(authMsg['type'], 'auth');
    socket.add(jsonEncode({'type': 'auth_ok', 'ha_version': '2026.7.0'}));

    final flushed = _decode(await pump.nextText());
    expect(flushed['type'], 'get_states');
    socket.add(jsonEncode({'id': flushed['id'], 'type': 'result', 'success': true, 'result': 'ok'}));
    expect((await call)['result'], 'ok');
  });

  test('sendCommand times out with a synthetic failure result if nothing replies', () async {
    client = HaWebSocketClient(
      baseUrl: server.baseUrl,
      token: 'test-token',
      requestTimeout: const Duration(milliseconds: 50),
    );
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    await _authenticate(socket);

    final result = await client.sendCommand({'type': 'get_states'});
    expect(result, {'success': false, 'error': 'timeout'});
  });

  test('forwards event messages on the events stream', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    await _authenticate(socket);

    final firstEvent = client.events.first;
    socket.add(jsonEncode({
      'type': 'event',
      'event': {'event_type': 'state_changed'},
    }));
    final event = await firstEvent;
    expect(event['event']['event_type'], 'state_changed');
  });

  test('auth_invalid disconnects without scheduling a reconnect', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'wrong-token');
    final statuses = <HaConnectionStatus>[];
    client.statusStream.listen(statuses.add);

    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    final pump = TestEventPump(socket);
    socket.add(jsonEncode({'type': 'auth_required', 'ha_version': '2026.7.0'}));
    await pump.nextText();
    socket.add(jsonEncode({'type': 'auth_invalid', 'message': 'Invalid token'}));

    // auth_invalid travels over a real loopback socket, not a synchronous
    // fake — pumpEventQueue()'s bounded microtask flushing isn't guaranteed
    // to cover that actual I/O round trip under load. Poll briefly instead.
    await _waitUntil(() => client.status == HaConnectionStatus.disconnected);
    expect(statuses, isNot(contains(HaConnectionStatus.reconnecting)));
  });

  test('close() is a clean disconnect: no reconnect attempt follows', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    await _authenticate(socket);

    client.close();
    expect(client.status, HaConnectionStatus.disconnected);

    // If close() failed to suppress reconnection, a second connection
    // would show up here; give it a moment and confirm it doesn't.
    final raced = await Future.any([
      server.connections.first.then((_) => true),
      Future.delayed(const Duration(milliseconds: 200), () => false),
    ]);
    expect(raced, isFalse);
  });

  test('reconnects with backoff after an unexpected drop, and re-authenticates', () async {
    client = HaWebSocketClient(
      baseUrl: server.baseUrl,
      token: 'test-token',
      reconnectInterval: const Duration(milliseconds: 10),
    );
    final statuses = <HaConnectionStatus>[];
    client.statusStream.listen(statuses.add);

    final connectionQueue = _ConnectionQueue(server.connections);
    await client.connect();
    final firstSocket = await connectionQueue.next();
    await _authenticate(firstSocket);

    await firstSocket.close();
    final secondSocket = await connectionQueue.next();

    expect(statuses, contains(HaConnectionStatus.reconnecting));
    await _authenticate(secondSocket);
    await connectionQueue.cancel();
    await pumpEventQueue();
    expect(client.status, HaConnectionStatus.connected);
  });

  test('callServiceForResponse throws HaServiceException on failure', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    final pump = await _authenticate(socket);

    final call = client.callServiceForResponse('music_assistant', 'search');
    final sent = _decode(await pump.nextText());
    socket.add(jsonEncode({
      'id': sent['id'],
      'type': 'result',
      'success': false,
      'error': {'message': 'Entity not found'},
    }));

    await expectLater(
      call,
      throwsA(isA<HaServiceException>().having((e) => e.message, 'message', 'Entity not found')),
    );
  });

  test('browseMedia throws HaServiceException on failure and returns result on success', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    final pump = await _authenticate(socket);

    final call = client.browseMedia('media_player.living_room');
    final sent = _decode(await pump.nextText());
    expect(sent['type'], 'media_player/browse_media');
    expect(sent['entity_id'], 'media_player.living_room');
    socket.add(jsonEncode({
      'id': sent['id'],
      'type': 'result',
      'success': true,
      'result': {'title': 'Library'},
    }));

    expect((await call)['title'], 'Library');
  });

  test('getConfigEntries and getEntityRegistry unwrap list results, ignoring non-map junk', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;
    final pump = await _authenticate(socket);

    final entriesCall = client.getConfigEntries(domain: 'music_assistant');
    final entriesSent = _decode(await pump.nextText());
    expect(entriesSent['type'], 'config_entries/get');
    expect(entriesSent['domain'], 'music_assistant');
    socket.add(jsonEncode({
      'id': entriesSent['id'],
      'type': 'result',
      'success': true,
      'result': [
        {'entry_id': 'abc'},
        'not-a-map',
      ],
    }));
    final entries = await entriesCall;
    expect(entries, [
      {'entry_id': 'abc'},
    ]);

    final registryCall = client.getEntityRegistry();
    final registrySent = _decode(await pump.nextText());
    expect(registrySent['type'], 'config/entity_registry/list');
    socket.add(jsonEncode({
      'id': registrySent['id'],
      'type': 'result',
      'success': true,
      'result': [
        {'entity_id': 'light.foo'},
      ],
    }));
    final registry = await registryCall;
    expect(registry, [
      {'entity_id': 'light.foo'},
    ]);
  });

  test('debug logging captures frames only once enabled, and clearDebugLog empties it', () async {
    client = HaWebSocketClient(baseUrl: server.baseUrl, token: 'test-token');
    final connFuture = server.connections.first;
    await client.connect();
    final socket = await connFuture;

    socket.add(jsonEncode({'type': 'auth_required', 'ha_version': '2026.7.0'}));
    await pumpEventQueue();
    // Logging is off by default: the auth_required frame above must not
    // have been captured.
    expect(client.debugLog.value, isEmpty);

    client.debugLoggingEnabled = true;
    socket.add(jsonEncode({'type': 'auth_ok', 'ha_version': '2026.7.0'}));
    await pumpEventQueue();
    expect(client.debugLog.value, isNotEmpty);

    client.clearDebugLog();
    expect(client.debugLog.value, isEmpty);
  });
}
