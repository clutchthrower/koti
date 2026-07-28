import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koti/models/room_config.dart';
import 'package:koti/store/settings_store.dart';

/// `flutter_secure_storage` talks to a real platform keychain/keystore over
/// this channel — nothing implements it under `flutter test`, so every test
/// that touches `SettingsStore.load()`/`setConnection()`/`resetToDefaults()`
/// (all of which read/write the access token) needs a fake backing it, or
/// they'd hang/throw on the missing platform implementation.
Map<String, String> _installFakeSecureStorage() {
  final backing = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>();
      switch (call.method) {
        case 'read':
          return backing[args!['key']];
        case 'write':
          backing[args!['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          backing.remove(args!['key']);
          return null;
        case 'deleteAll':
          backing.clear();
          return null;
        case 'containsKey':
          return backing.containsKey(args!['key']);
        case 'readAll':
          return backing;
        default:
          return null;
      }
    },
  );
  return backing;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secureBacking;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureBacking = _installFakeSecureStorage();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('load() defaults on a fresh install', () {
    test('mints and persists a deviceId exactly once', () async {
      final store = SettingsStore();
      await store.load();
      expect(store.deviceId, hasLength(32));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('koti_device_id'), store.deviceId);

      // A second load (e.g. app restart) must reuse the same id rather
      // than minting a fresh one, or every restart would register as a
      // new device in Home Assistant/Music Assistant.
      final second = SettingsStore();
      await second.load();
      expect(second.deviceId, store.deviceId);
    });

    test('other fields fall back to their documented defaults', () async {
      final store = SettingsStore();
      await store.load();

      expect(store.localUrl, '');
      expect(store.remoteUrl, '');
      expect(store.connectionMode, ConnectionMode.localOnly);
      expect(store.reconnectSeconds, 5);
      expect(store.timeoutSeconds, 15);
      expect(store.onboarded, isFalse);
      expect(store.rooms, isEmpty);
      expect(store.homeRoom, isNull);
      expect(store.weatherEntityId, isNull);
      expect(store.accessToken, isNull);
      expect(store.updateChecksEnabled, isTrue);
      expect(store.bluetoothProxyEnabled, isFalse);
      expect(store.musicAssistantEnabled, isFalse);
      expect(store.sendspinEnabled, isFalse);
      expect(store.hasCredentials, isFalse);
    });

    test('deviceName falls back to "Koti Tablet (<first 6 of deviceId>)"', () async {
      final store = SettingsStore();
      await store.load();
      expect(store.deviceName, 'Koti Tablet (${store.deviceId.substring(0, 6)})');
    });
  });

  group('activeUrl', () {
    test('resolves per connection mode', () async {
      final store = SettingsStore();
      await store.load();
      await store.setConnection(
        localUrl: 'http://local',
        remoteUrl: 'http://remote',
        accessToken: 'tok',
        mode: ConnectionMode.localOnly,
      );
      expect(store.activeUrl, 'http://local');

      await store.setConnection(
        localUrl: 'http://local',
        remoteUrl: 'http://remote',
        accessToken: 'tok',
        mode: ConnectionMode.remoteOnly,
      );
      expect(store.activeUrl, 'http://remote');

      await store.setConnection(
        localUrl: 'http://local',
        remoteUrl: 'http://remote',
        accessToken: 'tok',
        mode: ConnectionMode.auto,
      );
      expect(store.activeUrl, 'http://local');
    });
  });

  group('setters round-trip through a fresh load()', () {
    test('setConnection persists URLs, mode, and the token in secure storage', () async {
      final store = SettingsStore();
      await store.load();
      await store.setConnection(
        localUrl: 'http://192.168.1.5:8123',
        remoteUrl: 'https://example.duckdns.org',
        accessToken: 'super-secret-token',
        mode: ConnectionMode.remoteOnly,
      );
      expect(store.hasCredentials, isTrue);
      expect(secureBacking['koti_ha_access_token'], 'super-secret-token');

      final reloaded = SettingsStore();
      await reloaded.load();
      expect(reloaded.localUrl, 'http://192.168.1.5:8123');
      expect(reloaded.remoteUrl, 'https://example.duckdns.org');
      expect(reloaded.connectionMode, ConnectionMode.remoteOnly);
      expect(reloaded.accessToken, 'super-secret-token');
    });

    test('setRooms and setHomeRoom persist and reload full RoomConfig objects', () async {
      final store = SettingsStore();
      await store.load();
      final room = RoomConfig(
        id: 'living_room',
        name: 'Living Room',
        lightEntities: const ['light.lamp'],
      );
      await store.setRooms([room]);
      await store.setHomeRoom(room);

      final reloaded = SettingsStore();
      await reloaded.load();
      expect(reloaded.rooms, hasLength(1));
      expect(reloaded.rooms.single.id, 'living_room');
      expect(reloaded.homeRoom?.id, 'living_room');
    });

    test('setHomeRoom(null) clears the persisted home room', () async {
      final store = SettingsStore();
      await store.load();
      await store.setHomeRoom(RoomConfig(id: 'x', name: 'X'));
      await store.setHomeRoom(null);

      final reloaded = SettingsStore();
      await reloaded.load();
      expect(reloaded.homeRoom, isNull);
    });

    test('markOnboarded persists true', () async {
      final store = SettingsStore();
      await store.load();
      await store.markOnboarded();

      final reloaded = SettingsStore();
      await reloaded.load();
      expect(reloaded.onboarded, isTrue);
    });

    test('feature toggles and device identity setters all persist', () async {
      final store = SettingsStore();
      await store.load();
      await store.setDeviceName('Living Room Tablet');
      await store.setUpdateChecksEnabled(false);
      await store.setBluetoothProxyEnabled(true);
      await store.setMusicAssistantEnabled(true);
      await store.setSendspinEnabled(true);
      await store.setReconnectSeconds(10);
      await store.setTimeoutSeconds(30);
      await store.setWeatherEntityId('weather.home');

      final reloaded = SettingsStore();
      await reloaded.load();
      expect(reloaded.deviceName, 'Living Room Tablet');
      expect(reloaded.updateChecksEnabled, isFalse);
      expect(reloaded.bluetoothProxyEnabled, isTrue);
      expect(reloaded.musicAssistantEnabled, isTrue);
      expect(reloaded.sendspinEnabled, isTrue);
      expect(reloaded.reconnectSeconds, 10);
      expect(reloaded.timeoutSeconds, 30);
      expect(reloaded.weatherEntityId, 'weather.home');
    });

    test('setDeviceName("") clears back to the derived default', () async {
      final store = SettingsStore();
      await store.load();
      await store.setDeviceName('Custom Name');
      await store.setDeviceName('  ');

      final reloaded = SettingsStore();
      await reloaded.load();
      expect(reloaded.deviceName, 'Koti Tablet (${reloaded.deviceId.substring(0, 6)})');
    });
  });

  group('resetToDefaults', () {
    test('clears prefs, the secure-storage token, and in-memory fields', () async {
      final store = SettingsStore();
      await store.load();
      await store.setConnection(
        localUrl: 'http://local',
        accessToken: 'tok',
      );
      await store.markOnboarded();

      await store.resetToDefaults();

      expect(store.localUrl, '');
      expect(store.remoteUrl, '');
      expect(store.accessToken, isNull);
      expect(store.connectionMode, ConnectionMode.localOnly);
      expect(store.onboarded, isFalse);
      expect(store.rooms, isEmpty);
      expect(store.homeRoom, isNull);
      expect(store.hasCredentials, isFalse);
      expect(secureBacking.containsKey('koti_ha_access_token'), isFalse);
    });
  });
}
