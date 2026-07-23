import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../store/settings_store.dart';
import '../../widgets/koti_switch.dart';

/// The "Music Assistant" page toggle, plus the Sendspin speaker toggle
/// that only matters once it's on — one settings destination instead of
/// two, since the speaker feature is meaningless without the Music page
/// it's controlled from. Direct HA control (independent of Music
/// Assistant) is handled by custom_components/koti automatically — see
/// koti_player_server.dart — so there's nothing to configure for that here.
class MusicAssistantSettingsPage extends StatelessWidget {
  const MusicAssistantSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();

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
              title: const Text('Use this tablet as a speaker (Sendspin)'),
              subtitle: const Text(
                  'Speaks Music Assistant\'s own built-in synchronized-audio '
                  'protocol directly — no player provider to install, no '
                  'setup in Music Assistant at all. Once enabled, the '
                  'tablet shows up in Music Assistant\'s player list '
                  'automatically.'),
              value: settings.sendspinEnabled,
              onChanged: settings.setSendspinEnabled,
            ),
          ],
        ],
      ),
    );
  }
}
