import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../store/settings_store.dart';
import '../../theme/koti_theme.dart';
import 'music_assistant_api.dart';

/// One row for a track/album/artist/playlist/radio result — used by the
/// Search, Browse, and Queue tabs so they all look and behave the same.
class MusicItemTile extends StatelessWidget {
  final MusicItem item;
  final VoidCallback onTap;
  final int? index;

  /// See MusicGridTile's own onLongPress doc — same "play this now"
  /// shortcut for items where onTap prefers browsing in.
  final VoidCallback? onLongPress;

  const MusicItemTile({
    super.key,
    required this.item,
    required this.onTap,
    this.index,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final settings = Provider.of<SettingsStore>(context, listen: false);
    final imageUrl = item.imageUrl;
    final resolvedUrl = imageUrl == null
        ? null
        : (imageUrl.startsWith('http') ? imageUrl : '${settings.activeUrl}$imageUrl');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: ListTile(
        // entityBackground (translucent black) is meant to sit over a photo
        // — on Music's solid dark page it would be nearly invisible, so
        // rows use the lighter overlay instead to read as distinct cards.
        tileColor: tokens.iconCircleBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 44,
            height: 44,
            // See music_grid_tile.dart's cacheWidth comment — same fix,
            // capping decode to roughly this 44px display size instead of
            // the source image's full resolution.
            child: resolvedUrl != null
                ? Image.network(
                    resolvedUrl,
                    fit: BoxFit.cover,
                    cacheWidth: (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                    headers: {'Authorization': 'Bearer ${settings.accessToken ?? ''}'},
                    errorBuilder: (_, __, ___) => _fallbackIcon(tokens),
                  )
                : _fallbackIcon(tokens),
          ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: tokens.entityName, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: item.subtitle != null
            ? Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.entityState, fontSize: 12),
              )
            : null,
        trailing: index != null
            ? Text('${index! + 1}', style: TextStyle(color: tokens.textSecondary))
            : Icon(Icons.play_arrow, color: tokens.textSecondary),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  Widget _fallbackIcon(dynamic tokens) => Container(
        color: tokens.iconCircleBackground,
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
          size: 20,
        ),
      );
}
