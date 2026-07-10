import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../store/settings_store.dart';
import 'advanced_settings_page.dart';
import 'appearance_settings_page.dart';
import 'connection_settings_page.dart';
import 'display_settings_page.dart';
import 'rooms_settings_page.dart';
import 'speaker_settings_page.dart';

/// Full settings hub. The sidebar links to the common pages directly, but
/// everything must also be reachable from here — this is the only settings
/// entry point on screens without the drawer (e.g. the no-rooms prompt).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _renameDevice(BuildContext context, SettingsStore settings) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Device Name'),
            subtitle: Text(
                '${settings.deviceName} — identifies this tablet to Home Assistant '
                '(Bluetooth proxy, speaker). Change it if you have more than one.'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _renameDevice(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('Connection'),
            subtitle: const Text('Home Assistant URL and access token'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ConnectionSettingsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.meeting_room_outlined),
            title: const Text('Rooms'),
            subtitle: const Text('Add, remove, and edit rooms'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RoomsSettingsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Display'),
            subtitle: const Text('Brightness, light/dark, screensaver'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const DisplaySettingsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance & Theme'),
            subtitle: const Text('Glass/Base variant, accent color, animations'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AppearanceSettingsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.developer_mode_outlined),
            title: const Text('Advanced / Developer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AdvancedSettingsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.speaker_outlined),
            title: const Text('Speaker'),
            subtitle: Text(settings.speakerEnabled ? 'Enabled' : 'Use this tablet as a speaker'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SpeakerSettingsPage())),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Features',
                style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.system_update_alt),
            title: const Text('Automatic Update Checks'),
            subtitle: const Text(
                'Checks GitHub for new releases and shows an update screen when one is available'),
            value: settings.updateChecksEnabled,
            onChanged: settings.setUpdateChecksEnabled,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bluetooth_searching),
            title: const Text('Bluetooth Proxy'),
            subtitle: Text(
                'Relays nearby Bluetooth devices (sensors, beacons) to Home Assistant, '
                'like an ESPHome Bluetooth proxy. HA will discover "${settings.deviceName}" '
                'under Devices & services — add it there.'),
            value: settings.bluetoothProxyEnabled,
            onChanged: settings.setBluetoothProxyEnabled,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.library_music_outlined),
            title: const Text('Music Assistant'),
            subtitle: const Text(
                'Adds a swipeable Music page (left of Home): player/group '
                'selection, search, library browsing, queue, and artwork.'),
            value: settings.musicAssistantEnabled,
            onChanged: settings.setMusicAssistantEnabled,
          ),
        ],
      ),
    );
  }
}
