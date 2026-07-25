import 'package:flutter/material.dart';

import '../../theme/koti_theme.dart';
import 'music_assistant_api.dart';
import 'music_browse_stack.dart';
import 'music_item_tile.dart';

// Media types worth browsing INTO rather than instant-playing when tapped
// from a search result — matches BrowseNode.mediaClass's real values (an
// artist's own tracks/albums, a playlist's/album's own tracks).
const _expandableTypes = {'artist', 'album', 'playlist'};

class MusicSearchTab extends StatefulWidget {
  final String entityId;
  final MusicAssistantApi api;

  const MusicSearchTab({super.key, required this.entityId, required this.api});

  @override
  State<MusicSearchTab> createState() => _MusicSearchTabState();
}

class _MusicSearchTabState extends State<MusicSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  List<MusicItem>? _results;
  bool _loading = false;
  String? _error;

  // Non-null once the user taps an artist/album/playlist result — swaps
  // the results list for a MusicBrowseStack rooted at that item, instead
  // of the old behavior where tapping it just instant-played the whole
  // thing with no way to see or pick individual tracks.
  MusicItem? _browsing;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _browsing = null;
    });
    try {
      final results = await widget.api.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
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

  void _onTapResult(MusicItem item) {
    if (_expandableTypes.contains(item.mediaType)) {
      setState(() => _browsing = item);
    } else {
      widget.api.playItem(widget.entityId, uri: item.uri, mediaType: item.mediaType);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tokens = KotiTheme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            style: TextStyle(color: tokens.textPrimary),
            cursorColor: tokens.activeColor,
            decoration: InputDecoration(
              hintText: 'Search tracks, artists, albums…',
              hintStyle: TextStyle(color: tokens.textSecondary),
              prefixIcon: Icon(Icons.search, color: tokens.textSecondary),
              suffixIcon: IconButton(
                icon: Icon(Icons.arrow_forward, color: tokens.textSecondary),
                onPressed: _search,
              ),
              filled: true,
              fillColor: tokens.entityBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: tokens.activeColor, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Search failed: $_error',
                style: const TextStyle(color: Colors.redAccent)),
          ),
        Expanded(
          child: _browsing != null
              ? MusicBrowseStack(
                  key: ValueKey(_browsing!.uri),
                  entityId: widget.entityId,
                  api: widget.api,
                  rootMediaContentType: _browsing!.mediaType,
                  rootMediaContentId: _browsing!.uri,
                  onExitRoot: () => setState(() => _browsing = null),
                )
              : _results == null
                  ? Center(
                      child: Text('Search Music Assistant\'s library',
                          style: TextStyle(color: tokens.textSecondary)))
                  : _results!.isEmpty
                      ? Center(
                          child: Text('No results',
                              style: TextStyle(color: tokens.textSecondary)))
                      : ListView.builder(
                          itemCount: _results!.length,
                          itemBuilder: (context, i) => MusicItemTile(
                            item: _results![i],
                            onTap: () => _onTapResult(_results![i]),
                            onLongPress: _expandableTypes.contains(_results![i].mediaType)
                                ? () => widget.api.playItem(widget.entityId,
                                    uri: _results![i].uri, mediaType: _results![i].mediaType)
                                : null,
                          ),
                        ),
        ),
      ],
    );
  }
}
