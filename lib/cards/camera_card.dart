import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../popups/camera_popup.dart';
import '../store/settings_store.dart';
import '../store/state_store.dart';
import '../theme/koti_theme.dart';
import '../widgets/entity_watcher.dart';

/// Camera tile: the card itself is a still preview refreshed every ~10s
/// (cheap enough to keep on screen); tapping opens the live-view popup. When
/// [motionEntityId] is set, the card pulses a red gradient border while that
/// binary_sensor is `on` — a cheap decoration-only animation (no blur/shader
/// work) so it stays smooth on old hardware, and only the border repaints
/// via its own AnimatedBuilder rather than the whole tile.
class CameraCard extends StatefulWidget {
  final String entityId;
  final String? label;
  final String? motionEntityId;
  final int position;

  const CameraCard({
    super.key,
    required this.entityId,
    this.label,
    this.motionEntityId,
    this.position = 0,
  });

  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard> with SingleTickerProviderStateMixin {
  Timer? _refresh;
  int _cacheBust = DateTime.now().millisecondsSinceEpoch;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() => _cacheBust = DateTime.now().millisecondsSinceEpoch);
      }
    });
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final settings = Provider.of<SettingsStore>(context, listen: false);
    final store = Provider.of<StateStore>(context, listen: false);
    final motionId = widget.motionEntityId;

    return EntityWatcher(
      entityIds: [widget.entityId, if (motionId != null) motionId],
      builder: (context, states) {
        final entity = states[widget.entityId] ?? store.get(widget.entityId);
        final name = widget.label ??
            entity?.attr<String>('friendly_name', widget.entityId) ??
            widget.entityId;
        final available =
            entity != null && entity.state != 'unavailable' && entity.state != 'unknown';
        final url =
            '${settings.activeUrl}/api/camera_proxy/${widget.entityId}?t=$_cacheBust';

        final motionActive = motionId != null && states[motionId]?.state == 'on';
        if (motionActive && !_pulse.isAnimating) {
          _pulse.repeat(reverse: true);
        } else if (!motionActive && _pulse.isAnimating) {
          _pulse.stop();
          _pulse.reset();
        }

        return GestureDetector(
          onTap: available
              ? () =>
                  showCameraPopup(context, entityId: widget.entityId, title: name)
              : null,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = motionActive ? _pulse.value : 0.0;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  gradient: motionActive
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(Colors.red.shade900, Colors.red.shade400, t)!,
                            Color.lerp(Colors.red.shade400, Colors.red.shade900, t)!,
                          ],
                        )
                      : null,
                ),
                padding: EdgeInsets.all(motionActive ? 3 : 0),
                child: child,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.cardRadius - 3),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: tokens.cardBackground),
                  if (available)
                    Image.network(
                      url,
                      headers: {
                        'Authorization': 'Bearer ${settings.accessToken ?? ''}'
                      },
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  // Legibility scrim behind the name, like the hero title.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color.fromRGBO(0, 0, 0, 0.65)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Hanken Grotesk',
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            motionActive
                                ? 'Motion detected'
                                : available
                                    ? 'Tap for live view'
                                    : 'Unavailable',
                            style: const TextStyle(
                              fontFamily: 'Hanken Grotesk',
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
