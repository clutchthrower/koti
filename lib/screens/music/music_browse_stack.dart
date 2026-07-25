import 'package:flutter/material.dart';

import '../../theme/koti_theme.dart';
import 'music_assistant_api.dart';
import 'music_grid_tile.dart';

/// One drill-down browsing session against HA's `media_player/browse_media`
/// — starts at [rootMediaContentType]/[rootMediaContentId] and pushes a new
/// level each time the user taps into an expandable node (an artist showing
/// their albums, a playlist/album showing its tracks, ...), instead of the
/// old behavior where every tap just instant-played whatever was tapped.
///
/// Shared between [MusicBrowseTab] (each top category tab is its own root)
/// and [MusicSearchTab] (an artist/album/playlist search result becomes a
/// root once tapped) — give each instantiation a fresh [Key] (e.g. keyed on
/// the root content id) when the root itself changes, since that's what
/// resets this widget's internal navigation stack.
class MusicBrowseStack extends StatefulWidget {
  final String entityId;
  final MusicAssistantApi api;
  final String rootMediaContentType;
  final String rootMediaContentId;

  /// When set, a back arrow is shown even at the root level (normally
  /// hidden there, since there's nothing left to pop) — pressing it calls
  /// this instead of popping. Used when this stack was pushed from outside
  /// browsing itself (e.g. Search tapping into a result), so there's
  /// somewhere sensible for "back" to go once the stack itself is empty.
  final VoidCallback? onExitRoot;

  const MusicBrowseStack({
    super.key,
    required this.entityId,
    required this.api,
    required this.rootMediaContentType,
    required this.rootMediaContentId,
    this.onExitRoot,
  });

  @override
  State<MusicBrowseStack> createState() => _MusicBrowseStackState();
}

class _MusicBrowseStackState extends State<MusicBrowseStack> {
  final List<BrowseNode> _stack = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  Future<void> _loadRoot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final node = await widget.api.browseMedia(
        widget.entityId,
        mediaContentType: widget.rootMediaContentType,
        mediaContentId: widget.rootMediaContentId,
      );
      if (!mounted) return;
      setState(() {
        _stack
          ..clear()
          ..add(node);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _expand(BrowseNode node) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final child = await widget.api.browseMedia(
        widget.entityId,
        mediaContentType: node.mediaContentType,
        mediaContentId: node.mediaContentId,
      );
      if (!mounted) return;
      setState(() {
        _stack.add(child);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _back() {
    if (_stack.length > 1) {
      setState(() => _stack.removeLast());
    } else {
      widget.onExitRoot?.call();
    }
  }

  // Prefers browsing in over playing when a node is both — a playlist or
  // album is can_play *and* can_expand, and always instant-playing it
  // (the old behavior) never let the user see or pick individual tracks.
  void _onTapNode(BrowseNode node) {
    if (node.canExpand) {
      _expand(node);
    } else if (node.canPlay) {
      widget.api.playItem(widget.entityId, uri: node.mediaContentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final current = _stack.isEmpty ? null : _stack.last;
    final items = current?.children ?? const <BrowseNode>[];
    final showBackBar = current != null && (_stack.length > 1 || widget.onExitRoot != null);

    return Column(
      children: [
        if (showBackBar)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: tokens.textPrimary),
                  onPressed: _back,
                ),
                Expanded(
                  child: Text(
                    current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: tokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                // A folder that's ALSO directly playable (an album/
                // playlist, not a plain artists/albums/... category
                // folder) — an explicit way to play the whole thing
                // without picking a specific track.
                if (current.canPlay)
                  IconButton(
                    icon: Icon(Icons.play_circle_fill, color: tokens.activeColor),
                    tooltip: 'Play all',
                    onPressed: () =>
                        widget.api.playItem(widget.entityId, uri: current.mediaContentId),
                  ),
              ],
            ),
          ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Couldn\'t load: $_error', style: const TextStyle(color: Colors.redAccent)),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    _loading ? 'Loading…' : 'Nothing here',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final node = items[i];
                    return MusicGridTile(
                      item: MusicItem.fromBrowseNode(node),
                      onTap: () => _onTapNode(node),
                      onLongPress: node.canPlay && node.canExpand
                          ? () => widget.api.playItem(widget.entityId, uri: node.mediaContentId)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
