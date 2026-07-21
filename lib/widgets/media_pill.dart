import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/entity_state.dart';
import '../store/state_store.dart';
import '../theme/koti_theme.dart';
import 'entity_watcher.dart';
import 'koti_icon.dart';

/// The "now playing" pill under the hero badges: track title, artist, and
/// pause/next controls for the first media player that's actively playing.
/// Hidden entirely when nothing is playing, like the original.
class MediaPill extends StatelessWidget {
  final List<String> mediaPlayerEntityIds;
  const MediaPill({super.key, required this.mediaPlayerEntityIds});

  @override
  Widget build(BuildContext context) {
    if (mediaPlayerEntityIds.isEmpty) return const SizedBox.shrink();
    final tokens = KotiTheme.of(context);

    return EntityWatcher(
      entityIds: mediaPlayerEntityIds,
      builder: (context, states) {
        EntityState? playing;
        for (final id in mediaPlayerEntityIds) {
          final s = states[id];
          if (s != null && (s.state == 'playing' || s.state == 'paused')) {
            playing = s;
            if (s.state == 'playing') break; // prefer an actively playing one
          }
        }
        if (playing == null) return const SizedBox.shrink();

        final title = playing.attr<String>('media_title', '');
        final artist = playing.attr<String>('media_artist', '');
        final isPlaying = playing.state == 'playing';
        final store = Provider.of<StateStore>(context, listen: false);
        final entityId = playing.entityId;

        return Container(
          constraints: const BoxConstraints(minHeight: 56, maxWidth: 340),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: tokens.badgeBackground,
            borderRadius: BorderRadius.circular(tokens.badgeRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.iconCircleBackground,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const KotiIcon('music', size: 22, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Playing' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Hanken Grotesk',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    if (artist.isNotEmpty)
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Hanken Grotesk',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _RoundButton(
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                onTap: () => store.callService(
                    'media_player', 'media_play_pause', entityId: entityId),
              ),
              const SizedBox(width: 6),
              _RoundButton(
                icon: Icons.skip_next,
                onTap: () => store.callService(
                    'media_player', 'media_next_track', entityId: entityId),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color.fromRGBO(255, 255, 255, 0.20),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 22, color: Colors.white),
      ),
    );
  }
}
