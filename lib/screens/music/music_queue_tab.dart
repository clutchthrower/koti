import 'package:flutter/material.dart';

import '../../theme/koti_theme.dart';
import 'music_assistant_api.dart';
import 'music_item_tile.dart';

class MusicQueueTab extends StatefulWidget {
  final String entityId;
  final MusicAssistantApi api;

  const MusicQueueTab({super.key, required this.entityId, required this.api});

  @override
  State<MusicQueueTab> createState() => _MusicQueueTabState();
}

class _MusicQueueTabState extends State<MusicQueueTab>
    with AutomaticKeepAliveClientMixin {
  MusicQueueInfo? _queue;
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MusicQueueTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId) {
      _queue = null;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final queue = await widget.api.getQueue(widget.entityId);
      if (!mounted) return;
      setState(() {
        _queue = queue;
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tokens = KotiTheme.of(context);
    final queue = _queue;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Couldn\'t load the queue: $_error',
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          if (queue == null) ...[
            if (!_loading)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                    child: Text('Nothing to show',
                        style: TextStyle(color: tokens.textSecondary))),
              ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      queue.name.isNotEmpty ? queue.name : 'Queue',
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
                    ),
                  ),
                  if (queue.shuffleEnabled)
                    Icon(Icons.shuffle, size: 16, color: tokens.activeColor),
                  if (queue.repeatMode != 'off') ...[
                    const SizedBox(width: 8),
                    Icon(Icons.repeat, size: 16, color: tokens.activeColor),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                queue.active
                    ? '${queue.itemCount} item${queue.itemCount == 1 ? '' : 's'} in queue'
                    : 'Not active',
                style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            if (queue.currentItem != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Now playing',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
              ),
              MusicItemTile(
                item: queue.currentItem!,
                onTap: () {},
              ),
            ],
            if (queue.nextItem != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Up next',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
              ),
              MusicItemTile(
                item: queue.nextItem!,
                onTap: () => widget.api.playItem(widget.entityId,
                    uri: queue.nextItem!.uri, mediaType: queue.nextItem!.mediaType),
              ),
            ],
            if (queue.currentItem == null && queue.nextItem == null && !_loading)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                    child: Text('Queue is empty',
                        style: TextStyle(color: tokens.textSecondary))),
              ),
          ],
        ],
      ),
    );
  }
}
