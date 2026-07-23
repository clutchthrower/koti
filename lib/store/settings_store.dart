import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/room_config.dart';

enum ConnectionMode { localOnly, remoteOnly, auto }

/// Connection + room configuration, persisted locally. The access token
/// lives in the platform keychain/keystore (flutter_secure_storage) and is
/// never written to SharedPreferences or logged.
class SettingsStore extends ChangeNotifier {
  static const _secureStorage = FlutterSecureStorage();
  static const _tokenKey = 'koti_ha_access_token';

  static const _kLocalUrl = 'koti_local_url';
  static const _kRemoteUrl = 'koti_remote_url';
  static const _kConnectionMode = 'koti_connection_mode';
  static const _kReconnectSeconds = 'koti_reconnect_seconds';
  static const _kTimeoutSeconds = 'koti_timeout_seconds';
  static const _kRooms = 'koti_rooms_v1';
  static const _kHomeRoom = 'koti_home_room_v1';
  static const _kOnboarded = 'koti_onboarded';
  static const _kWeatherEntity = 'koti_weather_entity';
  static const _kDeviceId = 'koti_device_id';
  static const _kWebhookId = 'koti_ha_webhook_id';
  static const _kUpdateChecks = 'koti_update_checks';
  static const _kBleProxy = 'koti_ble_proxy';
  static const _kMusicAssistant = 'koti_music_assistant';
  static const _kDeviceName = 'koti_device_name';
  static const _kSendspinEnabled = 'koti_sendspin_enabled';

  String localUrl = '';
  String remoteUrl = '';
  String? _accessToken;
  ConnectionMode connectionMode = ConnectionMode.localOnly;
  int reconnectSeconds = 5;
  int timeoutSeconds = 15;
  bool onboarded = false;
  List<RoomConfig> rooms = [];
  String? weatherEntityId;

  /// Saved customization of the Home tab. Null means Home is derived
  /// automatically (aggregate badges + whole-home device cards).
  RoomConfig? homeRoom;

  /// Stable id identifying this tablet to HA's mobile_app integration,
  /// and the webhook id HA returned when the tablet registered itself as
  /// a device (null until registration succeeds).
  String deviceId = '';
  String? haWebhookId;

  /// User-facing device name — used for the Bluetooth proxy's mDNS
  /// identity and the Koti player's own discovery advertisement, so two
  /// tablets on the same network don't collide under a shared hardcoded
  /// name. Defaults to something already-unique (derived from [deviceId])
  /// so it works without the user having to set it, but they can rename it
  /// (e.g. "Living Room Tablet") in Settings.
  String _deviceName = '';
  String get deviceName =>
      _deviceName.isNotEmpty ? _deviceName : 'Koti Tablet ($_shortId)';
  String get _shortId => deviceId.length >= 6 ? deviceId.substring(0, 6) : deviceId;

  /// Feature switches: automatic update checks (GitHub releases), the
  /// ESPHome-style Bluetooth proxy, and the full-page Music Assistant
  /// control screen (off by default — most users don't run MA).
  bool updateChecksEnabled = true;
  bool bluetoothProxyEnabled = false;
  bool musicAssistantEnabled = false;

  /// Speaks the Sendspin protocol directly — Music Assistant's own
  /// built-in player support, no custom provider/add-on install needed on
  /// the MA side at all.
  bool sendspinEnabled = false;

  String? get accessToken => _accessToken;

  /// Resolves the URL to actually connect to given the current mode.
  /// `auto` always prefers local; the SSID/IP-based switching described in
  /// the spec is a future enhancement once network info plumbing is added.
  String get activeUrl {
    switch (connectionMode) {
      case ConnectionMode.remoteOnly:
        return remoteUrl;
      case ConnectionMode.localOnly:
      case ConnectionMode.auto:
        return localUrl;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    localUrl = prefs.getString(_kLocalUrl) ?? '';
    remoteUrl = prefs.getString(_kRemoteUrl) ?? '';
    connectionMode = ConnectionMode.values.firstWhere(
      (m) => m.name == prefs.getString(_kConnectionMode),
      orElse: () => ConnectionMode.localOnly,
    );
    reconnectSeconds = prefs.getInt(_kReconnectSeconds) ?? 5;
    timeoutSeconds = prefs.getInt(_kTimeoutSeconds) ?? 15;
    onboarded = prefs.getBool(_kOnboarded) ?? false;
    weatherEntityId = prefs.getString(_kWeatherEntity);
    _accessToken = await _secureStorage.read(key: _tokenKey);

    final roomsRaw = prefs.getString(_kRooms);
    if (roomsRaw != null) {
      final list = jsonDecode(roomsRaw) as List;
      rooms = list
          .map((r) => RoomConfig.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    }
    final homeRaw = prefs.getString(_kHomeRoom);
    if (homeRaw != null) {
      homeRoom = RoomConfig.fromJson(
          (jsonDecode(homeRaw) as Map).cast<String, dynamic>());
    }

    // A stable per-install device id, minted once.
    deviceId = prefs.getString(_kDeviceId) ?? '';
    if (deviceId.isEmpty) {
      final rng = Random.secure();
      deviceId = List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_kDeviceId, deviceId);
    }
    haWebhookId = prefs.getString(_kWebhookId);
    _deviceName = prefs.getString(_kDeviceName) ?? '';
    updateChecksEnabled = prefs.getBool(_kUpdateChecks) ?? true;
    bluetoothProxyEnabled = prefs.getBool(_kBleProxy) ?? false;
    musicAssistantEnabled = prefs.getBool(_kMusicAssistant) ?? false;
    sendspinEnabled = prefs.getBool(_kSendspinEnabled) ?? false;
    notifyListeners();
  }

  Future<void> setDeviceName(String v) async {
    _deviceName = v.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_deviceName.isEmpty) {
      await prefs.remove(_kDeviceName);
    } else {
      await prefs.setString(_kDeviceName, _deviceName);
    }
    notifyListeners();
  }

  Future<void> setUpdateChecksEnabled(bool v) async {
    updateChecksEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUpdateChecks, v);
    notifyListeners();
  }

  Future<void> setBluetoothProxyEnabled(bool v) async {
    bluetoothProxyEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBleProxy, v);
    notifyListeners();
  }

  Future<void> setMusicAssistantEnabled(bool v) async {
    musicAssistantEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMusicAssistant, v);
    notifyListeners();
  }

  Future<void> setSendspinEnabled(bool v) async {
    sendspinEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSendspinEnabled, v);
    notifyListeners();
  }

  Future<void> setHaWebhookId(String? id) async {
    haWebhookId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kWebhookId);
    } else {
      await prefs.setString(_kWebhookId, id);
    }
    notifyListeners();
  }

  Future<void> setConnection({
    required String localUrl,
    String? remoteUrl,
    required String accessToken,
    ConnectionMode? mode,
  }) async {
    this.localUrl = localUrl;
    this.remoteUrl = remoteUrl ?? this.remoteUrl;
    _accessToken = accessToken;
    if (mode != null) connectionMode = mode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocalUrl, this.localUrl);
    await prefs.setString(_kRemoteUrl, this.remoteUrl);
    await prefs.setString(_kConnectionMode, connectionMode.name);
    await _secureStorage.write(key: _tokenKey, value: accessToken);
    notifyListeners();
  }

  Future<void> setReconnectSeconds(int seconds) async {
    reconnectSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kReconnectSeconds, seconds);
    notifyListeners();
  }

  Future<void> setTimeoutSeconds(int seconds) async {
    timeoutSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTimeoutSeconds, seconds);
    notifyListeners();
  }

  Future<void> setRooms(List<RoomConfig> newRooms) async {
    rooms = newRooms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kRooms, jsonEncode(newRooms.map((r) => r.toJson()).toList()));
    notifyListeners();
  }

  Future<void> setHomeRoom(RoomConfig? config) async {
    homeRoom = config;
    final prefs = await SharedPreferences.getInstance();
    if (config == null) {
      await prefs.remove(_kHomeRoom);
    } else {
      await prefs.setString(_kHomeRoom, jsonEncode(config.toJson()));
    }
    notifyListeners();
  }

  Future<void> setWeatherEntityId(String? id) async {
    weatherEntityId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kWeatherEntity);
    } else {
      await prefs.setString(_kWeatherEntity, id);
    }
    notifyListeners();
  }

  Future<void> markOnboarded() async {
    onboarded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _secureStorage.delete(key: _tokenKey);
    localUrl = '';
    remoteUrl = '';
    _accessToken = null;
    connectionMode = ConnectionMode.localOnly;
    reconnectSeconds = 5;
    timeoutSeconds = 15;
    onboarded = false;
    rooms = [];
    homeRoom = null;
    weatherEntityId = null;
    haWebhookId = null;
    notifyListeners();
  }

  bool get hasCredentials => localUrl.isNotEmpty && (_accessToken?.isNotEmpty ?? false);
}
