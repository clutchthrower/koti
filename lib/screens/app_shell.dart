import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../edit/background_sheet.dart';
import '../edit/edit_mode.dart';
import '../models/room_config.dart';
import '../navigation/top_nav.dart';
import '../popups/scenes_popup.dart';
import '../store/settings_store.dart';
import '../store/state_store.dart';
import '../theme/koti_theme.dart';
import '../widgets/clock_widget.dart';
import 'home_overview_screen.dart';
import 'music/music_assistant_screen.dart';
import 'room_screen.dart';
import 'screensaver_screen.dart';
import 'settings_view.dart';

/// Top-level shell mirroring the original dashboard chrome: hamburger
/// top-left, the Home/rooms/Scenes text-tab nav top-center, clock
/// top-right, with the full-screen [HomeView]/[RoomView] behind it. Also
/// owns the idle-timeout screensaver. No sliding side menu — the menu icon
/// swaps in [SettingsView] as the body, the same way the music icon swaps
/// in the Music page, so it reads as one continuous screen rather than a
/// panel layered on top.
class AppShell extends StatefulWidget {
  final SettingsStore settings;
  const AppShell({super.key, required this.settings});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _editMode = EditModeController();

  /// Selected room id; null means the Home tab (or Music/Settings, see
  /// [_showMusic]/[_showSettings]).
  String? _roomId;
  /// Only meaningful when [_roomId] is null — Music sits one swipe to the
  /// left of Home, outside the room sequence.
  bool _showMusic = false;
  /// Only reachable via the menu icon, not swipeable — sits "on top of"
  /// whichever destination was last active, so leaving it (via a nav tab,
  /// the music icon, or a swipe) returns there.
  bool _showSettings = false;
  Timer? _idleTimer;
  bool _showScreensaver = false;

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _editMode.dispose();
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    final minutes =
        Provider.of<ThemeController>(context, listen: false).screensaverTimeoutMinutes;
    if (_showScreensaver) setState(() => _showScreensaver = false);
    if (minutes <= 0) return;
    _idleTimer = Timer(Duration(minutes: minutes), () {
      // Never black out mid-edit.
      if (mounted && !_editMode.editing) setState(() => _showScreensaver = true);
    });
  }

  /// Swipe left/right anywhere on the background steps through
  /// Music → Home → room1 → room2 … (scrollable rows like the card strip
  /// keep their own gesture and are unaffected).
  void _onHorizontalSwipe(DragEndDetails details) {
    if (_editMode.editing) return;
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < 250) return;
    final rooms = widget.settings.rooms;
    final musicEnabled = widget.settings.musicAssistantEnabled;
    // Position in the sequence: -2 = Music, -1 = Home, otherwise room index.
    // A swipe while Settings is showing just dismisses it back to whatever
    // was last active, rather than moving from Settings itself.
    var index = _showMusic
        ? -2
        : (_roomId == null ? -1 : rooms.indexWhere((r) => r.id == _roomId));
    if (!_showSettings) {
      index += v < 0 ? 1 : -1; // swipe left = forward
    }
    final minIndex = musicEnabled ? -2 : -1;
    if (index < minIndex || index >= rooms.length) return;
    setState(() {
      _showSettings = false;
      _showMusic = index == -2;
      _roomId = index >= 0 ? rooms[index].id : null;
    });
  }

  Future<void> _editBackground(RoomConfig? currentRoom) async {
    final settings = widget.settings;
    final room = currentRoom ??
        effectiveHomeConfig(
          rooms: settings.rooms,
          store: Provider.of<StateStore>(context, listen: false),
          saved: settings.homeRoom,
        );
    final updated = await showBackgroundSheet(context, room);
    if (updated == null) return;
    if (currentRoom != null) {
      final rooms = List.of(settings.rooms);
      final i = rooms.indexWhere((r) => r.id == currentRoom.id);
      if (i != -1) {
        rooms[i] = updated;
        await settings.setRooms(rooms);
      }
    } else {
      await settings.setHomeRoom(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.settings.rooms;
    RoomConfig? currentRoom;
    for (final r in rooms) {
      if (r.id == _roomId) currentRoom = r;
    }
    final theme = context.watch<ThemeController>();
    final tokens = KotiTheme.of(context);
    final musicEnabled = widget.settings.musicAssistantEnabled;

    return ChangeNotifierProvider<EditModeController>.value(
      value: _editMode,
      child: Listener(
        onPointerDown: (_) => _resetIdleTimer(),
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: _onHorizontalSwipe,
                  child: _showSettings
                      ? const SettingsView()
                      : _showMusic
                          ? const MusicAssistantScreen()
                          : (currentRoom != null
                              ? RoomView(room: currentRoom)
                              : const HomeView()),
                ),
              ),
              // Top chrome: hamburger / nav tabs / clock, like the
              // original — or the edit-mode banner while editing.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: AnimatedBuilder(
                      animation: _editMode,
                      builder: (context, _) => _editMode.editing
                          ? _EditModeBar(
                              roomName: currentRoom?.name ?? 'Home',
                              onDone: _editMode.exit,
                              onBackground: () => _editBackground(currentRoom),
                            )
                          : Row(
                              children: [
                                IconButton(
                                  tooltip: 'Settings',
                                  icon: Icon(Icons.menu,
                                      color: _showSettings
                                          ? tokens.activeColor
                                          : Colors.white70),
                                  onPressed: () =>
                                      setState(() => _showSettings = true),
                                ),
                                if (musicEnabled)
                                  IconButton(
                                    tooltip: 'Music',
                                    icon: Icon(Icons.music_note,
                                        color: !_showSettings && _showMusic
                                            ? tokens.activeColor
                                            : Colors.white70),
                                    onPressed: () => setState(() {
                                      _showSettings = false;
                                      _showMusic = true;
                                      _roomId = null;
                                    }),
                                  ),
                                Expanded(
                                  child: Center(
                                    child: KotiTopNav(
                                      rooms: rooms,
                                      selectedRoomId: _roomId,
                                      homeSelected: !_showSettings &&
                                          !_showMusic &&
                                          _roomId == null,
                                      onSelect: (room) => setState(() {
                                        _showSettings = false;
                                        _showMusic = false;
                                        _roomId = room?.id;
                                      }),
                                      onScenes: () => showScenesPopup(context),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                const ClockWidget(
                                  style: TextStyle(
                                    fontFamily: 'Hanken Grotesk',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              if (_showScreensaver && theme.screensaverTimeoutMinutes > 0)
                Positioned.fill(
                  child: ScreensaverScreen(
                      onDismiss: () => setState(() => _showScreensaver = false)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Replaces the nav bar while editing: what's being edited, a hint, a
/// background picker, and Done.
class _EditModeBar extends StatelessWidget {
  final String roomName;
  final VoidCallback onDone;
  final VoidCallback onBackground;

  const _EditModeBar({
    required this.roomName,
    required this.onDone,
    required this.onBackground,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 0, 0, 0.45),
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit, size: 18, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Editing $roomName — tap a card or badge to change it',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Background',
                  icon: const Icon(Icons.wallpaper, color: Colors.white),
                  onPressed: onBackground,
                ),
                FilledButton(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
