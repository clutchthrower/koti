import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../api/app_update.dart';
import '../hero/hero_room_card.dart';
import '../layout/settings_grid.dart';
import '../models/room_config.dart';
import '../store/settings_store.dart';
import '../store/state_store.dart';
import '../widgets/glass_page_route.dart';
import 'home_overview_screen.dart';
import 'settings/advanced_settings_page.dart';
import 'settings/appearance_settings_page.dart';
import 'settings/connection_settings_page.dart';
import 'settings/display_settings_page.dart';
import 'settings/rooms_settings_page.dart';
import 'settings/speaker_settings_page.dart';
import 'update_screen.dart';

/// Settings, restyled as a "room" rather than a sliding side menu: the same
/// hero background/title chrome as [RoomView], with every settings entry as
/// a card in the same grid — same tile sizes, same portrait/landscape
/// layouts. Reached by tapping the shell's menu icon, exited the same way
/// Music is (pick another destination, or swipe).
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _checkingUpdate = false;
  bool _checkedUpdateOnce = false;
  AppUpdateInfo? _availableUpdate;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsStore>(context, listen: false);
    if (settings.updateChecksEnabled) _checkForUpdate(silent: true);
  }

  Future<void> _checkForUpdate({bool silent = false}) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = !silent);
    try {
      final info = await AppUpdateChecker().check();
      if (!mounted) return;
      setState(() {
        _availableUpdate = info;
        _checkedUpdateOnce = true;
        _checkingUpdate = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _openUpdate() async {
    final info = _availableUpdate;
    if (info == null) return;
    final version = (await PackageInfo.fromPlatform()).version;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (routeContext) => UpdateScreen(
        info: info,
        currentVersion: version,
        onSkip: () => Navigator.of(routeContext).pop(),
      ),
    ));
  }

  Future<void> _renameDevice(SettingsStore settings) async {
    final controller = TextEditingController(text: settings.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Living Room Tablet',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await settings.setDeviceName(name);
    controller.dispose();
  }

  void _push(Widget page) => pushGlassSheet(context, page);

  List<SettingsEntry> _entries(SettingsStore settings) {
    return [
      SettingsEntry(
        icon: Icons.badge_outlined,
        label: 'Device Name',
        stateText: settings.deviceName,
        onTap: () => _renameDevice(settings),
      ),
      if (settings.homeRoom != null)
        SettingsEntry(
          icon: Icons.restart_alt,
          label: 'Reset Home',
          stateText: 'Tap to reset to automatic',
          onTap: () => settings.setHomeRoom(null),
        ),
      SettingsEntry(
        icon: Icons.meeting_room_outlined,
        label: 'Rooms',
        stateText: 'Add, remove, edit',
        onTap: () => _push(const RoomsSettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.brightness_6_outlined,
        label: 'Display',
        stateText: 'Brightness, screensaver',
        onTap: () => _push(const DisplaySettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.palette_outlined,
        label: 'Appearance & Theme',
        stateText: 'Glass/Base, accent color',
        onTap: () => _push(const AppearanceSettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.wifi,
        label: 'Connection',
        stateText: 'HA URL & access token',
        onTap: () => _push(const ConnectionSettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.developer_mode_outlined,
        label: 'Advanced',
        stateText: 'Debug & diagnostics',
        onTap: () => _push(const AdvancedSettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.speaker_outlined,
        label: 'Speaker',
        stateText: settings.speakerEnabled ? 'Enabled' : 'Disabled',
        active: settings.speakerEnabled,
        onTap: () => _push(const SpeakerSettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.system_update_alt,
        label: 'Auto Update Checks',
        stateText: settings.updateChecksEnabled ? 'On' : 'Off',
        active: settings.updateChecksEnabled,
        onTap: () => settings.setUpdateChecksEnabled(!settings.updateChecksEnabled),
      ),
      SettingsEntry(
        icon: Icons.bluetooth_searching,
        label: 'Bluetooth Proxy',
        stateText: settings.bluetoothProxyEnabled ? 'On' : 'Off',
        active: settings.bluetoothProxyEnabled,
        onTap: () => settings.setBluetoothProxyEnabled(!settings.bluetoothProxyEnabled),
      ),
      SettingsEntry(
        icon: Icons.library_music_outlined,
        label: 'Music Assistant',
        stateText: settings.musicAssistantEnabled ? 'On' : 'Off',
        active: settings.musicAssistantEnabled,
        onTap: () => settings.setMusicAssistantEnabled(!settings.musicAssistantEnabled),
      ),
      if (_availableUpdate != null)
        SettingsEntry(
          icon: Icons.system_update_alt,
          label: 'Update Available',
          stateText: 'Version ${_availableUpdate!.version}',
          active: true,
          onTap: _openUpdate,
        )
      else
        SettingsEntry(
          icon: Icons.system_update_alt,
          label: 'Check for Updates',
          stateText: _checkingUpdate
              ? 'Checking…'
              : _checkedUpdateOnce
                  ? 'Up to date'
                  : 'Tap to check',
          onTap: _checkingUpdate ? null : () => _checkForUpdate(),
        ),
      SettingsEntry(
        icon: Icons.logout,
        label: 'Exit',
        stateText: 'Quit Koti',
        onTap: () => SystemNavigator.pop(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final store = Provider.of<StateStore>(context, listen: false);
    final home = effectiveHomeConfig(
      rooms: settings.rooms,
      store: store,
      saved: settings.homeRoom,
    );
    // Same background as Home (falling back to the same bundled demo photo
    // Home itself would use) — Settings reads as a continuation of the
    // house, not a screen bolted on from somewhere else.
    final settingsRoom = RoomConfig(
      id: 'settings',
      name: 'Settings',
      backgroundAsset: home.backgroundAsset,
    );

    return Stack(
      children: [
        Positioned.fill(child: HeroRoomCard(room: settingsRoom)),
        Positioned.fill(child: SettingsGrid(entries: _entries(settings))),
      ],
    );
  }
}
