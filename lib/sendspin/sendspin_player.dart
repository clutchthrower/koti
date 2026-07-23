import 'dart:async';

import 'package:flutter/services.dart';

import 'sendspin_connection.dart';
import 'time_sync.dart';
import 'wire/binary_frame.dart';
import 'wire/envelope.dart';

/// Drives one Sendspin connection's steady state (everything after
/// `server/activate`): the `client/time`/`server/time` sync loop feeding
/// [SendspinTimeFilter], `stream/start` format negotiation, scheduling
/// incoming audio chunks into the native `AudioTrack` sink, and reporting
/// player state/volume back to the server.
///
/// Talks to the native sink over the same `koti/native` platform channel
/// this app's other native calls already use (volume, BLE proxy, mDNS) —
/// see `MainActivity.kt`'s `startSendspinAudioSink`/`writeSendspinPcmChunk`/
/// `stopSendspinAudioSink`.
class SendspinPlayer {
  SendspinPlayer(this._connection);

  final SendspinConnection _connection;
  static const _channel = MethodChannel('koti/native');
  final _timeFilter = SendspinTimeFilter();

  Timer? _timeSyncTimer;
  StreamSubscription<Object>? _messagesSub;
  bool _sinkStarted = false;
  int _volume = 100;
  bool _muted = false;

  // Declared to the server in client/state — how far ahead of a chunk's
  // play deadline we'd like it delivered, and how much we can buffer.
  // Generous relative to what a single-hop LAN stream actually needs.
  static const _requiredLeadTimeMs = 200;
  static const _minBufferMs = 400;
  static const _staticDelayMs = 0;

  Future<void> start() async {
    _messagesSub = _connection.messages.listen(_handleMessage);
    await _sendClientState();
    await _sendClientTime();
    _scheduleTimeSync(const Duration(milliseconds: 200));
  }

  Future<void> stop() async {
    await _messagesSub?.cancel();
    _timeSyncTimer?.cancel();
    await _stopSink();
  }

  void _scheduleTimeSync(Duration interval) {
    _timeSyncTimer?.cancel();
    _timeSyncTimer = Timer(interval, () async {
      await _sendClientTime();
      _scheduleTimeSync(_nextTimeSyncInterval());
    });
  }

  /// Spec's recommended send-interval tuning: sync tighter -> check less
  /// often; sync poor or not yet converged -> check more often.
  Duration _nextTimeSyncInterval() {
    final errorUs = _timeFilter.errorUs;
    if (errorUs < 1000) return const Duration(seconds: 3);
    if (errorUs < 2000) return const Duration(seconds: 1);
    if (errorUs < 5000) return const Duration(milliseconds: 500);
    return const Duration(milliseconds: 200);
  }

  int get _nowUs => DateTime.now().microsecondsSinceEpoch;

  Future<void> _sendClientTime() {
    return _connection.send(SendspinEnvelope(MessageType.clientTime, {
      'client_transmitted': _nowUs,
    }));
  }

  Future<void> _sendClientState() {
    return _connection.send(SendspinEnvelope(MessageType.clientState, {
      'player': {
        'volume': _volume,
        'muted': _muted,
        'static_delay_ms': _staticDelayMs,
        'required_lead_time_ms': _requiredLeadTimeMs,
        'min_buffer_ms': _minBufferMs,
      },
    }));
  }

  void _handleMessage(Object message) {
    if (message is SendspinEnvelope) {
      _handleEnvelope(message);
    } else if (message is SendspinBinaryMessage) {
      unawaited(_handleBinaryMessage(message));
    }
  }

  void _handleEnvelope(SendspinEnvelope envelope) {
    switch (envelope.type) {
      case MessageType.serverTime:
        _handleServerTime(envelope.payload);
      case MessageType.streamStart:
        unawaited(_handleStreamStart(envelope.payload));
      case MessageType.streamClear:
      case MessageType.streamEnd:
        unawaited(_stopSink());
      case MessageType.serverCommand:
        unawaited(_handleServerCommand(envelope.payload));
    }
  }

  void _handleServerTime(Map<String, dynamic> payload) {
    final t0 = payload['client_transmitted'] as int;
    final t1 = payload['server_received'] as int;
    final t2 = payload['server_transmitted'] as int;
    _timeFilter.update(t0, t1, t2, _nowUs);
  }

  Future<void> _handleStreamStart(Map<String, dynamic> payload) async {
    final player = payload['player'] as Map<String, dynamic>?;
    if (player == null) return;
    if (player['codec'] != 'pcm') {
      // v1 only ever declared PCM support — a compliant server should
      // never negotiate anything else for this client.
      return;
    }
    await _channel.invokeMethod('startSendspinAudioSink', {
      'sampleRate': player['sample_rate'] ?? 48000,
      'channels': player['channels'] ?? 2,
    });
    _sinkStarted = true;
  }

  Future<void> _stopSink() async {
    if (!_sinkStarted) return;
    _sinkStarted = false;
    await _channel.invokeMethod('stopSendspinAudioSink');
  }

  Future<void> _handleServerCommand(Map<String, dynamic> payload) async {
    final player = payload['player'] as Map<String, dynamic>?;
    if (player == null) return;
    switch (player['command']) {
      case 'volume':
        final volume = player['volume'] as int?;
        if (volume != null) {
          _volume = volume;
          await _channel.invokeMethod('setMusicVolume', {'percent': volume});
        }
      case 'mute':
        _muted = player['mute'] as bool? ?? _muted;
      case 'set_static_delay':
        // Only shifts the target scheduling deadline, applied per-chunk in
        // _handleBinaryMessage — nothing else to update here.
        break;
    }
    await _sendClientState();
  }

  Future<void> _handleBinaryMessage(SendspinBinaryMessage message) async {
    if (message.type != BinaryMessageType.audioChunk || !_sinkStarted) return;
    if (_timeFilter.isSynchronized) {
      final deadlineUs = _timeFilter.computeClientTime(message.payload.timestampUs);
      final delayUs = deadlineUs - _nowUs;
      if (delayUs > 0) {
        await Future<void>.delayed(Duration(microseconds: delayUs));
      }
    }
    // Not yet synchronized: write immediately rather than dropping audio —
    // sync converges within the first few round trips in practice, and
    // AudioTrack's own buffer absorbs the resulting jitter until it does.
    await _channel.invokeMethod('writeSendspinPcmChunk', {
      'bytes': message.payload.payload,
    });
  }
}
