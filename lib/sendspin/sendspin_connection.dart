import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'base64url.dart';
import 'identity.dart';
import 'noise/handshake_state.dart';
import 'noise/primitives.dart';
import 'noise/transport_cipher.dart';
import 'wire/binary_frame.dart';
import 'wire/envelope.dart';

const _cipherSuite = '25519_ChaChaPoly_SHA256';

/// Published constant PSK for v1's unpaired-access trust tier — no pairing
/// flow at all. Spec: `SHA256("sendspin-sentinel-psk-v1")`.
Future<Uint8List> sentinelPsk() => sha256Hash(utf8.encode('sendspin-sentinel-psk-v1'));

/// `psk_id = base64url(SHA256("sendspin-psk-id-v1" || psk))` — lets the
/// client pick the matching PSK from the server's first handshake message
/// before the PSK itself is mixed in.
Future<Uint8List> _pskId(Uint8List psk) =>
    sha256Hash([...utf8.encode('sendspin-psk-id-v1'), ...psk]);

/// A decoded role-data binary frame (audio/artwork/etc.) delivered after
/// activation, for the next build stage (time sync + playback) to consume.
class SendspinBinaryMessage {
  const SendspinBinaryMessage(this.type, this.payload);
  final int type;
  final TimestampedFramePayload payload;
}

/// Queues events off a raw (possibly mixed text/binary) socket stream so
/// the handshake's strictly-ordered request/reply sequence can `await` each
/// expected message one at a time, instead of juggling a single `listen`
/// callback across every lifecycle phase.
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

  Future<dynamic> _next() async {
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
    final event = await _next();
    if (event is! String) {
      throw StateError('Expected a text frame, got ${event.runtimeType}');
    }
    return event;
  }

  Future<Uint8List> nextBinary() async {
    final event = await _next();
    if (event is Uint8List) return event;
    if (event is List<int>) return Uint8List.fromList(event);
    throw StateError('Expected a binary frame, got ${event.runtimeType}');
  }

  Future<void> cancel() => _subscription.cancel();
}

/// One accepted Sendspin WebSocket connection's full lifecycle: cleartext
/// `client/init` -> `server/init` -> Noise handshake -> `hello`/`activate`.
/// v1 only ever uses the unpaired-access trust tier (no pairing flow) —
/// see the plan's architecture decisions for why.
///
/// Music Assistant dials into this tablet's advertised `_sendspin._tcp`
/// service (the spec's "server-initiated" discovery model), so this is
/// constructed from an already-accepted [WebSocket] — but the Sendspin
/// protocol's own client/server roles are fixed by spec regardless of which
/// side opened the TCP connection: this tablet is always the Sendspin
/// *client* and always sends `client/init` first, and is always the Noise
/// *responder* (see `noise/handshake_state.dart`).
class SendspinConnection {
  SendspinConnection(this._socket, this._identity, {required this.deviceName});

  final WebSocket _socket;
  final SendspinIdentity _identity;
  final String deviceName;

  late final _pump = _FramePump(_socket);
  final _fragmentReassembler = FragmentReassembler();
  TransportCipher? _sendCipher;
  TransportCipher? _receiveCipher;
  Uint8List? _prologue;

  final _controller = StreamController<Object>.broadcast();

  /// Post-activation traffic — [SendspinEnvelope]s and
  /// [SendspinBinaryMessage]s — for the time-sync/audio-playback stage to
  /// consume. Closes when the connection ends.
  Stream<Object> get messages => _controller.stream;

  // 8 seconds of 48kHz/stereo/16-bit PCM — declared to the server as our
  // player buffer capacity in client/hello; generous relative to what a
  // LAN-only, single-hop audio stream actually needs.
  static const _bufferCapacityBytes = 48000 * 2 * 2 * 8;

  /// Runs the handshake through to `server/activate`, then starts pumping
  /// subsequent traffic onto [messages]. Returns the `server/activate`
  /// payload so the caller can confirm `player@v1` was actually activated.
  Future<Map<String, dynamic>> handshakeAndActivate() async {
    final serverStaticPublicKey = await _exchangeInit();
    await _runNoiseHandshake(serverStaticPublicKey);
    await _receiveEnvelope(); // server/hello — nothing to act on yet
    await _sendClientHello();
    final activate = await _receiveEnvelope();
    if (activate.type != MessageType.serverActivate) {
      throw StateError('Expected server/activate, got ${activate.type}');
    }
    unawaited(_pumpSteadyState());
    return activate.payload;
  }

  Future<void> close({String reason = 'user_request'}) async {
    try {
      if (_sendCipher != null) {
        await _sendEnvelope(SendspinEnvelope(MessageType.clientGoodbye, {'reason': reason}));
      }
    } catch (_) {
      // Best-effort — the socket may already be gone.
    }
    await _pump.cancel();
    await _socket.close();
  }

  Future<Uint8List> _exchangeInit() async {
    final sentRaw = SendspinEnvelope(MessageType.clientInit, {
      'client_id': _identity.clientId,
      'version': 1,
      'suite': _cipherSuite,
    }).encode();
    _socket.add(sentRaw);

    final serverInitRaw = await _pump.nextText();
    final serverInit = SendspinEnvelope.decode(serverInitRaw);
    if (serverInit.type != MessageType.serverInit) {
      throw StateError('Expected server/init, got ${serverInit.type}');
    }
    _prologue = Uint8List.fromList([
      ...utf8.encode(sentRaw),
      ...utf8.encode(serverInitRaw),
    ]);
    return base64UrlNoPadDecode(serverInit.payload['server_id'] as String);
  }

  Future<void> _runNoiseHandshake(Uint8List serverStaticPublicKey) async {
    final handshake = KKpsk2ResponderHandshake(
      localStatic: _identity.keyPair,
      remoteStaticPublicKey: serverStaticPublicKey,
    );
    await handshake.initialize(_prologue!);

    final msg1Raw = await _pump.nextText();
    final msg1Envelope = SendspinEnvelope.decode(msg1Raw);
    if (msg1Envelope.type != MessageType.noiseHandshake) {
      throw StateError('Expected noise/handshake, got ${msg1Envelope.type}');
    }
    final msg1Bytes = base64UrlNoPadDecode(msg1Envelope.payload['data'] as String);
    final msg1Payload = await handshake.readMessage1(msg1Bytes);
    final announcedPskId =
        (jsonDecode(utf8.decode(msg1Payload)) as Map<String, dynamic>)['psk_id'] as String;

    final psk = await sentinelPsk();
    final expectedPskId = base64UrlNoPad(await _pskId(psk));
    if (announcedPskId != expectedPskId) {
      throw StateError(
        'Server did not offer the Sentinel PSK (psk_id mismatch) — unpaired '
        'access requires it; this build has no pairing flow implemented',
      );
    }

    final msg2Bytes = await handshake.writeMessage2(psk, utf8.encode('{}'));
    _socket.add(SendspinEnvelope(MessageType.noiseHandshake, {
      'data': base64UrlNoPad(msg2Bytes),
    }).encode());

    final (sendKey, receiveKey) = await handshake.split();
    _sendCipher = TransportCipher(sendKey);
    _receiveCipher = TransportCipher(receiveKey);
  }

  Future<void> _sendClientHello() async {
    await _sendEnvelope(SendspinEnvelope(MessageType.clientHello, {
      'name': deviceName,
      'device_info': {'product_name': 'Koti Tablet', 'manufacturer': 'Koti'},
      'trust_level': 'none',
      'supported_roles': ['player@v1'],
      'player@v1_support': {
        'supported_formats': [
          {'codec': 'pcm', 'channels': 2, 'sample_rate': 48000, 'bit_depth': 16},
          {'codec': 'pcm', 'channels': 2, 'sample_rate': 44100, 'bit_depth': 16},
        ],
        'buffer_capacity': _bufferCapacityBytes,
        'supported_commands': ['volume', 'mute'],
      },
      'unpaired_access': {'enabled': true},
    }));
  }

  Future<void> _sendEnvelope(SendspinEnvelope envelope) async {
    final plaintext = <int>[BinaryMessageType.jsonBody, ...utf8.encode(envelope.encode())];
    _socket.add(await _sendCipher!.encrypt(plaintext));
  }

  Future<SendspinEnvelope> _receiveEnvelope() async {
    while (true) {
      final rawFrame = await _pump.nextBinary();
      final plaintext = await _receiveCipher!.decrypt(rawFrame);
      final reassembled = _fragmentReassembler.feed(plaintext);
      if (reassembled == null) continue;
      final (type, data) = reassembled;
      if (type != BinaryMessageType.jsonBody) {
        throw StateError('Expected a JSON control message, got binary type $type');
      }
      return SendspinEnvelope.decode(utf8.decode(data));
    }
  }

  Future<void> _pumpSteadyState() async {
    try {
      while (true) {
        final rawFrame = await _pump.nextBinary();
        final plaintext = await _receiveCipher!.decrypt(rawFrame);
        final reassembled = _fragmentReassembler.feed(plaintext);
        if (reassembled == null) continue;
        final (type, data) = reassembled;
        if (type == BinaryMessageType.jsonBody) {
          _controller.add(SendspinEnvelope.decode(utf8.decode(data)));
        } else {
          _controller.add(SendspinBinaryMessage(type, TimestampedFramePayload.decode(data)));
        }
      }
    } catch (_) {
      // Connection closed/errored — fall through to close the stream below
      // so listeners (the time-sync/audio loop) know to tear down.
    } finally {
      await _controller.close();
    }
  }
}
