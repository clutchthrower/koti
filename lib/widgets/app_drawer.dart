import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../api/app_update.dart';
import '../models/room_config.dart';
import '../screens/home_overview_screen.dart';
import '../screens/update_screen.dart';
import '../store/settings_store.dart';
import '../store/state_store.dart';
import '../theme/hemma_theme.dart';
import '../screens/settings/connection_settings_page.dart';
import '../screens/settings/display_settings_page.dart';
import '../screens/settings/room_edit_page.dart';
import '../screens/settings/rooms_settings_page.dart';
import '../screens/settings/settings_screen.dart';

/// Sidebar menu. Styled like the app's own popups (same dark panel, same
/// radius, no Material list chrome) so it reads as part of the dashboard
/// rather than a system surface layered on top.
class AppDrawer extends StatelessWidget {
  final RoomConfig? currentRoom;
  const AppDrawer({super.key, this.currentRoom});

  Future<void> _editRoom(BuildContext context, SettingsStore settings) async {
    Navigator.of(context).pop();
    final updated = await Navigator.of(context).push<RoomConfig>(
      MaterialPageRoute(builder: (_) => RoomEditPage(existing: currentRoom)),
    );
    if (updated != null) {
      final rooms = List.of(settings.rooms);
      final i = rooms.indexWhere((r) => r.id == currentRoom!.id);
      if (i != -1) {
        rooms[i] = updated;
        await settings.setRooms(rooms);
      }
    }
  }

  Future<void> _editHome(BuildContext context, SettingsStore settings) async {
    Navigator.of(context).pop();
    final store = Provider.of<StateStore>(context, listen: false);
    // Seed the editor with whatever Home currently shows — the saved
    // layout, or today's auto-derived one.
    final current = effectiveHomeConfig(
      rooms: settings.rooms,
      store: store,
      saved: settings.homeRoom,
    );
    final updated = await Navigator.of(context).push<RoomConfig>(
      MaterialPageRoute(builder: (_) => RoomEditPage(existing: current)),
    );
    if (updated != null) await settings.setHomeRoom(updated);
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HemmaTheme.of(context);
    final settings = Provider.of<SettingsStore>(context, listen: false);

    return Drawer(
      width: 270,
      elevation: 0,
      backgroundColor: tokens.dialogBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
              child: Text(
                'Koti',
                style: TextStyle(
                  fontFamily: 'Hanken Grotesk',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (currentRoom != null)
                    _DrawerItem(
                      icon: Icons.edit_outlined,
                      label: 'Edit ${currentRoom!.name}',
                      onTap: () => _editRoom(context, settings),
                    )
                  else ...[
                    _DrawerItem(
                      icon: Icons.edit_outlined,
                      label: 'Edit Home',
                      onTap: () => _editHome(context, settings),
                    ),
                    if (settings.homeRoom != null)
                      _DrawerItem(
                        icon: Icons.restart_alt,
                        label: 'Reset Home to Automatic',
                        onTap: () async {
                          Navigator.of(context).pop();
                          await settings.setHomeRoom(null);
                        },
                      ),
                  ],
                  const _DrawerDivider(),
                  _DrawerItem(
                    icon: Icons.meeting_room_outlined,
                    label: 'Rooms',
                    onTap: () => _push(context, const RoomsSettingsPage()),
                  ),
                  _DrawerItem(
                    icon: Icons.brightness_6_outlined,
                    label: 'Display',
                    onTap: () => _push(context, const DisplaySettingsPage()),
                  ),
                  _DrawerItem(
                    icon: Icons.wifi,
                    label: 'Connection',
                    onTap: () => _push(context, const ConnectionSettingsPage()),
                  ),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    label: 'All Settings',
                    onTap: () => _push(context, const SettingsScreen()),
                  ),
                  const _DrawerDivider(),
                  const _UpdateItem(),
                  _DrawerItem(
                    icon: Icons.logout,
                    label: 'Exit',
                    onTap: () => SystemNavigator.pop(),
                  ),
                ],
              ),
            ),
            const _VersionFooter(),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.sublabel,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HemmaTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tokens.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: tokens.textPrimary,
                    ),
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel!,
                      style: TextStyle(
                        fontFamily: 'Hanken Grotesk',
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      child: Divider(height: 1, color: Color.fromRGBO(255, 255, 255, 0.08)),
    );
  }
}

/// "Check for Updates": quietly checks when the drawer opens (if update
/// checks are enabled) and turns into "Update available"; tapping either
/// runs a manual check or opens the update screen.
class _UpdateItem extends StatefulWidget {
  const _UpdateItem();

  @override
  State<_UpdateItem> createState() => _UpdateItemState();
}

class _UpdateItemState extends State<_UpdateItem> {
  bool _checking = false;
  bool _checkedOnce = false;
  AppUpdateInfo? _available;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsStore>(context, listen: false);
    if (settings.updateChecksEnabled) _check(silent: true);
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = !silent);
    try {
      final info = await AppUpdateChecker().check();
      if (!mounted) return;
      setState(() {
        _available = info;
        _checkedOnce = true;
        _checking = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _open() async {
    final info = _available;
    if (info == null) return;
    final version = (await PackageInfo.fromPlatform()).version;
    if (!mounted) return;
    Navigator.of(context).pop(); // close the drawer
    Navigator.of(context).push(MaterialPageRoute(
      builder: (routeContext) => UpdateScreen(
        info: info,
        currentVersion: version,
        onSkip: () => Navigator.of(routeContext).pop(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HemmaTheme.of(context);

    if (_available != null) {
      return _DrawerItem(
        icon: Icons.system_update_alt,
        label: 'Update available',
        sublabel: 'Version ${_available!.version}',
        trailing: Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: tokens.activeColor, shape: BoxShape.circle),
        ),
        onTap: _open,
      );
    }

    return _DrawerItem(
      icon: Icons.system_update_alt,
      label: 'Check for Updates',
      sublabel: _checking
          ? 'Checking…'
          : _checkedOnce
              ? 'You\'re up to date'
              : null,
      trailing: _checking
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _checking ? null : () => _check(),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    final tokens = HemmaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) => Text(
          snapshot.hasData ? 'Version ${snapshot.data!.version}' : '',
          style: TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontSize: 12,
            color: tokens.textSecondary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
