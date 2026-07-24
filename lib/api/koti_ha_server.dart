import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../sendspin/sendspin_player.dart';

/// Speaks the Fully Kiosk Browser REST API (`?cmd=X&password=Y&type=json`).
/// Runs always, independent of any Music Assistant setup — it's the
/// backing API `custom_components/koti`'s entities poll and send commands
/// to for direct Home Assistant control: playback/volume on the
/// media_player entity, battery/charging/update-status sensors, restart/
/// reboot buttons, and (via [sendspinController]) transport commands
/// forwarded to whatever Sendspin session is currently connected. It also
/// happens to be compatible with Music Assistant's existing, already-
/// shipped "Fully Kiosk Browser" provider (the same surface the Dashie
/// Kiosk app's `dashie_kiosk` MA provider uses), for anyone who prefers
/// that over the native Sendspin client (`lib/sendspin/`).
/// The password param is accepted but never checked — this device is only
/// reachable on the LAN, matching this app's other unauthenticated local
/// servers (e.g. the Bluetooth proxy). Volume goes through Android's real
/// STREAM_MUSIC (a platform channel call, not the audio player's own
/// gain) — otherwise a remote volume slider silently multiplies against
/// whatever the device's physical volume happens to be set to.
///
/// Also advertises itself over mDNS (`_koti._tcp`, see MainActivity.kt) so
/// `custom_components/koti` can auto-discover the tablet.
class KotiHaServer {
  static const defaultPort = 8127;
  static const _channel = MethodChannel('koti/native');

  final String id;
  String name;
  final int port;

  /// Live getters rather than fixed values, since the current app
  /// version/update state and the connected Sendspin session (if any) can
  /// all change while this server keeps running.
  final String Function() currentVersion;
  final String? Function() latestVersion;
  final SendspinPlayer? Function() sendspinController;

  KotiHaServer({
    required this.id,
    required this.name,
    required this.currentVersion,
    required this.latestVersion,
    required this.sendspinController,
    this.port = defaultPort,
  }) {
    // Only an explicit stopSound cleared `_currentUrl` — a track that
    // finishes on its own left it set forever, so `soundUrlPlaying` (and
    // therefore the HA entity's and MA player's derived playback state)
    // never went back to idle. Both then kept extrapolating elapsed time
    // forward from the last known position while "still playing", which is
    // what showed up as playtime counting up past the track's own duration.
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _currentUrl = null;
      }
    });
  }

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
      case 'restartApp':
        await _handleRestartApp(request);
      case 'rebootDevice':
        await _handleRebootDevice(request);
      case 'sendspinPlay':
        await _handleSendspinCommand(request, (p) => p.controllerPlay());
      case 'sendspinPause':
        await _handleSendspinCommand(request, (p) => p.controllerPause());
      case 'sendspinStop':
        await _handleSendspinCommand(request, (p) => p.controllerStop());
      case 'sendspinNext':
        await _handleSendspinCommand(request, (p) => p.controllerNext());
      case 'sendspinPrevious':
        await _handleSendspinCommand(request, (p) => p.controllerPrevious());
      default:
        await _respondError(request, 'Unknown command: ${params['cmd']}');
    }
  }

  Future<void> _respondDeviceInfo(HttpRequest request) async {
    int volume = 100;
    try {
      volume = await _channel.invokeMethod<int>('getMusicVolume') ?? 100;
    } catch (_) {}

    var batteryLevel = 0;
    var batteryCharging = false;
    try {
      final battery = await _channel.invokeMethod<Map<Object?, Object?>>('getBatteryStatus');
      batteryLevel = battery?['level'] as int? ?? 0;
      batteryCharging = battery?['charging'] as bool? ?? false;
    } catch (_) {}

    final current = currentVersion();
    final latest = latestVersion();

    await _respondJson(request, {
      'deviceID': id,
      'deviceName': name,
      'deviceModel': 'Koti Tablet',
      'audioVolume': volume,
      'soundUrlPlaying': _currentUrl ?? '',
      'audioPosition': _player.position.inMilliseconds,
      'batteryLevel': batteryLevel,
      'batteryCharging': batteryCharging,
      'appVersion': current,
      'appLatestVersion': latest,
      'appUpdateAvailable': latest != null && latest != current,
      'sendspinConnected': sendspinController() != null,
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

  Future<void> _handleRestartApp(HttpRequest request) async {
    // Respond before triggering the restart — the native side kills this
    // process shortly after, and this response needs to actually flush
    // over the socket before that happens.
    await _respondJson(request, {'status': 'OK'});
    try {
      await _channel.invokeMethod('restartApp');
    } catch (_) {}
  }

  Future<void> _handleRebootDevice(HttpRequest request) async {
    try {
      final result = await _channel.invokeMethod<String>('rebootDevice');
      if (result == 'ok') {
        await _respondJson(request, {'status': 'OK'});
      } else {
        // Most commonly "requires_device_owner" — a normal Android app
        // can't reboot the device without Device Owner mode (see README).
        await _respondError(request, result ?? 'error');
      }
    } catch (e) {
      await _respondError(request, 'Reboot failed: $e');
    }
  }

  Future<void> _handleSendspinCommand(
    HttpRequest request,
    Future<void> Function(SendspinPlayer) action,
  ) async {
    final player = sendspinController();
    if (player == null) {
      await _respondError(request, 'No Sendspin session connected');
      return;
    }
    try {
      await action(player);
      await _respondJson(request, {'status': 'OK'});
    } catch (e) {
      await _respondError(request, 'Command failed: $e');
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
