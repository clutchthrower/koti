import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../hero/hero_room_card.dart';
import '../layout/settings_grid.dart';
import '../models/room_config.dart';
import '../store/settings_store.dart';
import '../store/state_store.dart';
import '../widgets/glass_page_route.dart';
import 'home_overview_screen.dart';
import 'settings/app_info_settings_page.dart';
import 'settings/diagnostics_settings_page.dart';
import 'settings/display_settings_page.dart';
import 'settings/home_assistant_settings_page.dart';
import 'settings/music_assistant_settings_page.dart';

/// Settings, restyled as a "room" rather than a sliding side menu: the same
/// hero background/title chrome as [RoomView], with every settings entry as
/// a card in the same grid — same tile sizes, same portrait/landscape
/// layouts. Reached by tapping the shell's menu icon, exited the same way
/// Music is (pick another destination, or swipe).
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  void _push(BuildContext context, Widget page) =>
      pushGlassSheet(context, page);

  List<SettingsEntry> _entries(BuildContext context, SettingsStore settings) {
    return [
      SettingsEntry(
        icon: Icons.home_work_outlined,
        label: 'Home Assistant',
        stateText: settings.deviceName,
        onTap: () => _push(context, const HomeAssistantSettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.library_music_outlined,
        label: 'Music Assistant',
        stateText: settings.musicAssistantEnabled
            ? (settings.sendspinEnabled ? 'On + Sendspin' : 'On')
            : 'Off',
        active: settings.musicAssistantEnabled,
        onTap: () => _push(context, const MusicAssistantSettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.brightness_6_outlined,
        label: 'Display',
        stateText: 'Appearance, screensaver',
        onTap: () => _push(context, const DisplaySettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.developer_mode_outlined,
        label: 'Diagnostics',
        stateText: 'Network, debug, reset',
        onTap: () => _push(context, const DiagnosticsSettingsPage()),
      ),
      SettingsEntry(
        icon: Icons.info_outline,
        label: 'App Info',
        stateText: 'Version, updates, credits',
        onTap: () => _push(context, const AppInfoSettingsPage()),
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
        Positioned.fill(child: SettingsGrid(entries: _entries(context, settings))),
      ],
    );
  }
}
