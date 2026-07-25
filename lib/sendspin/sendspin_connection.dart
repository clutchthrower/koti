import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'wire/binary_frame.dart';
import 'wire/envelope.dart';

/// A decoded role-data binary frame (audio/artwork/etc.) delivered after
/// the connection is established, for the player to consume.
class SendspinBinaryMessage {
  const SendspinBinaryMessage(this.type, this.payload);
  final int type;
  final TimestampedFramePayload payload;
}

/// Queues events off a raw (mixed text/binary) socket stream so the
/// connection lifecycle can `await` each expected message one at a time,
/// instead of juggling a single `listen` callback across every phase.
class _FramePump {
  _FramePump(Stream<dynamic> source) {
    _subscription = source.listen(
      (event) {
        _queue.add(event);
        _drain();
      },
      onDone: () {
        _closed = true;
        _drain();
      },
      onError: (Object error) {
        _error = error;
        _drain();
      },
    );
  }

  late final StreamSubscription<dynamic> _subscription;
  final _queue = <dynamic>[];
  final _waiters = <Completer<void>>[];
  bool _closed = false;
  Object? _error;

  void _drain() {
    while (_waiters.isNotEmpty && (_queue.isNotEmpty || _closed || _error != null)) {
      _waiters.removeAt(0).complete();
    }
  }

  Future<dynamic> next() async {
    while (_queue.isEmpty) {
      if (_error != null) throw _error!;
      if (_closed) throw StateError('Sendspin connection closed');
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    return _queue.removeAt(0);
  }

  Future<String> nextText() async {
    final event = await next();
    if (event is! String) {
      throw StateError('Expected a text frame, got ${event.runtimeType}');
    }
    return event;
  }

  Future<void> cancel() => _subscription.cancel();
}

/// One accepted Sendspin WebSocket connection's lifecycle: `client/hello`
/// as the very first message, sent in plaintext, through to steady-state
/// message pumping.
///
/// This deployed version of the protocol (confirmed by reading the actual
/// `aiosendspin` source Music Assistant ships — no `noise/` module exists
/// in it at all) has none of the encryption/pairing machinery the Sendspin
/// spec's `dev` branch describes: no `client/init`/`server/init`, no Noise
/// handshake, and no separate `server/activate` — `server/hello`'s own
/// `active_roles` field *is* the activation signal. A from-scratch
/// Noise-encrypted implementation matching that newer spec direction still
/// exists in `lib/sendspin/noise/` (unused for now, kept for once MA
/// actually ships it) — this class talks to what's really deployed today.
///
/// Music Assistant dials into this tablet's advertised `_sendspin._tcp`
/// service (the spec's "server-initiated" discovery model), so this is
/// constructed from an already-accepted [WebSocket] — but the Sendspin
/// protocol's own client/server roles are fixed regardless of which side
/// opened the TCP connection: this tablet is always the Sendspin *client*
/// and always sends `client/hello` first.
class SendspinConnection {
  SendspinConnection(this._socket, {required this.clientId, required this.deviceName});

  final WebSocket _socket;

  /// A stable, unique string identifying this tablet — this deployed
  /// protocol doesn't need it to be cryptographic (no Noise handshake to
  /// be the public half of), so callers pass the app's own device id
  /// rather than this class generating a separate identity.
  final String clientId;
  final String deviceName;

  late final _pump = _FramePump(_socket);
  final _controller = StreamController<Object>.broadcast();

  /// Post-hello traffic — [SendspinEnvelope]s and [SendspinBinaryMessage]s
  /// — for the time-sync/audio-playback stage to consume. Closes when the
  /// connection ends.
  Stream<Object> get messages => _controller.stream;

  // 8 seconds of 48kHz/stereo/16-bit PCM — declared to the server as our
  // player buffer capacity in client/hello; generous relative to what a
  // LAN-only, single-hop audio stream actually needs.
  static const _bufferCapacityBytes = 48000 * 2 * 2 * 8;

  /// Sends `client/hello` and awaits `server/hello`, then starts pumping
  /// subsequent traffic onto [messages]. Returns the `server/hello`
  /// payload — its `active_roles` field confirms what actually got
  /// negotiated (e.g. whether `player@v1` is really active).
  Future<Map<String, dynamic>> handshakeAndActivate() async {
    await _sendClientHello();
    final serverHello = await _receiveEnvelope();
    if (serverHello.type != MessageType.serverHello) {
      throw StateError('Expected server/hello, got ${serverHello.type}');
    }
    unawaited(_pumpSteadyState());
    return serverHello.payload;
  }

  /// Sends one JSON message — for use after [handshakeAndActivate]
  /// resolves (`client/time`, `client/state`, ...).
  Future<void> send(SendspinEnvelope envelope) => _sendEnvelope(envelope);

  Future<void> close({String reason = 'user_request'}) async {
    try {
      await _sendEnvelope(SendspinEnvelope(MessageType.clientGoodbye, {'reason': reason}));
    } catch (_) {
      // Best-effort — the socket may already be gone.
    }
    await _pump.cancel();
    await _socket.close();
  }

  Future<void> _sendClientHello() {
    return _sendEnvelope(SendspinEnvelope(MessageType.clientHello, {
      'client_id': clientId,
      'name': deviceName,
      'version': 1,
      'device_info': {'product_name': 'Koti Tablet', 'manufacturer': 'Koti'},
      'supported_roles': ['player@v1', 'controller@v1'],
      'player@v1_support': {
        'supported_formats': [
          {'codec': 'pcm', 'channels': 2, 'sample_rate': 48000, 'bit_depth': 16},
          {'codec': 'pcm', 'channels': 2, 'sample_rate': 44100, 'bit_depth': 16},
        ],
        'buffer_capacity': _bufferCapacityBytes,
        'supported_commands': ['volume', 'mute'],
      },
    }));
  }

  Future<void> _sendEnvelope(SendspinEnvelope envelope) async {
    _socket.add(envelope.encode());
  }

  Future<SendspinEnvelope> _receiveEnvelope() async {
    final raw = await _pump.nextText();
    return SendspinEnvelope.decode(raw);
  }

  Future<void> _pumpSteadyState() async {
    try {
      while (true) {
        final event = await _pump.next();
        if (event is String) {
          _controller.add(SendspinEnvelope.decode(event));
          continue;
        }
        final bytes = event is Uint8List ? event : Uint8List.fromList(event as List<int>);
        final type = bytes[0];
        final payload = TimestampedFramePayload.decode(bytes.sublist(1));
        _controller.add(SendspinBinaryMessage(type, payload));
      }
    } catch (_) {
      // Connection closed/errored — fall through to close the stream below
      // so listeners (the time-sync/audio loop) know to tear down.
    } finally {
      await _controller.close();
    }
  }
}
