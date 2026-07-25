import 'package:flutter/material.dart';

import '../../widgets/glass_tab_strip.dart';
import 'music_assistant_api.dart';
import 'music_browse_stack.dart';

// media_content_id values HA's music_assistant integration's root browse
// listing uses for each library category (media_browser.py's LIBRARY_*
// constants) — media_content_type just needs to be some non-null string
// alongside it (HA's schema requires the pair together but the actual
// routing only inspects media_content_id), so 'music_assistant' (the
// integration's own domain) is used for all of them.
const _categories = [
  ('artists', 'Artists'),
  ('albums', 'Albums'),
  ('playlists', 'Playlists'),
  ('radio', 'Radio'),
  ('tracks', 'Tracks'),
];

class MusicBrowseTab extends StatefulWidget {
  final String entityId;
  final MusicAssistantApi api;

  const MusicBrowseTab({super.key, required this.entityId, required this.api});

  @override
  State<MusicBrowseTab> createState() => _MusicBrowseTabState();
}

class _MusicBrowseTabState extends State<MusicBrowseTab>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _typeController = TabController(length: _categories.length, vsync: this)
    ..addListener(() {
      if (!_typeController.indexIsChanging) setState(() {});
    });

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _typeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final (categoryId, _) = _categories[_typeController.index];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GlassTabStrip(
            controller: _typeController,
            labels: [for (final c in _categories) c.$2],
            scrollable: true,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          // Keyed on the category so switching top tabs starts that
          // category's own browsing session fresh at its root, rather
          // than continuing wherever the previous category's drill-down
          // happened to be.
          child: MusicBrowseStack(
            key: ValueKey(categoryId),
            entityId: widget.entityId,
            api: widget.api,
            rootMediaContentType: 'music_assistant',
            rootMediaContentId: categoryId,
          ),
        ),
      ],
    );
  }
}
