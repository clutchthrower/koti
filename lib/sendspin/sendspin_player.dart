import 'dart:async';

import 'package:flutter/services.dart';

import 'sendspin_connection.dart';
import 'time_sync.dart';
import 'wire/binary_frame.dart';
import 'wire/envelope.dart';

/// Drives one Sendspin connection's steady state (everything after
/// `server/hello`): the `client/time`/`server/time` sync loop feeding
/// [SendspinTimeFilter], `stream/start` format negotiation, scheduling
/// incoming audio chunks into the native `AudioTrack` sink, reporting
/// player state/volume back to the server, and — via the `controller@v1`
/// role — sending outward transport commands ([play]/[pause]/[stop]/
/// [next]/[previous]) so something outside this connection (Home
/// Assistant, via `KotiHaServer`) can control whatever the connected Music
/// Assistant server is currently playing.
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

  // Bumped on every stream/clear, stream/end, and stream/start. Each
  // incoming audio chunk captures the generation it belongs to before
  // awaiting its scheduled-delivery delay (up to _minBufferMs out); if the
  // generation has since moved on by the time that delay elapses, the
  // chunk is stale (its stream was cleared/replaced mid-flight) and gets
  // dropped instead of written — otherwise it lands in the native sink
  // after the flush/new-track start that was supposed to silence it,
  // which is what caused the old and new track to audibly overlap.
  int _streamGeneration = 0;

  // Declared to the server in client/state — how far ahead of a chunk's
  // play deadline we'd like it delivered, and how much we can buffer.
  // Generous relative to what a single-hop LAN stream actually needs.
  static const _requiredLeadTimeMs = 200;
  static const _minBufferMs = 400;

  // This device's own fixed output latency (write() call to actually
  // audible), MEASURED via AudioTrack.getTimestamp() rather than declared
  // as a fixed guess — see _measureAndReportStaticDelay. Reporting an
  // accurate value here is what lets the server schedule this client's
  // audio far enough ahead to land in sync with other group members;
  // this used to always be a flat 0, which is almost certainly a real
  // contributor to reported multi-second group-sync drift.
  int _staticDelayMs = 0;
  Timer? _latencyMeasureTimer;

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

  /// Sends a `controller@v1` transport command — no local state to
  /// maintain, since it's the connected Music Assistant server that
  /// decides what "next track" means and what's actually playing;
  /// `server/state.controller` feedback isn't tracked here as this app
  /// doesn't currently surface repeat/shuffle/volume-from-controller back
  /// to the user anywhere.
  Future<void> _sendControllerCommand(String command) {
    return _connection.send(SendspinEnvelope(MessageType.clientCommand, {
      'controller': {'command': command},
    }));
  }

  // Named controllerX rather than play()/pause()/stop() to avoid colliding
  // with this class's own start()/stop() lifecycle methods above, which
  // mean something entirely different (tear down this connection).
  Future<void> controllerPlay() => _sendControllerCommand('play');
  Future<void> controllerPause() => _sendControllerCommand('pause');
  Future<void> controllerStop() => _sendControllerCommand('stop');
  Future<void> controllerNext() => _sendControllerCommand('next');
  Future<void> controllerPrevious() => _sendControllerCommand('previous');

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
      // Client-level operational state (separate from the player role's
      // own volume/mute/etc.) — 'synchronized' is what actually satisfies
      // the server's "waiting on initial state" gate for player@v1 and
      // lets it start sending stream/start; omitting this field entirely
      // still connects, but leaves the server's own idea of our state
      // wherever it defaulted, which isn't guaranteed to unblock playback.
      'state': 'synchronized',
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
        // A track skip/seek — buffers reset, but the stream itself keeps
        // going (unlike stream/end), so the sink stays alive and just
        // discards whatever's currently buffered.
        _streamGeneration++;
        unawaited(_flushSink());
      case MessageType.streamEnd:
        _streamGeneration++;
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
    // A new stream/start can arrive as a track change with no preceding
    // stream/clear/stream/end (the server just keeps the connection's
    // stream role active and starts the next track directly) — bump the
    // generation here too so any chunks still in flight for the previous
    // track get dropped rather than written into the freshly (re)started
    // sink.
    _streamGeneration++;
    await _channel.invokeMethod('startSendspinAudioSink', {
      'sampleRate': player['sample_rate'] ?? 48000,
      'channels': player['channels'] ?? 2,
    });
    _sinkStarted = true;
    _scheduleLatencyMeasurement();
  }

  Future<void> _stopSink() async {
    if (!_sinkStarted) return;
    _sinkStarted = false;
    _latencyMeasureTimer?.cancel();
    await _channel.invokeMethod('stopSendspinAudioSink');
  }

  /// First measurement is delayed slightly — AudioTrack.getTimestamp()
  /// reports nothing valid until the HAL has actually consumed some
  /// audio, so measuring immediately after starting the sink would just
  /// see "no timestamp yet". Re-measures periodically after that: the
  /// value is expected to be fairly stable (it's this device's own fixed
  /// hardware/buffer latency) but can shift slightly, e.g. after a buffer
  /// underrun and refill.
  void _scheduleLatencyMeasurement() {
    _latencyMeasureTimer?.cancel();
    _latencyMeasureTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_measureAndReportStaticDelay());
      _latencyMeasureTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_measureAndReportStaticDelay());
      });
    });
  }

  Future<void> _measureAndReportStaticDelay() async {
    if (!_sinkStarted) return;
    final latencyUs = await _channel.invokeMethod<int>('getSendspinOutputLatencyUs');
    if (latencyUs == null || latencyUs <= 0) return; // no valid HAL timestamp yet
    final delayMs = (latencyUs / 1000).round();
    if (delayMs == _staticDelayMs) return; // no meaningful change
    _staticDelayMs = delayMs;
    await _sendClientState();
  }

  Future<void> _flushSink() async {
    if (!_sinkStarted) return;
    await _channel.invokeMethod('flushSendspinAudioSink');
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
    final generation = _streamGeneration;
    if (_timeFilter.isReadyForPrecisionScheduling) {
      final deadlineUs = _timeFilter.computeClientTime(message.payload.timestampUs);
      final delayUs = deadlineUs - _nowUs;
      if (delayUs > 0) {
        await Future<void>.delayed(Duration(microseconds: delayUs));
      }
    }
    // Not yet converged enough to trust precise scheduling: write
    // immediately rather than dropping audio or (worse) delaying against
    // a still-noisy estimate — sync converges within the first several
    // round trips in practice, and AudioTrack's own buffer absorbs the
    // resulting jitter until it does.
    if (generation != _streamGeneration) return; // superseded mid-delay — belongs to a track that's since been cleared/replaced
    // _muted was previously only ever recorded and echoed back in
    // client/state — nothing actually silenced playback when Music
    // Assistant's own volume_mute reached this client via server/command,
    // confirmed live (is_volume_muted flipped true on the mirrored HA
    // entity, audio kept playing at full volume regardless). Checked at
    // write-time (not capture-time) so a mute toggled mid-delay still
    // takes effect for this chunk.
    if (_muted) return;
    await _channel.invokeMethod('writeSendspinPcmChunk', {
      'bytes': message.payload.payload,
    });
  }
}
