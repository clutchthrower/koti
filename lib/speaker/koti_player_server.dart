import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Speaks the Fully Kiosk Browser REST API (`?cmd=X&password=Y&type=json`)
/// so this tablet can be added as a player in Music Assistant's existing,
/// already-shipped "Fully Kiosk Browser" provider — the same API surface
/// the Dashie Kiosk app's MA provider (`dashie_kiosk`) uses. A real
/// Koti-branded MA provider would need code merged into music-assistant's
/// own server repo (see `music_assistant/providers/dashie_kiosk/` for the
/// pattern); this is the interim path that works with what MA ships today.
/// The password param is accepted but never checked — this device is only
/// reachable on the LAN, matching this app's other unauthenticated local
/// servers (e.g. the Bluetooth proxy). Volume goes through Android's real
/// STREAM_MUSIC (a platform channel call, not the audio player's own
/// gain) — otherwise MA's volume slider silently multiplies against
/// whatever the device's physical volume happens to be set to.
///
/// Also advertises itself over mDNS (`_koti._tcp`, see MainActivity.kt) so
/// this app's own `custom_components/koti` Home Assistant integration can
/// still auto-discover the tablet as a plain HA device/entity — separate
/// from, and unrelated to, how Music Assistant finds it.
class KotiPlayerServer {
  static const defaultPort = 8127;
  static const _channel = MethodChannel('koti/native');

  final String id;
  String name;
  final int port;

  KotiPlayerServer({required this.id, required this.name, this.port = defaultPort});

  HttpServer? _server;
  final AudioPlayer _player = AudioPlayer();
  String? _currentUrl;

  bool get running => _server != null;

  Future<void> start() async {
    if (running) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(
      (request) => _handle(request).catchError((_) {
        // A single malformed/aborted request shouldn't take the server down.
      }),
      onError: (_) {},
      cancelOnError: false,
    );
    try {
      await _channel.invokeMethod('startKotiDiscovery', {
        'name': name,
        'id': id,
        'port': port,
      });
    } catch (_) {
      // Discovery is a convenience, not a hard requirement — the server
      // still works if someone adds it by IP.
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    await _player.stop();
    _currentUrl = null;
    try {
      await _channel.invokeMethod('stopKotiDiscovery');
    } catch (_) {}
  }

  /// Re-announces under the new name without a full stop/start — used
  /// when the user renames the device in Settings while this is running.
  Future<void> updateName(String newName) async {
    name = newName;
    if (!running) return;
    try {
      await _channel.invokeMethod('startKotiDiscovery', {
        'name': name,
        'id': id,
        'port': port,
      });
    } catch (_) {}
  }

  Future<void> _handle(HttpRequest request) async {
    final params = request.uri.queryParameters;
    switch (params['cmd']) {
      case 'deviceInfo':
        await _respondDeviceInfo(request);
      case 'playSound':
        await _handlePlaySound(request, params);
      case 'stopSound':
        await _handleStopSound(request);
      case 'pauseSound':
        await _handlePauseSound(request);
      case 'resumeSound':
        await _handleResumeSound(request);
      case 'seekSound':
        await _handleSeekSound(request, params);
      case 'setAudioVolume':
        await _handleSetAudioVolume(request, params);
      default:
        await _respondError(request, 'Unknown command: ${params['cmd']}');
    }
  }

  Future<void> _respondDeviceInfo(HttpRequest request) async {
    int volume = 100;
    try {
      volume = await _channel.invokeMethod<int>('getMusicVolume') ?? 100;
    } catch (_) {}
    await _respondJson(request, {
      'deviceID': id,
      'deviceName': name,
      'deviceModel': 'Koti Tablet',
      'audioVolume': volume,
      'soundUrlPlaying': _currentUrl ?? '',
      'audioPosition': _player.position.inMilliseconds,
    });
  }

  Future<void> _handlePlaySound(HttpRequest request, Map<String, String> params) async {
    final url = params['url'];
    if (url == null || url.isEmpty) {
      await _respondError(request, 'Missing url');
      return;
    }
    try {
      await _player.setUrl(url);
      _currentUrl = url;
      // Deliberately not awaited: play() only completes once playback
      // finishes (or is paused), which would hang this HTTP response for
      // the whole track.
      unawaited(_player.play());
      await _respondJson(request, {'status': 'OK'});
    } catch (e) {
      _currentUrl = null;
      await _respondError(request, 'Playback failed: $e');
    }
  }

  Future<void> _handleStopSound(HttpRequest request) async {
    await _player.stop();
    _currentUrl = null;
    await _respondJson(request, {'status': 'OK'});
  }

  Future<void> _handlePauseSound(HttpRequest request) async {
    await _player.pause();
    await _respondJson(request, {'status': 'OK'});
  }

  Future<void> _handleResumeSound(HttpRequest request) async {
    if (_currentUrl != null) unawaited(_player.play());
    await _respondJson(request, {'status': 'OK'});
  }

  Future<void> _handleSeekSound(HttpRequest request, Map<String, String> params) async {
    final positionMs = int.tryParse(params['position'] ?? '');
    if (positionMs == null) {
      await _respondError(request, 'Missing position');
      return;
    }
    try {
      await _player.seek(Duration(milliseconds: positionMs));
      await _respondJson(request, {'status': 'OK'});
    } catch (e) {
      await _respondError(request, 'Seek failed: $e');
    }
  }

  Future<void> _handleSetAudioVolume(HttpRequest request, Map<String, String> params) async {
    final level = int.tryParse(params['level'] ?? '');
    if (level == null) {
      await _respondError(request, 'Missing level');
      return;
    }
    try {
      await _channel.invokeMethod('setMusicVolume', {'percent': level.clamp(0, 100)});
      await _respondJson(request, {'status': 'OK'});
    } catch (e) {
      await _respondError(request, 'Volume change failed: $e');
    }
  }

  Future<void> _respondJson(HttpRequest request, Map<String, dynamic> body) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  // Fully Kiosk's own error convention is a 200 response with a
  // {"status": "Error", ...} body, not an HTTP error status — MA's client
  // checks the body, not the status code, so this must match.
  Future<void> _respondError(HttpRequest request, String message) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'status': 'Error', 'statustext': message}));
    await request.response.close();
  }
}
