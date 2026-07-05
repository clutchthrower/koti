import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// One BLE advertisement observed by the tablet's radio, ready to relay.
class BleAdvertisement {
  /// MAC as a 48-bit integer (ESPHome wire format).
  final int address;
  final int rssi;

  /// 0 = public, 1 = random (heuristic from the address' top bits).
  final int addressType;

  /// Raw advertising payload (AD structures) as seen over the air.
  final Uint8List data;

  const BleAdvertisement({
    required this.address,
    required this.rssi,
    required this.addressType,
    required this.data,
  });
}

/// Minimal ESPHome native-API server (plaintext) that presents this tablet
/// to Home Assistant as a Bluetooth proxy — the same protocol ESPHome
/// devices speak on port 6053. Only the handshake, device info, and the
/// raw BLE advertisement stream are implemented; there are no entities.
///
/// Message ids/fields come from `reference_hemma/esphome/api.proto`
/// (esphome/aioesphomeapi). Feature flags: PASSIVE_SCAN | RAW_ADVERTISEMENTS.
class EsphomeServer {
  static const port = 6053;
  static const _featureFlags = 1 | 32; // passive scan + raw advertisements

  final String name; // hostname-style, e.g. "hemma-tablet"
  final String friendlyName;
  final String macAddress; // "AA:BB:CC:DD:EE:FF"
  final String bluetoothMacAddress;

  /// Optional diagnostics hook (dev tools); no-op in the app.
  final void Function(String message)? log;

  ServerSocket? _server;
  final List<_Client> _clients = [];

  EsphomeServer({
    required this.name,
    required this.friendlyName,
    required this.macAddress,
    required this.bluetoothMacAddress,
    this.log,
  });

  bool get hasSubscribers => _clients.any((c) => c.subscribed);

  Future<void> start() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server!.listen((socket) {
      log?.call('client connected: ${socket.remoteAddress.address}');
      final client = _Client(socket, this);
      _clients.add(client);
      client.onClosed = () {
        log?.call('client disconnected');
        _clients.remove(client);
      };
    });
  }

  Future<void> stop() async {
    for (final c in List.of(_clients)) {
      c.close();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
  }

  /// Relays a batch of advertisements to every subscribed client
  /// (BluetoothLERawAdvertisementsResponse, id 93).
  void sendAdvertisements(List<BleAdvertisement> ads) {
    if (ads.isEmpty) return;
    final w = _ProtoWriter();
    for (final ad in ads) {
      final item = _ProtoWriter()
        ..varintField(1, ad.address)
        ..sint32Field(2, ad.rssi)
        ..varintField(3, ad.addressType)
        ..bytesField(4, ad.data);
      w.messageField(1, item);
    }
    final frame = _frame(93, w.bytes);
    for (final c in _clients.where((c) => c.subscribed)) {
      c.add(frame);
    }
  }

  // ---- message handling ----------------------------------------------

  void _handleMessage(_Client client, int type, Uint8List payload) {
    log?.call('received message type $type (${payload.length} bytes)');
    switch (type) {
      case 1: // HelloRequest
        final w = _ProtoWriter()
          ..varintField(1, 1) // api major
          ..varintField(2, 10) // api minor
          ..stringField(3, 'Koti Bluetooth Proxy')
          ..stringField(4, name);
        client.add(_frame(2, w.bytes));
        break;
      case 3: // legacy AuthenticationRequest — accept unconditionally
        client.add(_frame(4, Uint8List(0)));
        break;
      case 5: // DisconnectRequest
        client.add(_frame(6, Uint8List(0)));
        client.close();
        break;
      case 7: // PingRequest
        client.add(_frame(8, Uint8List(0)));
        break;
      case 9: // DeviceInfoRequest
        final w = _ProtoWriter()
          ..stringField(2, name)
          ..stringField(3, macAddress)
          // Reported "ESPHome version": HA files an update-nag repair for
          // anything below its supported minimum (2026.5.1 as of now), so
          // track something current. Bump when HA complains again.
          ..stringField(4, '2026.6.0')
          ..stringField(6, 'Koti Tablet')
          ..stringField(12, 'Koti')
          ..stringField(13, friendlyName)
          ..varintField(15, _featureFlags)
          ..stringField(18, bluetoothMacAddress);
        client.add(_frame(10, w.bytes));
        break;
      case 11: // ListEntitiesRequest — we expose none
        client.add(_frame(19, Uint8List(0)));
        break;
      case 20: // SubscribeStatesRequest — nothing to send
        break;
      case 66: // SubscribeBluetoothLEAdvertisementsRequest
        client.subscribed = true;
        break;
      default:
        // Unknown/unsupported messages are ignored, like a device without
        // that feature compiled in.
        break;
    }
  }

  static Uint8List _frame(int type, Uint8List payload) {
    final b = BytesBuilder();
    b.addByte(0); // plaintext indicator
    b.add(_varint(payload.length));
    b.add(_varint(type));
    b.add(payload);
    return b.toBytes();
  }

  static Uint8List _varint(int value) {
    final b = BytesBuilder();
    var v = value;
    while (v >= 0x80) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
    return b.toBytes();
  }
}

class _Client {
  final Socket socket;
  final EsphomeServer server;
  final List<int> _buffer = [];
  bool subscribed = false;
  bool _closed = false;
  VoidCallback? onClosed;

  _Client(this.socket, this.server) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.listen(_onData, onDone: close, onError: (_) => close());
  }

  void add(Uint8List bytes) {
    if (_closed) return;
    try {
      socket.add(bytes);
    } catch (_) {
      close();
    }
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    while (true) {
      if (_buffer.isEmpty) return;
      // A first byte of 0x01 means the client wants Noise encryption,
      // which this proxy doesn't speak — close so HA reports it clearly.
      if (_buffer[0] != 0) {
        close();
        return;
      }
      var offset = 1;
      final len = _readVarint(offset);
      if (len == null) return;
      offset = len.$2;
      final type = _readVarint(offset);
      if (type == null) return;
      offset = type.$2;
      if (_buffer.length < offset + len.$1) return; // incomplete frame
      final payload =
          Uint8List.fromList(_buffer.sublist(offset, offset + len.$1));
      _buffer.removeRange(0, offset + len.$1);
      server._handleMessage(this, type.$1, payload);
      if (_closed) return;
    }
  }

  /// Returns (value, nextOffset) or null if the buffer is incomplete.
  (int, int)? _readVarint(int offset) {
    var result = 0;
    var shift = 0;
    var i = offset;
    while (true) {
      if (i >= _buffer.length) return null;
      final byte = _buffer[i++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return (result, i);
      shift += 7;
      if (shift > 35) return (0, i); // malformed; will be dropped
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      socket.destroy();
    } catch (_) {}
    onClosed?.call();
  }
}

typedef VoidCallback = void Function();

/// Just enough protobuf encoding for the messages above.
class _ProtoWriter {
  final BytesBuilder _b = BytesBuilder();

  Uint8List get bytes => _b.toBytes();

  void _tag(int field, int wire) => _varint((field << 3) | wire);

  void _varint(int value) {
    var v = value;
    while (v >= 0x80) {
      _b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _b.addByte(v);
  }

  void varintField(int field, int value) {
    if (value == 0) return;
    _tag(field, 0);
    _varint(value);
  }

  void sint32Field(int field, int value) {
    _tag(field, 0);
    _varint((value << 1) ^ (value >> 31)); // zigzag
  }

  void bytesField(int field, List<int> data) {
    _tag(field, 2);
    _varint(data.length);
    _b.add(data);
  }

  void stringField(int field, String s) {
    if (s.isEmpty) return;
    bytesField(field, s.codeUnits);
  }

  void messageField(int field, _ProtoWriter inner) =>
      bytesField(field, inner.bytes);
}
