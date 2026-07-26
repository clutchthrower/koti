import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koti/sendspin/sendspin_connection.dart';
import 'package:koti/sendspin/sendspin_player.dart';
import 'package:koti/sendspin/wire/binary_frame.dart';
import 'package:koti/sendspin/wire/envelope.dart';

import 'test_event_pump.dart';

/// Drives the Music Assistant side over a real loopback socket through the
/// plaintext `client/hello`/`server/hello` exchange (mirroring
/// sendspin_connection_test.dart's fixture, kept as its own copy since each
/// test file's fixture evolves for what it needs to exercise next), then
/// continues into the steady state this test actually cares about: replying
/// to one `client/time` with `server/time`, sending `stream/start` for a
/// PCM format, and pushing one audio chunk.
class _FakeMusicAssistantServer {
  _FakeMusicAssistantServer(this._socket);

  final WebSocket _socket;
  late final _pump = TestEventPump(_socket);

  Future<void> _sendJson(SendspinEnvelope envelope) async {
    _socket.add(envelope.encode());
  }

  Future<SendspinEnvelope> _receiveJson() async {
    final raw = await _pump.nextText();
    return SendspinEnvelope.decode(raw);
  }

  Future<void> _sendAudioChunk(int timestampUs, Uint8List pcm) async {
    final frame = TimestampedFramePayload(timestampUs, pcm).encode();
    _socket.add(Uint8List.fromList([BinaryMessageType.audioChunk, ...frame]));
  }

  /// Runs the connection through the hello exchange, then the extra
  /// steady-state exchange this test needs. Returns the `client/state`
  /// payloads received, plus the `client/command` payload sent afterward
  /// (the controller-role transport command the test triggers), for
  /// assertions.
  Future<(List<Map<String, dynamic>>, Map<String, dynamic>)> run() async {
    final clientHelloRaw = await _pump.nextText();
    final clientHello = SendspinEnvelope.decode(clientHelloRaw);
    expect(clientHello.type, MessageType.clientHello);

    await _sendJson(SendspinEnvelope(MessageType.serverHello, {
      'server_id': 'fake-ma-server',
      'name': 'Fake MA',
      'version': 1,
      'active_roles': ['player@v1', 'controller@v1'],
      'connection_reason': 'discovery',
    }));

    // Steady state: collect client/state, reply to client/time, then push
    // a stream/start + one audio chunk.
    final clientStates = <Map<String, dynamic>>[];
    final firstState = await _receiveJson();
    expect(firstState.type, MessageType.clientState);
    clientStates.add(firstState.payload);

    final clientTime = await _receiveJson();
    expect(clientTime.type, MessageType.clientTime);
    final t0 = clientTime.payload['client_transmitted'] as int;
    await _sendJson(SendspinEnvelope(MessageType.serverTime, {
      'client_transmitted': t0,
      'server_received': t0 + 1000,
      'server_transmitted': t0 + 1000,
    }));

    await _sendJson(SendspinEnvelope(MessageType.streamStart, {
      'player': {
        'codec': 'pcm',
        'sample_rate': 48000,
        'channels': 2,
        'bit_depth': 16,
      },
    }));

    await _sendAudioChunk(t0, Uint8List.fromList(List.generate(16, (i) => i)));

    final controllerCommand = await _receiveJson();
    expect(controllerCommand.type, MessageType.clientCommand);

    return (clientStates, controllerCommand.payload);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SendspinPlayer starts the native sink on stream/start and forwards audio chunks', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('koti/native'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('koti/native'), null);
    });

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late Future<(List<Map<String, dynamic>>, Map<String, dynamic>)> fakeServerResult;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      fakeServerResult = _FakeMusicAssistantServer(socket).run();
    });

    final clientSocket = await WebSocket.connect('ws://127.0.0.1:${server.port}/sendspin');
    final connection = SendspinConnection(
      clientSocket,
      clientId: 'test-device-id-1234',
      deviceName: 'Test Tablet',
    );
    await connection.handshakeAndActivate();

    final player = SendspinPlayer(connection);
    await player.start();
    // Fired without awaiting: the fake server's run() is already waiting
    // for exactly this message by the time it arrives.
    unawaited(player.controllerPlay());

    final (clientStates, controllerCommand) = await fakeServerResult;
    expect(clientStates.single['state'], 'synchronized');
    expect(clientStates.single['player']['volume'], 100);
    expect(clientStates.single['player']['muted'], false);
    expect(controllerCommand['controller'], {'command': 'play'});

    // Give the async audio-chunk handling a moment to reach the native
    // channel (scheduling delay is ~0 here since the chunk's timestamp is
    // t0, already in the past relative to when it's processed).
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final startCall = calls.firstWhere((c) => c.method == 'startSendspinAudioSink');
    expect(startCall.arguments['sampleRate'], 48000);
    expect(startCall.arguments['channels'], 2);

    final writeCall = calls.firstWhere((c) => c.method == 'writeSendspinPcmChunk');
    expect(writeCall.arguments['bytes'], List.generate(16, (i) => i));

    await player.stop();
    expect(calls.any((c) => c.method == 'stopSendspinAudioSink'), isTrue);

    await connection.close();
    await server.close(force: true);
  });

  test('SendspinPlayer stops writing audio chunks once server/command mutes it', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('koti/native'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('koti/native'), null);
    });

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late WebSocket serverSocket;
    late Completer<void> serverSocketReady;
    serverSocketReady = Completer<void>();
    server.listen((request) async {
      serverSocket = await WebSocketTransformer.upgrade(request);
      serverSocketReady.complete();
    });

    final clientSocket = await WebSocket.connect('ws://127.0.0.1:${server.port}/sendspin');
    final connection = SendspinConnection(
      clientSocket,
      clientId: 'test-device-id-1234',
      deviceName: 'Test Tablet',
    );
    await serverSocketReady.future;
    final pump = TestEventPump(serverSocket);

    // Not awaited yet — handshakeAndActivate() is what actually sends
    // client/hello, so it must run concurrently with (not after) the
    // server-side read below, or neither side ever proceeds.
    final handshakeFuture = connection.handshakeAndActivate();

    final clientHelloRaw = await pump.nextText();
    expect(SendspinEnvelope.decode(clientHelloRaw).type, MessageType.clientHello);
    serverSocket.add(SendspinEnvelope(MessageType.serverHello, {
      'server_id': 'fake-ma-server',
      'name': 'Fake MA',
      'version': 1,
      'active_roles': ['player@v1'],
      'connection_reason': 'discovery',
    }).encode());
    await handshakeFuture;

    final player = SendspinPlayer(connection);
    await player.start();

    final firstState = SendspinEnvelope.decode(await pump.nextText());
    expect(firstState.type, MessageType.clientState);
    expect(firstState.payload['player']['muted'], false);

    final clientTime = SendspinEnvelope.decode(await pump.nextText());
    final t0 = clientTime.payload['client_transmitted'] as int;
    serverSocket.add(SendspinEnvelope(MessageType.serverTime, {
      'client_transmitted': t0,
      'server_received': t0 + 1000,
      'server_transmitted': t0 + 1000,
    }).encode());

    serverSocket.add(SendspinEnvelope(MessageType.streamStart, {
      'player': {'codec': 'pcm', 'sample_rate': 48000, 'channels': 2, 'bit_depth': 16},
    }).encode());

    // Music Assistant's own volume_mute reaches the client as a
    // server/command, exactly like a normal volume change — confirmed
    // live against the actual server this way, not guessed.
    serverSocket.add(SendspinEnvelope(MessageType.serverCommand, {
      'player': {'command': 'mute', 'mute': true},
    }).encode());
    final muteAckState = SendspinEnvelope.decode(await pump.nextText());
    expect(muteAckState.payload['player']['muted'], true);

    final frame =
        TimestampedFramePayload(t0, Uint8List.fromList(List.generate(16, (i) => i))).encode();
    serverSocket.add(Uint8List.fromList([BinaryMessageType.audioChunk, ...frame]));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The sink still starts (stream/start already arrived) — it's just
    // the chunk itself that must never reach the native write call.
    expect(calls.any((c) => c.method == 'startSendspinAudioSink'), isTrue);
    expect(calls.any((c) => c.method == 'writeSendspinPcmChunk'), isFalse);

    await player.stop();
    await connection.close();
    await server.close(force: true);
  });

  test('SendspinPlayer measures and reports real output latency via static_delay_ms', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('koti/native'),
      (call) async {
        // Stands in for AudioTrack.getTimestamp()-derived measurement —
        // 45ms of real, measured output latency instead of the flat 0
        // this used to always declare.
        if (call.method == 'getSendspinOutputLatencyUs') return 45000;
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('koti/native'), null);
    });

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late WebSocket serverSocket;
    late Completer<void> serverSocketReady;
    serverSocketReady = Completer<void>();
    server.listen((request) async {
      serverSocket = await WebSocketTransformer.upgrade(request);
      serverSocketReady.complete();
    });

    final clientSocket = await WebSocket.connect('ws://127.0.0.1:${server.port}/sendspin');
    final connection = SendspinConnection(
      clientSocket,
      clientId: 'test-device-id-1234',
      deviceName: 'Test Tablet',
    );
    await serverSocketReady.future;
    final pump = TestEventPump(serverSocket);

    final handshakeFuture = connection.handshakeAndActivate();
    final clientHelloRaw = await pump.nextText();
    expect(SendspinEnvelope.decode(clientHelloRaw).type, MessageType.clientHello);
    serverSocket.add(SendspinEnvelope(MessageType.serverHello, {
      'server_id': 'fake-ma-server',
      'name': 'Fake MA',
      'version': 1,
      'active_roles': ['player@v1'],
      'connection_reason': 'discovery',
    }).encode());
    await handshakeFuture;

    final player = SendspinPlayer(connection);
    await player.start();

    final firstState = SendspinEnvelope.decode(await pump.nextText());
    expect(firstState.payload['player']['static_delay_ms'], 0);

    final clientTime = SendspinEnvelope.decode(await pump.nextText());
    final t0 = clientTime.payload['client_transmitted'] as int;
    serverSocket.add(SendspinEnvelope(MessageType.serverTime, {
      'client_transmitted': t0,
      'server_received': t0 + 1000,
      'server_transmitted': t0 + 1000,
    }).encode());

    serverSocket.add(SendspinEnvelope(MessageType.streamStart, {
      'player': {'codec': 'pcm', 'sample_rate': 48000, 'channels': 2, 'bit_depth': 16},
    }).encode());

    // The measurement fires ~500ms after stream/start, racing the
    // player's own 200ms-interval client/time pings — skip past any of
    // those to find the client/state a changed measurement triggers.
    SendspinEnvelope updatedState;
    while (true) {
      updatedState = SendspinEnvelope.decode(await pump.nextText());
      if (updatedState.type == MessageType.clientState) break;
    }
    expect(updatedState.payload['player']['static_delay_ms'], 45);

    await player.stop();
    await connection.close();
    await server.close(force: true);
  });
}
