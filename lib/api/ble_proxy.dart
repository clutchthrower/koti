import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// One BLE advertisement observed by the tablet's radio, ready to relay.
class BleAdvertisement {
  final String address; // "AA:BB:CC:DD:EE:FF"
  final int rssi;

  /// Raw advertising payload (AD structures) as seen over the air — parsed
  /// server-side by `custom_components/koti/bluetooth.py` (via
  /// `bluetooth_data_tools`), not here.
  final Uint8List data;

  /// Client epoch ms when this was captured — lets the server reconstruct
  /// a reasonably accurate presentation time even if the POST itself lands
  /// a little late.
  final int timestampMs;

  const BleAdvertisement({
    required this.address,
    required this.rssi,
    required this.data,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'address': address,
        'rssi': rssi,
        'raw': base64Encode(data),
        'timestamp': timestampMs,
      };
}

/// Streams nearby BLE advertisements to Home Assistant so this tablet acts
/// as a passive (presence-only, not connectable) Bluetooth proxy.
///
/// Deliberately does NOT implement the ESPHome native-API protocol the way
/// this used to — that's what made HA's own `esphome` integration
/// auto-discover the tablet as a second, unrelated Device. Instead, this
/// just batches raw scan results (same ~300ms cadence as before) and POSTs
/// them as JSON to a webhook `custom_components/koti/bluetooth.py`
/// registers under this tablet's own existing Koti Device — see
/// `KotiHaServer`'s `setBleWebhook` command for how this learns the
/// webhook id to push to.
class BleProxy {
  static const _channel = MethodChannel('koti/native');
  static const _scanChannel = EventChannel('koti/ble');

  final String Function() activeUrl;

  BleProxy({required this.activeUrl});

  bool _running = false;
  String? _webhookId;
  StreamSubscription? _scanSub;
  Timer? _flushTimer;
  final List<BleAdvertisement> _pending = [];
  final Map<String, int> _lastForwarded = {};

  bool get running => _running;

  /// Where this tablet should POST its advertisement batches — learned
  /// from Home Assistant (see `KotiHaServer`'s `setBleWebhook` command),
  /// not decided locally. `null` until then; batches collected before it's
  /// known are simply dropped rather than buffered indefinitely.
  void setWebhookId(String? id) {
    _webhookId = (id != null && id.isNotEmpty) ? id : null;
  }

  Future<String> start() async {
    if (_running) return 'ok';
    final status = await _channel.invokeMethod<String>('startBleScan') ?? 'error';
    if (status != 'ok') return status;

    _running = true;
    _scanSub = _scanChannel.receiveBroadcastStream().listen(_onScan);
    _flushTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      unawaited(_flush());
    });
    return 'ok';
  }

  void _onScan(dynamic event) {
    final map = (event as Map).cast<String, dynamic>();
    final address = map['address'] as String? ?? '';
    final rssi = map['rssi'] as int? ?? 0;
    final data = map['data'] as Uint8List? ?? Uint8List(0);
    if (address.isEmpty || data.isEmpty) return;

    // Rate-limit per device: BLE beacons chatter several times a second,
    // and HA only needs a fresh reading every so often.
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastForwarded[address] ?? 0;
    if (now - last < 800) return;
    _lastForwarded[address] = now;

    if (_pending.length < 24) {
      _pending.add(BleAdvertisement(
        address: address,
        rssi: rssi,
        data: data,
        timestampMs: now,
      ));
    }
  }

  Future<void> _flush() async {
    final webhookId = _webhookId;
    if (_pending.isEmpty || webhookId == null) {
      _pending.clear();
      return;
    }
    final batch = List<BleAdvertisement>.of(_pending);
    _pending.clear();
    try {
      await http
          .post(
            Uri.parse('${activeUrl()}/api/webhook/$webhookId'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(batch.map((a) => a.toJson()).toList()),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort — dropped batches aren't retried, matching the old
      // ESPHome path's behavior of simply not delivering to a momentarily
      // unreachable Home Assistant.
    }
  }

  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _channel.invokeMethod('stopBleScan');
    } catch (_) {}
    _running = false;
    _pending.clear();
    _lastForwarded.clear();
  }
}
