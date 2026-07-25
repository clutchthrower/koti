import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../store/settings_store.dart';
import '../../theme/koti_theme.dart';
import '../../theme/tokens.dart';
import 'music_assistant_api.dart';

/// Square-art tile for a track/album/artist/playlist/radio result — used by
/// the Browse tab's library grid, HOMEii Flow-style (art-forward tiles
/// rather than [MusicItemTile]'s list rows, which Search/Queue keep since
/// those are more scan-a-list contexts than browse-by-cover-art ones).
class MusicGridTile extends StatelessWidget {
  final MusicItem item;
  final VoidCallback onTap;

  /// A long-press "play this now" shortcut — offered for items that are
  /// both expandable and directly playable (an artist/album/playlist),
  /// since [onTap] on those prefers browsing in over instant-playing them.
  final VoidCallback? onLongPress;

  const MusicGridTile({super.key, required this.item, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final settings = Provider.of<SettingsStore>(context, listen: false);
    final imageUrl = item.imageUrl;
    final resolvedUrl = imageUrl == null
        ? null
        : (imageUrl.startsWith('http') ? imageUrl : '${settings.activeUrl}$imageUrl');
    final round = item.mediaType == 'artist' ? 9999.0 : 14.0;
    // Grid tiles render at ~160 logical px (see maxCrossAxisExtent in
    // music_browse_tab.dart/music_search_tab.dart) — without a decode-size
    // hint, Image.network decodes each result at its full source
    // resolution (MA's image proxy can serve 512px+ art) before scaling
    // down for paint. A grid's worth of those decoding at once was heavy
    // enough on this tablet's hardware to stutter the Sendspin audio
    // thread running alongside it; capping the decode target to roughly
    // the tile's actual on-screen size fixes that at the source.
    final cacheWidth = (160 * MediaQuery.devicePixelRatioOf(context)).round();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(round),
              child: resolvedUrl != null
                  ? Image.network(
                      resolvedUrl,
                      fit: BoxFit.cover,
                      cacheWidth: cacheWidth,
                      headers: {'Authorization': 'Bearer ${settings.accessToken ?? ''}'},
                      errorBuilder: (_, __, ___) => _fallback(tokens, round),
                    )
                  : _fallback(tokens, round),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: tokens.entityName, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if (item.subtitle != null)
            Text(
              item.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.entityState, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _fallback(KotiTokens tokens, double round) => Container(
        decoration: BoxDecoration(
          color: tokens.iconCircleBackground,
          borderRadius: BorderRadius.circular(round),
        ),
        alignment: Alignment.center,
        child: Icon(
          switch (item.mediaType) {
            'artist' => Icons.person,
            'album' => Icons.album,
            'playlist' => Icons.queue_music,
            'radio' => Icons.radio,
            _ => Icons.music_note,
          },
          color: tokens.textSecondary,
          size: 28,
        ),
      );
}
