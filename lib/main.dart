import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'api/app_update.dart';
import 'api/ble_proxy.dart';
import 'api/ha_device_registration.dart';
import 'api/ha_registry.dart';
import 'api/ha_rest_client.dart';
import 'api/ha_websocket_client.dart';
import 'screens/koti_splash_screen.dart';
import 'screens/update_screen.dart';
import 'store/helper_store.dart';
import 'store/settings_store.dart';
import 'store/state_store.dart';
import 'theme/koti_theme.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/settings/rooms_settings_page.dart';
import 'screens/settings/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Wall-dashboard look: hide Android's status/navigation bars (swipe from
  // an edge temporarily brings them back).
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // .env is dev-only convenience: onboarding screens offer a one-tap "fill
  // from .env" shortcut, but nothing auto-connects with it — the real
  // Discovery -> Sign In flow (spec 1.5) is always what runs on first
  // launch, so it stays exercisable even with a .env present.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env is optional — absent in a clean checkout.
  }

  final settings = SettingsStore();
  await settings.load();

  runApp(KotiApp(settings: settings));
}

class KotiApp extends StatefulWidget {
  final SettingsStore settings;
  const KotiApp({super.key, required this.settings});

  @override
  State<KotiApp> createState() => _KotiAppState();
}

class _KotiAppState extends State<KotiApp> with WidgetsBindingObserver {
  StateStore? _stateStore;
  HelperStore? _helperStore;
  final ThemeController _themeController = ThemeController();
  bool _ready = false;
  bool _splashDone = false;
  String? _connectedUrl;
  String? _connectedToken;

  AppUpdateInfo? _pendingUpdate;
  String _currentVersion = '';
  Timer? _updateTimer;

  final BleProxy _bleProxy = BleProxy();
  bool _bleProxySyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettingsChanged);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from another app/dialog can leave the system bars stuck
    // visible — re-hide them.
    if (state == AppLifecycleState.resumed) {
      _themeController.reassertFullscreen();
    }
  }

  void _onSettingsChanged() {
    final changed = widget.settings.activeUrl != _connectedUrl ||
        widget.settings.accessToken != _connectedToken;
    if (changed) _connect();
    unawaited(_syncBleProxy());
  }

  /// Starts/stops the Bluetooth proxy to match the setting. If starting
  /// fails (permission pending, Bluetooth off) the toggle flips back so
  /// the switch never lies about what's running.
  Future<void> _syncBleProxy() async {
    if (_bleProxySyncing) return;
    _bleProxySyncing = true;
    try {
      final want = widget.settings.bluetoothProxyEnabled;
      if (want && !_bleProxy.running) {
        final status = await _bleProxy.start(deviceId: widget.settings.deviceId);
        if (status != 'ok') {
          await widget.settings.setBluetoothProxyEnabled(false);
        }
      } else if (!want && _bleProxy.running) {
        await _bleProxy.stop();
      }
    } finally {
      _bleProxySyncing = false;
    }
  }

  Future<void> _init() async {
    await _themeController.load();
    await _connect();
    setState(() => _ready = true);
    // Update check: on launch, then every 6 hours. Never blocks startup —
    // the screen only appears once a newer release is actually confirmed.
    unawaited(_checkForUpdate());
    _updateTimer = Timer.periodic(
        const Duration(hours: 6), (_) => unawaited(_checkForUpdate()));
    unawaited(_syncBleProxy());
  }

  Future<void> _checkForUpdate() async {
    if (!widget.settings.updateChecksEnabled) return;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      final info = await AppUpdateChecker().check(currentVersion: _currentVersion);
      if (info != null && mounted) setState(() => _pendingUpdate = info);
    } catch (_) {
      // Offline or GitHub unreachable — try again next cycle.
    }
  }

  Future<void> _connect() async {
    _stateStore?.dispose();
    _helperStore?.dispose();
    _stateStore = null;
    _helperStore = null;

    if (widget.settings.hasCredentials) {
      final url = widget.settings.activeUrl;
      final token = widget.settings.accessToken!;
      final rest = HaRestClient(baseUrl: url, token: token);
      final ws = HaWebSocketClient(
        baseUrl: url,
        token: token,
        reconnectInterval: Duration(seconds: widget.settings.reconnectSeconds),
        requestTimeout: Duration(seconds: widget.settings.timeoutSeconds),
      );
      final stateStore = StateStore(ws: ws, rest: rest);
      await stateStore.init();
      final helperStore = HelperStore(stateStore: stateStore);
      await helperStore.init();
      _stateStore = stateStore;
      _helperStore = helperStore;
      _connectedUrl = url;
      _connectedToken = token;
      // One-time: register this tablet as a device in HA (Settings →
      // Devices & services → "Hemma Tablet"). Silent best-effort — the
      // dashboard works fine without it.
      if (widget.settings.haWebhookId == null) {
        unawaited(_registerDevice(url, token));
      }
    } else {
      _connectedUrl = null;
      _connectedToken = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _registerDevice(String url, String token) async {
    try {
      final webhookId = await HaDeviceRegistration.register(
        baseUrl: url,
        accessToken: token,
        deviceId: widget.settings.deviceId,
      );
      if (webhookId != null) await widget.settings.setHaWebhookId(webhookId);
    } catch (_) {
      // Registration is optional; retried on next launch.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onSettingsChanged);
    _updateTimer?.cancel();
    unawaited(_bleProxy.stop());
    _stateStore?.dispose();
    _helperStore?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || !_splashDone) {
      // Animated splash (house draws itself → tumbles → settles into the
      // wordmark) doubles as the loading screen: it plays while we connect
      // and holds its final frame if HA is slower than the animation. The
      // native launch background is the same tan, so the hand-off from
      // Android is seamless.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: KotiSplashScreen(
          ready: _ready,
          onFinished: () => setState(() => _splashDone = true),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider.value(value: _themeController),
        if (_stateStore != null) ChangeNotifierProvider.value(value: _stateStore!),
        if (_helperStore != null) ChangeNotifierProvider.value(value: _helperStore!),
      ],
      child: Builder(
        builder: (context) {
          // Watched (not just read) so the root screen swaps the moment
          // rooms appear — e.g. right after onboarding auto-provisions them.
          final settings = context.watch<SettingsStore>();
          final tokens = context.watch<ThemeController>().tokensFor(context);
          // Deliberately NOT colorSchemeSeed: seeding Material3 from the
          // accent color tints every AppBar/ListTile/Scaffold with it. The
          // original dashboard is calm neutral tones with the accent used
          // sparingly (active icons, buttons) — build the scheme by hand so
          // surfaces stay neutral and only small elements pick up accent.
          final baseScheme = tokens.isDark ? const ColorScheme.dark() : const ColorScheme.light();
          final colorScheme = baseScheme.copyWith(
            primary: tokens.accentColor,
            onPrimary: Colors.white,
            secondary: tokens.accentColor,
            // Warm brown-charcoal / warm off-white instead of a cold
            // near-black / near-white — harmonizes with the tan splash and
            // brand color instead of reading as a generic dark UI.
            surface: tokens.isDark ? const Color(0xFF211D18) : const Color(0xFFF6F2EC),
            onSurface: tokens.isDark ? Colors.white : const Color(0xFF241F19),
          );

          return KotiTheme(
            tokens: tokens,
            child: MaterialApp(
              title: 'Koti',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'Hanken Grotesk',
                useMaterial3: true,
                colorScheme: colorScheme,
                scaffoldBackgroundColor: colorScheme.surface,
                appBarTheme: AppBarTheme(
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.onSurface,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                ),
              ),
              home: _pendingUpdate != null
                  ? UpdateScreen(
                      info: _pendingUpdate!,
                      currentVersion: _currentVersion,
                      onSkip: () => setState(() => _pendingUpdate = null),
                    )
                  : _stateStore == null
                      ? const OnboardingScreen()
                      : (settings.rooms.isEmpty
                          ? const _EmptyRoomsPrompt()
                          : AppShell(settings: settings)),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyRoomsPrompt extends StatefulWidget {
  const _EmptyRoomsPrompt();

  @override
  State<_EmptyRoomsPrompt> createState() => _EmptyRoomsPromptState();
}

class _EmptyRoomsPromptState extends State<_EmptyRoomsPrompt> {
  bool _busy = false;
  String? _message;

  Future<void> _autoProvision() async {
    final settings = Provider.of<SettingsStore>(context, listen: false);
    if (!settings.hasCredentials) {
      setState(() => _message = 'Not connected to Home Assistant yet.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await RoomAutoProvisioner(
        baseUrl: settings.activeUrl,
        accessToken: settings.accessToken!,
      ).provision();
      if (result.weatherEntityId != null) {
        await settings.setWeatherEntityId(result.weatherEntityId);
      }
      if (result.rooms.isNotEmpty) {
        // Root watches SettingsStore, so this swaps straight into the app.
        await settings.setRooms(result.rooms);
      } else if (!result.adminAccess) {
        setState(() => _message =
            'This account can\'t read Areas — add rooms manually below.');
      } else {
        setState(() => _message =
            'No Areas found in Home Assistant — add rooms manually below.');
      }
    } catch (e) {
      setState(() => _message = 'Auto-setup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Koti')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No rooms configured yet.', style: TextStyle(fontSize: 18)),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(_busy ? 'Setting up…' : 'Set Up Rooms from Home Assistant'),
                onPressed: _busy ? null : _autoProvision,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const RoomsSettingsPage())),
                child: const Text('Add Rooms Manually'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                child: const Text('Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
