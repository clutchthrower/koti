import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../popups/camera_popup.dart';
import '../store/settings_store.dart';
import '../store/state_store.dart';
import '../theme/hemma_theme.dart';
import '../widgets/entity_watcher.dart';

/// Camera tile: the card itself is a still preview refreshed every ~10s
/// (cheap enough to keep on screen); tapping opens the live-view popup.
class CameraCard extends StatefulWidget {
  final String entityId;
  final String? label;
  final int position;

  const CameraCard(
      {super.key, required this.entityId, this.label, this.position = 0});

  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard> {
  Timer? _refresh;
  int _cacheBust = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() => _cacheBust = DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HemmaTheme.of(context);
    final settings = Provider.of<SettingsStore>(context, listen: false);
    final store = Provider.of<StateStore>(context, listen: false);

    return EntityWatcher(
      entityIds: [widget.entityId],
      builder: (context, states) {
        final entity = states[widget.entityId] ?? store.get(widget.entityId);
        final name = widget.label ??
            entity?.attr<String>('friendly_name', widget.entityId) ??
            widget.entityId;
        final available =
            entity != null && entity.state != 'unavailable' && entity.state != 'unknown';
        final url =
            '${settings.activeUrl}/api/camera_proxy/${widget.entityId}?t=$_cacheBust';

        return GestureDetector(
          onTap: available
              ? () =>
                  showCameraPopup(context, entityId: widget.entityId, title: name)
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
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
                          available ? 'Tap for live view' : 'Unavailable',
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
        );
      },
    );
  }
}
