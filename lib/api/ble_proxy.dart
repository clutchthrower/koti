import 'dart:async';

import 'package:flutter/services.dart';

import 'esphome_server.dart';

/// Ties the pieces of the Bluetooth proxy together: the native BLE scanner
/// (EventChannel), the ESPHome API server, and the mDNS advertisement that
/// makes Home Assistant discover the tablet on Devices & services.
class BleProxy {
  static const _channel = MethodChannel('hemma/native');
  static const _scanChannel = EventChannel('hemma/ble');

  EsphomeServer? _server;
  StreamSubscription? _scanSub;
  Timer? _flushTimer;
  final List<BleAdvertisement> _pending = [];
  final Map<int, int> _lastForwarded = {};

  bool get running => _server != null;

  /// Derives a stable, locally-administered MAC from the install's device
  /// id — ESPHome devices are identified by MAC, so it must not change.
  static String macFrom(String deviceId, {int variant = 0}) {
    final hex = (deviceId + '0' * 12).substring(0, 12).toUpperCase();
    final pairs = [
      variant == 0 ? '02' : '06',
      for (var i = 2; i < 12; i += 2) hex.substring(i, i + 2),
    ];
    return pairs.join(':');
  }

  Future<String> start({required String deviceId}) async {
    if (running) return 'ok';
    final mac = macFrom(deviceId);
    final server = EsphomeServer(
      name: 'koti-tablet',
      friendlyName: 'Koti Tablet',
      macAddress: mac,
      bluetoothMacAddress: macFrom(deviceId, variant: 1),
    );
    await server.start();

    final status = await _channel.invokeMethod<String>('startBleProxy', {
          'name': 'koti-tablet',
          'friendlyName': 'Koti Tablet',
          'mac': mac,
          'port': EsphomeServer.port,
        }) ??
        'error';
    if (status != 'ok') {
      await server.stop();
      return status;
    }

    _server = server;
    _scanSub = _scanChannel.receiveBroadcastStream().listen(_onScan);
    _flushTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_pending.isEmpty || !(server.hasSubscribers)) {
        _pending.clear();
        return;
      }
      server.sendAdvertisements(List.of(_pending));
      _pending.clear();
    });
    return 'ok';
  }

  void _onScan(dynamic event) {
    final map = (event as Map).cast<String, dynamic>();
    final addressStr = map['address'] as String? ?? '';
    final rssi = map['rssi'] as int? ?? 0;
    final data = map['data'] as Uint8List? ?? Uint8List(0);
    if (addressStr.isEmpty || data.isEmpty) return;

    final address =
        int.tryParse(addressStr.replaceAll(':', ''), radix: 16) ?? 0;
    if (address == 0) return;

    // Rate-limit per device: BLE beacons chatter several times a second,
    // and HA only needs a fresh reading every so often.
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastForwarded[address] ?? 0;
    if (now - last < 800) return;
    _lastForwarded[address] = now;

    // Random static addresses have the two top bits set.
    final firstOctet = (address >> 40) & 0xff;
    final addressType = (firstOctet & 0xC0) == 0xC0 ? 1 : 0;

    if (_pending.length < 24) {
      _pending.add(BleAdvertisement(
        address: address,
        rssi: rssi,
        addressType: addressType,
        // ESPHome caps raw payloads at 62 bytes; Android pads its buffer
        // to 62 with zeros already, but trim defensively.
        data: data.length > 62 ? Uint8List.sublistView(data, 0, 62) : data,
      ));
    }
  }

  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _channel.invokeMethod('stopBleProxy');
    } catch (_) {}
    await _server?.stop();
    _server = null;
    _pending.clear();
    _lastForwarded.clear();
  }
}
