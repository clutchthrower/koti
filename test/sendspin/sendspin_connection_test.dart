import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koti/sendspin/sendspin_connection.dart';
import 'package:koti/sendspin/wire/envelope.dart';

import 'test_event_pump.dart';

/// Drives the *server* (Music Assistant) side of the connection over a real
/// loopback WebSocket, so [SendspinConnection] gets exercised against
/// genuine socket framing, not just in-memory objects. Matches the actual
/// deployed protocol (confirmed by reading the real `aiosendspin` source
/// Music Assistant 2.9.8 ships): plaintext `client/hello` as the first
/// message, `server/hello` back — no Noise handshake, no `client/init`/
/// `server/init`, no separate `server/activate`.
class _FakeMusicAssistantServer {
  _FakeMusicAssistantServer(this._socket);

  final WebSocket _socket;
  late final _pump = TestEventPump(_socket);

  Future<Map<String, dynamic>> run() async {
    final clientHelloRaw = await _pump.nextText();
    final clientHello = SendspinEnvelope.decode(clientHelloRaw);
    expect(clientHello.type, MessageType.clientHello);

    final serverHelloPayload = {
      'server_id': 'fake-ma-server',
      'name': 'Fake MA',
      'version': 1,
      'active_roles': ['player@v1', 'controller@v1'],
      'connection_reason': 'discovery',
    };
    _socket.add(SendspinEnvelope(MessageType.serverHello, serverHelloPayload).encode());

    return clientHello.payload;
  }
}

void main() {
  test('SendspinConnection completes the plaintext hello exchange over a real loopback socket',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    late Future<Map<String, dynamic>> fakeServerResult;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      fakeServerResult = _FakeMusicAssistantServer(socket).run();
    });

    const testClientId = 'test-device-id-1234';
    final clientSocket = await WebSocket.connect('ws://127.0.0.1:${server.port}/sendspin');
    final connection = SendspinConnection(
      clientSocket,
      clientId: testClientId,
      deviceName: 'Test Tablet',
    );

    final serverHelloPayload = await connection.handshakeAndActivate();

    expect(serverHelloPayload['active_roles'], contains('player@v1'));

    final receivedClientHello = await fakeServerResult;
    expect(receivedClientHello['client_id'], testClientId);
    expect(receivedClientHello['name'], 'Test Tablet');
    expect(receivedClientHello['supported_roles'], containsAll(['player@v1', 'controller@v1']));

    await connection.close();
    await server.close(force: true);
  });
}
