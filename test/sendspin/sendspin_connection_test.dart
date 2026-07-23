import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koti/sendspin/base64url.dart';
import 'package:koti/sendspin/identity.dart';
import 'package:koti/sendspin/noise/handshake_state.dart';
import 'package:koti/sendspin/noise/primitives.dart';
import 'package:koti/sendspin/noise/symmetric_state.dart';
import 'package:koti/sendspin/noise/transport_cipher.dart';
import 'package:koti/sendspin/sendspin_connection.dart';
import 'package:koti/sendspin/wire/envelope.dart';

import 'test_event_pump.dart';

/// Drives the *server* (Music Assistant) side of the handshake over a real
/// loopback WebSocket, so [SendspinConnection] — which always plays the
/// Sendspin client/Noise-responder role — gets exercised against genuine
/// socket framing and genuine Noise crypto, not just in-memory byte
/// buffers (that part is already covered by noise_handshake_test.dart).
/// This is the closest thing to the real interop test short of a live MA
/// instance.
class _FakeMusicAssistantServer {
  _FakeMusicAssistantServer(this._socket, this._serverStatic);

  final WebSocket _socket;
  final SimpleKeyPair _serverStatic;
  late final _pump = TestEventPump(_socket);

  Future<Map<String, dynamic>> run() async {
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
    final sendCipher = TransportCipher(sendKey);
    final receiveCipher = TransportCipher(receiveKey);

    Future<void> sendJson(SendspinEnvelope envelope) async {
      final plaintext = <int>[0, ...utf8.encode(envelope.encode())];
      _socket.add(await sendCipher.encrypt(plaintext));
    }

    Future<Map<String, dynamic>> receiveJson() async {
      final raw = await _pump.nextBinary();
      final plaintext = await receiveCipher.decrypt(Uint8List.fromList(raw));
      expect(plaintext[0], 0, reason: 'expected a JSON control frame');
      return SendspinEnvelope.decode(utf8.decode(plaintext.sublist(1))).payload;
    }

    await sendJson(const SendspinEnvelope(MessageType.serverHello, {'name': 'Fake MA'}));
    final clientHello = await receiveJson();
    expect(clientHello['unpaired_access'], {'enabled': true});
    expect(clientHello['supported_roles'], contains('player@v1'));

    final activatePayload = {
      'activities': ['playback'],
      'active_roles': ['player@v1'],
    };
    await sendJson(SendspinEnvelope(MessageType.serverActivate, activatePayload));
    return activatePayload;
  }
}

/// Initiator-side Noise math (mirrors noise_handshake_test.dart's
/// `_FakeInitiator`, duplicated locally rather than shared since it's ~15
/// lines and this file already has enough moving parts as its own
/// integration surface).
class _FakeInitiator {
  _FakeInitiator(this.localStatic, this.remoteStaticPublicKey);

  final SimpleKeyPair localStatic;
  final Uint8List remoteStaticPublicKey;
  final _sym = SymmetricState();
  SimpleKeyPair? _localEphemeral;

  Future<void> initialize(List<int> prologue) async {
    await _sym.initializeSymmetric(utf8.encode(KKpsk2ResponderHandshake.protocolName));
    await _sym.mixHash(prologue);
    // Initiator's own static key is hashed first, then the responder's.
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
  test('SendspinConnection completes handshake and activation over a real loopback socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverStatic = await newX25519KeyPair();

    late Future<Map<String, dynamic>> fakeServerResult;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      fakeServerResult = _FakeMusicAssistantServer(socket, serverStatic).run();
    });

    final clientStatic = await newX25519KeyPair();
    final identity = await SendspinIdentity.forTesting(clientStatic);
    final clientSocket = await WebSocket.connect('ws://127.0.0.1:${server.port}/sendspin');
    final connection = SendspinConnection(clientSocket, identity, deviceName: 'Test Tablet');

    final activatePayload = await connection.handshakeAndActivate();

    expect(activatePayload['activities'], ['playback']);
    expect(activatePayload['active_roles'], ['player@v1']);
    expect(await fakeServerResult, activatePayload);

    await connection.close();
    await server.close(force: true);
  });
}
