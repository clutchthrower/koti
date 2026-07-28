import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../store/settings_store.dart';
import '../../widgets/glass_page_route.dart';
import '../../widgets/koti_switch.dart';
import 'connection_settings_page.dart';
import 'rooms_settings_page.dart';

/// Everything about *this Home Assistant instance and this tablet's
/// identity to it*: device name, the Bluetooth proxy feature, Rooms, and
/// the actual connection (URL/token/mode) — as opposed to Diagnostics'
/// live network-tuning tools, or Display's on-device appearance settings.
class HomeAssistantSettingsPage extends StatelessWidget {
  const HomeAssistantSettingsPage({super.key});

  Future<void> _renameDevice(BuildContext context, SettingsStore settings) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RenameDeviceSheet(initialName: settings.deviceName),
    );
    if (name != null && name.isNotEmpty) await settings.setDeviceName(name);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('Home Assistant')),
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
          KotiSwitchListTile(
            secondary: const Icon(Icons.bluetooth_searching),
            title: const Text('Bluetooth Proxy'),
            subtitle: const Text(
                'Relays nearby Bluetooth devices (sensors, beacons) to Home Assistant — '
                'no extra setup needed, it registers under this tablet\'s own device.'),
            value: settings.bluetoothProxyEnabled,
            onChanged: settings.setBluetoothProxyEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.meeting_room_outlined),
            title: const Text('Rooms'),
            subtitle: const Text('Add, remove, and edit rooms'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => pushGlassSheet(context, const RoomsSettingsPage()),
          ),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('Connection'),
            subtitle: const Text('Home Assistant URL and access token'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => pushGlassSheet(context, const ConnectionSettingsPage()),
          ),
        ],
      ),
    );
  }
}

/// A `TextEditingController` created in a function and disposed right after
/// `showModalBottomSheet`'s Future resolves looks safe but isn't: the sheet
/// is still playing its close animation (not yet unmounted) when that
/// `Future` completes, so disposing the controller then rips it out from
/// under a still-live `TextField` and corrupts the element tree — the actual
/// cause of a `_dependents.isEmpty`/`defunct` assertion crash reproduced
/// live on Save (and even on a no-op Cancel) regardless of whether the
/// picker was a `AlertDialog`, a bottom sheet, or reached via a plain
/// `MaterialPageRoute` vs `pushGlassSheet` — all of those variations shared
/// this same bug. Owning the controller in the sheet's own State and
/// disposing it from its own `dispose()` ties its lifetime to the widget's
/// real unmount, which is the only thing that actually fixes it.
class _RenameDeviceSheet extends StatefulWidget {
  final String initialName;
  const _RenameDeviceSheet({required this.initialName});

  @override
  State<_RenameDeviceSheet> createState() => _RenameDeviceSheetState();
}

class _RenameDeviceSheetState extends State<_RenameDeviceSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device Name', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Living Room Tablet',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
                  child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
