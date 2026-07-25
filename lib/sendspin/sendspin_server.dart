import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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
  SendspinServer({required this.deviceName, required this.clientId, this.port = defaultPort});

  // Spec's recommended port for server-initiated discovery (this tablet
  // advertising itself for Music Assistant to find).
  static const defaultPort = 8928;
  static const _channel = MethodChannel('koti/native');

  String deviceName;
  final int port;

  /// The app's own stable device id (`SettingsStore.deviceId` — the same
  /// one `custom_components/koti`'s media_player entity uses as its
  /// `unique_id`), reused here as Sendspin's `client_id` rather than a
  /// separately-generated identity. The deployed protocol only needs
  /// `client_id` to be a stable, unique string, not a cryptographic key
  /// (there's no Noise handshake to be the public half of) — reusing the
  /// same id both integrations already share is what actually lets Music
  /// Assistant's mirrored entity share a `unique_id` with the direct-control
  /// entity, which is what the app's own duplicate-speaker dedup logic
  /// (`dedupedPlayerIds` in `music_players_popup.dart`) keys on. Two
  /// separately-generated identities for the same physical tablet is
  /// exactly what made that dedup unable to recognize them as one device.
  final String clientId;

  HttpServer? _httpServer;
  SendspinConnection? _connection;
  SendspinPlayer? _player;

  bool get running => _httpServer != null;

  /// The live player for whatever Music Assistant connection is currently
  /// active, or null if nothing's connected — read live (not cached) by
  /// `KotiHaServer` each time it needs to forward a transport command, so
  /// it always reflects the current connection rather than a stale one.
  SendspinPlayer? get player => _player;

  Future<void> start() async {
    if (running) return;
    final server = await _bindWithRetry();
    _httpServer = server;
    server.listen(
      // A single malformed/aborted connection attempt shouldn't take the
      // server down — matches koti_ha_server.dart's own behavior.
      // _handleRequest already logs its own failures; this only catches
      // something escaping that (e.g. from the logging call itself).
      (request) => _handleRequest(request).catchError((Object e) {
        // ignore: avoid_print
        print('[sendspin] request failed: $e');
      }),
      onError: (Object e) {
        // ignore: avoid_print
        print('[sendspin] server error: $e');
      },
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

  /// "Restart app" (MainActivity.kt's restartApp()) starts a fresh
  /// Activity/FlutterEngine instance without a true OS-level process
  /// kill, so this port can still be held by the outgoing instance's own
  /// socket for a brief moment after this one's already trying to bind
  /// it — a plain single bind() attempt would surface that as a hard
  /// startup failure instead of the transient condition it actually is.
  Future<HttpServer> _bindWithRetry() async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await HttpServer.bind(InternetAddress.anyIPv4, port);
      } on SocketException {
        if (attempt >= 5) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
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
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      await _disconnect(); // only one connection at a time
      final connection = SendspinConnection(socket, clientId: clientId, deviceName: deviceName);
      _connection = connection;
      await connection.handshakeAndActivate();
      // ignore: avoid_print
      print('[sendspin] connected to ${request.connectionInfo?.remoteAddress.address}');
      final player = SendspinPlayer(connection);
      _player = player;
      await player.start();
    } catch (e) {
      // Kept minimal and permanent (not just a debugging leftover): a
      // silently-swallowed handshake/protocol failure here is otherwise
      // indistinguishable from the server never having started at all —
      // exactly what made an earlier real incompatibility (this client
      // built against a newer, unreleased protocol revision than what
      // Music Assistant actually ships) take a long live-debugging session
      // to even see happening.
      // ignore: avoid_print
      print('[sendspin] connection failed: $e');
    }
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
