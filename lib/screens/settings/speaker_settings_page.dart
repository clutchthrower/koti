import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../speaker/koti_player_server.dart';
import '../../store/settings_store.dart';
import '../../widgets/entity_picker.dart';

/// Settings for "tablet as a speaker": enable the local Koti player server
/// (which speaks the Fully Kiosk Browser REST protocol — see
/// koti_player_server.dart for why) and show the host/port to add it in
/// Music Assistant's built-in "Fully Kiosk Browser" player provider.
/// Also lets the user confirm which resulting HA entity is this device (so
/// the Music page can default to it) once this app's own Koti Home
/// Assistant integration has auto-discovered it — that part alone stays
/// zero-config; it's only the Music Assistant side that needs manual entry
/// until a real "Koti" MA provider exists upstream.
class SpeakerSettingsPage extends StatefulWidget {
  const SpeakerSettingsPage({super.key});

  @override
  State<SpeakerSettingsPage> createState() => _SpeakerSettingsPageState();
}

class _SpeakerSettingsPageState extends State<SpeakerSettingsPage> {
  String? _localIp;

  @override
  void initState() {
    super.initState();
    _lookupIp();
  }

  Future<void> _lookupIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            if (mounted) setState(() => _localIp = addr.address);
            return;
          }
        }
      }
    } catch (_) {
      // IP lookup is a convenience for copy/paste — the switch still works.
    }
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final port = KotiPlayerServer.defaultPort.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Speaker')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Use this tablet as a speaker'),
            subtitle: Text('Runs a local server on "${settings.deviceName}" that '
                'Music Assistant\'s built-in "Fully Kiosk Browser" player '
                'provider can control directly.'),
            value: settings.speakerEnabled,
            onChanged: settings.setSpeakerEnabled,
          ),
          if (settings.speakerEnabled) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('In Music Assistant',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                'Settings → Player Providers → add "Fully Kiosk Browser", then '
                'add a player with the host/port below. The password field can '
                'be anything — this tablet doesn\'t check it.',
              ),
            ),
            _CopyRow(
              label: 'Host',
              value: _localIp ?? 'Looking up…',
              onCopy: _localIp == null ? null : () => _copy(_localIp!, 'Host'),
            ),
            _CopyRow(label: 'Port', value: port, onCopy: () => _copy(port, 'Port')),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('In Home Assistant (optional)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 20),
              child: Text(
                'Separately, this tablet also advertises itself to Home '
                'Assistant with no setup — install the Koti integration (not '
                'on HACS yet — copy custom_components/koti from the Koti '
                'GitHub repo into your HA config and restart) and it\'ll show '
                'up as a device with volume/playback control. This is '
                'independent of the Music Assistant setup above.',
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('Which entity is this tablet?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                'Once added in Music Assistant, pick the resulting entity '
                'below so the Music page defaults to controlling this tablet.',
              ),
            ),
            EntityPickerField(
              label: 'This tablet\'s speaker entity',
              value: settings.selfSpeakerEntityId,
              domains: const ['media_player'],
              onChanged: settings.setSelfSpeakerEntityId,
            ),
          ],
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _CopyRow({required this.label, required this.value, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: TextStyle(color: Theme.of(context).hintColor)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
