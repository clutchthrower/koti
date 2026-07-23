import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../speaker/koti_player_server.dart';
import '../../store/settings_store.dart';
import '../../store/state_store.dart';
import '../../widgets/entity_picker.dart';
import '../../widgets/koti_switch.dart';
import '../music/music_players_popup.dart' show availablePlayerIds, dedupedPlayerIds;

/// Combines the "Music Assistant" page toggle with the "tablet as a
/// speaker" setup that only matters once it's on — one settings
/// destination instead of two, since the speaker feature is meaningless
/// without the Music page it's controlled from.
class MusicAssistantSettingsPage extends StatefulWidget {
  const MusicAssistantSettingsPage({super.key});

  @override
  State<MusicAssistantSettingsPage> createState() => _MusicAssistantSettingsPageState();
}

class _MusicAssistantSettingsPageState extends State<MusicAssistantSettingsPage> {
  String? _localIp;
  Future<Set<String>>? _hiddenSpeakerIds;

  @override
  void initState() {
    super.initState();
    _lookupIp();
  }

  // Same duplicate-hiding Music Assistant mirroring produces in the Music
  // tab's own player popup (see dedupedPlayerIds) — this picker is a
  // separate widget with its own candidate list, so without this it showed
  // every raw media_player duplicate MA mirrors alongside a device's native
  // entity.
  Future<Set<String>> _computeHiddenSpeakerIds(StateStore store) async {
    final all = availablePlayerIds(store);
    final deduped = await dedupedPlayerIds(store, all);
    return all.toSet().difference(deduped.toSet());
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
    final stateStore = Provider.of<StateStore>(context, listen: false);
    _hiddenSpeakerIds ??= _computeHiddenSpeakerIds(stateStore);

    return Scaffold(
      appBar: AppBar(title: const Text('Music Assistant')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          KotiSwitchListTile(
            title: const Text('Music Assistant'),
            subtitle: const Text(
                'Adds a swipeable Music page (left of Home): player/group '
                'selection, search, library browsing, queue, and artwork.'),
            value: settings.musicAssistantEnabled,
            onChanged: settings.setMusicAssistantEnabled,
          ),
          if (settings.musicAssistantEnabled) ...[
            const Divider(height: 32),
            KotiSwitchListTile(
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
              FutureBuilder<Set<String>>(
                future: _hiddenSpeakerIds,
                builder: (context, snapshot) => EntityPickerField(
                  label: 'This tablet\'s speaker entity',
                  value: settings.selfSpeakerEntityId,
                  domains: const ['media_player'],
                  excludeUnavailable: true,
                  excludeIds: snapshot.data,
                  onChanged: settings.setSelfSpeakerEntityId,
                ),
              ),
            ],
            const Divider(height: 32),
            KotiSwitchListTile(
              title: const Text('Use Sendspin (experimental)'),
              subtitle: const Text(
                  'Speaks Music Assistant\'s own built-in synchronized-audio '
                  'protocol directly — no player provider to install, no '
                  'setup in Music Assistant at all. An alternative to the '
                  'Fully Kiosk Browser speaker above, not a replacement for '
                  'it yet; safe to try alongside it.'),
              value: settings.sendspinEnabled,
              onChanged: settings.setSendspinEnabled,
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
