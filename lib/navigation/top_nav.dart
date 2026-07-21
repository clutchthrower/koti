import 'package:flutter/material.dart';

import '../models/room_config.dart';
import '../theme/koti_theme.dart';

/// The original dashboard's navigation: a row of text tabs across the top
/// — Home, then each room by name, then "Scenes ⌄" — inside a translucent
/// pill (tablet style). The selected tab gets a lighter pill highlight.
class KotiTopNav extends StatelessWidget {
  final List<RoomConfig> rooms;

  /// Selected room id, or null when the Home tab is active (unless
  /// [homeSelected] is overridden — e.g. while a non-room view like Music
  /// is showing, so neither Home nor any room reads as selected).
  final String? selectedRoomId;

  /// Called with the tapped room, or null for the Home tab.
  final ValueChanged<RoomConfig?> onSelect;
  final VoidCallback onScenes;
  final bool homeSelected;

  const KotiTopNav({
    super.key,
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelect,
    required this.onScenes,
    bool? homeSelected,
  }) : homeSelected = homeSelected ?? (selectedRoomId == null);

  @override
  Widget build(BuildContext context) {
    // Home and Scenes stay put at either end; only the room tabs between
    // them scroll — so there's always a stable "swipe left for Home, right
    // for Scenes" landmark regardless of how many rooms are configured.
    return Container(
      decoration: BoxDecoration(
        color: KotiTheme.of(context).pillBackground,
        borderRadius: BorderRadius.circular(9999),
      ),
      padding: const EdgeInsets.all(5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavTab(
            label: 'Home',
            selected: homeSelected,
            onTap: () => onSelect(null),
          ),
          if (rooms.isNotEmpty)
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final room in rooms)
                      _NavTab(
                        label: room.name,
                        selected: room.id == selectedRoomId,
                        onTap: () => onSelect(room),
                      ),
                  ],
                ),
              ),
            ),
          _NavTab(
            label: 'Scenes',
            selected: false,
            trailing: const Icon(Icons.expand_more, size: 18, color: Colors.white70),
            onTap: onScenes,
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? KotiTheme.of(context).pillSelectedBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Hanken Grotesk',
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 16,
                color: selected ? Colors.white : Colors.white70,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 2), trailing!],
          ],
        ),
      ),
    );
  }
}
