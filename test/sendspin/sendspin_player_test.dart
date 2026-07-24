import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koti/sendspin/base64url.dart';
import 'package:koti/sendspin/identity.dart';
import 'package:koti/sendspin/noise/handshake_state.dart';
import 'package:koti/sendspin/noise/primitives.dart';
import 'package:koti/sendspin/noise/symmetric_state.dart';
import 'package:koti/sendspin/noise/transport_cipher.dart';
import 'package:koti/sendspin/sendspin_connection.dart';
import 'package:koti/sendspin/sendspin_player.dart';
import 'package:koti/sendspin/wire/binary_frame.dart';
import 'package:koti/sendspin/wire/envelope.dart';

import 'test_event_pump.dart';

/// Drives the Music Assistant side over a real loopback socket through
/// activation (mirroring sendspin_connection_test.dart's fixture, kept as
/// its own copy since each test file's fixture evolves for what it needs to
/// exercise next), then continues into the steady state this test actually
/// cares about: replying to one `client/time` with `server/time`, sending
/// `stream/start` for a PCM format, and pushing one audio chunk.
class _FakeMusicAssistantServer {
  _FakeMusicAssistantServer(this._socket, this._serverStatic);

  final WebSocket _socket;
  final SimpleKeyPair _serverStatic;
  late final _pump = TestEventPump(_socket);
  TransportCipher? _sendCipher;
  TransportCipher? _receiveCipher;
  final _reassembler = FragmentReassembler();

  Future<void> _sendJson(SendspinEnvelope envelope) async {
    final plaintext = <int>[0, ...utf8.encode(envelope.encode())];
    _socket.add(await _sendCipher!.encrypt(plaintext));
  }

  Future<SendspinEnvelope> _receiveJson() async {
    while (true) {
      final raw = await _pump.nextBinary();
      final plaintext = await _receiveCipher!.decrypt(Uint8List.fromList(raw));
      final reassembled = _reassembler.feed(plaintext);
      if (reassembled == null) continue;
      final (type, data) = reassembled;
      expect(type, BinaryMessageType.jsonBody);
      return SendspinEnvelope.decode(utf8.decode(data));
    }
  }

  Future<void> _sendAudioChunk(int timestampUs, Uint8List pcm) async {
    final frame = TimestampedFramePayload(timestampUs, pcm).encode();
    final plaintext = <int>[BinaryMessageType.audioChunk, ...frame];
    _socket.add(await _sendCipher!.encrypt(plaintext));
  }

  /// Runs the handshake through activation, then the extra steady-state
  /// exchange this test needs. Returns the `client/state` payloads
  /// received, plus the `client/command` payload sent afterward (the
  /// controller-role transport command the test triggers), for assertions.
  Future<(List<Map<String, dynamic>>, Map<String, dynamic>)> run() async {
    final clientInitRaw = await _pump.nextText();
    final clientInit = SendspinEnvelope.decode(clientInitRaw);
    final clientId = base64UrlNoPadDecode(clientInit.payload['client_id'] as String);

    final serverStaticPub = await extractPublicKeyBytes(_serverStatic);
    final serverInitRaw = SendspinEnvelope(MessageType.serverInit, {
      'server_id': base64UrlNoPad(serverStaticPub),
      'version': 1,
    }).encode();
    _socket.add(serverInitRaw);

    final prologue = Uint8List.fromList([
      ...utf8.encode(clientInitRaw),
      ...utf8.encode(serverInitRaw),
    ]);

    final psk = await sentinelPsk();
    final handshake = _FakeInitiator(_serverStatic, clientId);
    await handshake.initialize(prologue);

    final pskIdBytes = await sha256Hash([...utf8.encode('sendspin-psk-id-v1'), ...psk]);
    final message1 = await handshake.writeMessage1(
      utf8.encode(jsonEncode({'psk_id': base64UrlNoPad(pskIdBytes)})),
    );
    _socket.add(SendspinEnvelope(MessageType.noiseHandshake, {
      'data': base64UrlNoPad(message1),
    }).encode());

    final message2Raw = await _pump.nextText();
    final message2Envelope = SendspinEnvelope.decode(message2Raw);
    final message2Bytes = base64UrlNoPadDecode(message2Envelope.payload['data'] as String);
    await handshake.readMessage2(message2Bytes, psk);

    final (sendKey, receiveKey) = await handshake.split();
    _sendCipher = TransportCipher(sendKey);
    _receiveCipher = TransportCipher(receiveKey);

    await _sendJson(const SendspinEnvelope(MessageType.serverHello, {'name': 'Fake MA'}));
    await _receiveJson(); // client/hello

    await _sendJson(SendspinEnvelope(MessageType.serverActivate, {
      'activities': ['playback'],
      'active_roles': ['player@v1'],
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

class _FakeInitiator {
  _FakeInitiator(this.localStatic, this.remoteStaticPublicKey);

  final SimpleKeyPair localStatic;
  final Uint8List remoteStaticPublicKey;
  final _sym = SymmetricState();
  SimpleKeyPair? _localEphemeral;

  Future<void> initialize(List<int> prologue) async {
    await _sym.initializeSymmetric(utf8.encode(KKpsk2ResponderHandshake.protocolName));
    await _sym.mixHash(prologue);
    await _sym.mixHash(await extractPublicKeyBytes(localStatic));
    await _sym.mixHash(remoteStaticPublicKey);
  }

  Future<Uint8List> writeMessage1(List<int> payload) async {
    final e = await newX25519KeyPair();
    _localEphemeral = e;
    final ePub = await extractPublicKeyBytes(e);
    await _sym.mixHash(ePub);
    await _sym.mixKey(await x25519SharedSecret(e, remoteStaticPublicKey));
    await _sym.mixKey(await x25519SharedSecret(localStatic, remoteStaticPublicKey));
    final ciphertext = await _sym.encryptAndHash(payload);
    return Uint8List.fromList([...ePub, ...ciphertext]);
  }

  Future<Uint8List> readMessage2(Uint8List message, Uint8List psk) async {
    final remoteEphemeral = message.sublist(0, 32);
    await _sym.mixHash(remoteEphemeral);
    await _sym.mixKey(await x25519SharedSecret(_localEphemeral!, remoteEphemeral));
    await _sym.mixKey(await x25519SharedSecret(localStatic, remoteEphemeral));
    await _sym.mixKeyAndHash(psk);
    return _sym.decryptAndHash(message.sublist(32));
  }

  Future<(Uint8List, Uint8List)> split() => _sym.split();
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
    final serverStatic = await newX25519KeyPair();
    late Future<(List<Map<String, dynamic>>, Map<String, dynamic>)> fakeServerResult;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      fakeServerResult = _FakeMusicAssistantServer(socket, serverStatic).run();
    });

    final clientStatic = await newX25519KeyPair();
    final identity = await SendspinIdentity.forTesting(clientStatic);
    final clientSocket = await WebSocket.connect('ws://127.0.0.1:${server.port}/sendspin');
    final connection = SendspinConnection(clientSocket, identity, deviceName: 'Test Tablet');
    await connection.handshakeAndActivate();

    final player = SendspinPlayer(connection);
    await player.start();
    // Fired without awaiting: the fake server's run() is already waiting
    // for exactly this message by the time it arrives.
    unawaited(player.controllerPlay());

    final (clientStates, controllerCommand) = await fakeServerResult;
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
}
