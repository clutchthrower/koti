import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'identity.dart';
import 'sendspin_connection.dart';
import 'sendspin_player.dart';

/// Runs the Sendspin listener: advertises this tablet over mDNS
/// (`_sendspin._tcp`, the spec's "server-initiated" discovery model — this
/// tablet advertises, Music Assistant finds and dials in) and accepts the
/// resulting WebSocket at `/sendspin`, handing it off to a
/// [SendspinConnection] + [SendspinPlayer] pair. Mirrors
/// `koti_player_server.dart`'s shape (bind an HttpServer, advertise via the
/// same native `koti/native` MethodChannel pattern), since this is the same
/// "run a small local server, let the discovering side dial in" model —
/// just Sendspin's own protocol instead of the Fully Kiosk Browser REST API.
///
/// At most one active connection at a time — a new incoming one replaces
/// whatever came before, matching a single physical speaker only ever
/// being controlled by one Music Assistant server.
class SendspinServer {
  SendspinServer({required this.deviceName, this.port = defaultPort});

  // Spec's recommended port for server-initiated discovery (this tablet
  // advertising itself for Music Assistant to find).
  static const defaultPort = 8928;
  static const _channel = MethodChannel('koti/native');

  String deviceName;
  final int port;

  HttpServer? _httpServer;
  SendspinIdentity? _identity;
  SendspinConnection? _connection;
  SendspinPlayer? _player;

  bool get running => _httpServer != null;

  Future<void> start() async {
    if (running) return;
    _identity = await SendspinIdentity.load();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _httpServer = server;
    server.listen(
      (request) => _handleRequest(request).catchError((_) {
        // A single malformed/aborted connection attempt shouldn't take the
        // server down — matches koti_player_server.dart's own behavior.
      }),
      onError: (_) {},
      cancelOnError: false,
    );
    try {
      await _channel.invokeMethod('startSendspinDiscovery', {
        'name': deviceName,
        'port': port,
      });
    } catch (_) {
      // Discovery is a convenience, not a hard requirement — Music
      // Assistant can still be pointed at this tablet manually by address.
    }
  }

  Future<void> stop() async {
    final server = _httpServer;
    _httpServer = null;
    await server?.close(force: true);
    await _disconnect();
    try {
      await _channel.invokeMethod('stopSendspinDiscovery');
    } catch (_) {}
  }

  /// Re-announces under the new name without a full stop/start — used when
  /// the user renames the device in Settings while this is running.
  Future<void> updateName(String newName) async {
    deviceName = newName;
    if (!running) return;
    try {
      await _channel.invokeMethod('startSendspinDiscovery', {
        'name': deviceName,
        'port': port,
      });
    } catch (_) {}
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    await _disconnect(); // only one connection at a time
    final connection = SendspinConnection(socket, _identity!, deviceName: deviceName);
    _connection = connection;
    await connection.handshakeAndActivate();
    final player = SendspinPlayer(connection);
    _player = player;
    await player.start();
  }

  Future<void> _disconnect() async {
    final player = _player;
    _player = null;
    if (player != null) await player.stop();
    final connection = _connection;
    _connection = null;
    if (connection != null) await connection.close();
  }
}
