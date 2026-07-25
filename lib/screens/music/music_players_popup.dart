import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../popups/popup_base.dart';
import '../../store/state_store.dart';
import '../../theme/koti_theme.dart';
import '../../widgets/entity_watcher.dart';

/// Every `media_player` entity that's actually usable — hides
/// `unavailable`/`unknown` ones, since these are almost always stale
/// leftovers (e.g. a second, orphaned entity_id left behind after an
/// integration re-registered a device) rather than real alternate players.
List<String> availablePlayerIds(StateStore store) {
  final ids = store.all.entries
      .where((e) =>
          e.key.startsWith('media_player.') &&
          e.value.state != 'unavailable' &&
          e.value.state != 'unknown')
      .map((e) => e.key)
      .toList()
    ..sort();
  return ids;
}

/// Music Assistant mirrors every player it manages into HA as its own
/// `media_player` entity — including ones that are ALSO natively
/// integrated (a Cast/webOS/etc. entity from a completely separate HA
/// integration), which is what causes the real "double speaker" duplicates
/// (confirmed live against the user's HA, not guessed): e.g.
/// `media_player.bedroom_speaker` (platform `cast`) and
/// `media_player.bedroom_speaker_2` (platform `music_assistant`) are two
/// distinct HA entities for the same physical speaker. The registry proved
/// a reliable link between them: MA reuses the underlying protocol's own
/// device identifier as its mirrored entity's `unique_id`, so both
/// entities share the exact same `unique_id` string even though they're
/// unrelated HA registrations. Grouping by `unique_id` and keeping only
/// the `music_assistant`-platform entity (the one MA's own services are
/// guaranteed to work with) resolves the duplicate cleanly.
///
/// This does NOT catch every duplicate a user might see — e.g. a
/// physical TV controllable via both HA's native "LG webOS TV"
/// integration and Google Cast has two independent identifier systems
/// with no shared value in HA's registry at all, so there's nothing here
/// to match on. Music Assistant itself doesn't treat that TV's webOS
/// entity as a player either (it's not Music-Assistant-controllable), so
/// that kind of duplicate needs resolving directly in HA (Settings →
/// Devices & services → Entities → disable the one you don't want to see).
Future<List<String>> dedupedPlayerIds(StateStore store, List<String> candidateIds) async {
  List<Map<String, dynamic>> registry;
  try {
    registry = await store.getEntityRegistry();
  } catch (_) {
    // Needs an admin account — fall back to the unfiltered list rather
    // than throwing into the UI.
    return candidateIds;
  }
  final byId = {
    for (final e in registry)
      if (e['entity_id'] is String) e['entity_id'] as String: e,
  };
  final byUniqueId = <String, List<String>>{};
  for (final id in candidateIds) {
    final uniqueId = byId[id]?['unique_id'] as String?;
    if (uniqueId == null) continue;
    byUniqueId.putIfAbsent(uniqueId, () => []).add(id);
  }
  final hide = <String>{};
  for (final group in byUniqueId.values) {
    if (group.length < 2) continue;
    final maPlayer = group.firstWhere(
      (id) => byId[id]?['platform'] == 'music_assistant',
      orElse: () => group.first,
    );
    hide.addAll(group.where((id) => id != maPlayer));
  }
  return candidateIds.where((id) => !hide.contains(id)).toList();
}

/// Shows every player as a card (name, what's playing, its own live volume
/// slider) in a popup — modeled on HOMEii Flow's "Players" grid. The sole
/// entry point for picking/switching a player: called from wherever a
/// player-picking affordance sits (the speaker-group icon on the volume
/// bar once one's selected, or the empty-state prompt before any is).
void showMusicPlayersPopup(
  BuildContext context, {
  required String? selected,
  required ValueChanged<String> onSelect,
}) {
  final store = Provider.of<StateStore>(context, listen: false);
  showKotiPopup(
    context,
    title: 'Players',
    builder: (context) => _PlayersList(store: store, selected: selected, onSelect: onSelect),
  );
}

class _PlayersList extends StatefulWidget {
  final StateStore store;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _PlayersList({required this.store, required this.selected, required this.onSelect});

  @override
  State<_PlayersList> createState() => _PlayersListState();
}

class _PlayersListState extends State<_PlayersList> {
  // Registry-based dedup only needs computing once per popup open — the
  // registry itself doesn't change while this is on screen, and
  // recomputing on every entity-state tick would just redo the same work.
  late final Future<List<String>> _dedupedIds =
      dedupedPlayerIds(widget.store, availablePlayerIds(widget.store));

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    return FutureBuilder<List<String>>(
      future: _dedupedIds,
      initialData: availablePlayerIds(widget.store),
      builder: (context, snapshot) {
        final ids = snapshot.data ?? const [];
        if (ids.isEmpty) {
          return Text('No media players found',
              style: TextStyle(color: tokens.textSecondary));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final id in ids)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PlayerCard(
                  entityId: id,
                  selected: id == widget.selected,
                  onTap: () {
                    widget.onSelect(id);
                    Navigator.of(context).pop();
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlayerCard extends StatefulWidget {
  final String entityId;
  final bool selected;
  final VoidCallback onTap;

  const _PlayerCard({required this.entityId, required this.selected, required this.onTap});

  @override
  State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard> {
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final store = Provider.of<StateStore>(context, listen: false);

    return EntityWatcher(
      entityIds: [widget.entityId],
      builder: (context, states) {
        final entity = states[widget.entityId];
        final name = entity?.attr<String>('friendly_name', widget.entityId) ?? widget.entityId;
        final state = entity?.state ?? 'unavailable';
        final playing = state == 'playing' || state == 'buffering';
        final title = entity?.attr<String>('media_title', '');
        final subtitle = playing && (title?.isNotEmpty ?? false) ? title! : _stateLabel(state);
        final volume = entity?.attrDouble('volume_level');

        final card = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: widget.selected ? tokens.borderGradient : null,
            color: widget.selected ? null : Colors.transparent,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              color: widget.selected
                  ? tokens.entityBackgroundActive.withValues(alpha: 0.18)
                  : tokens.iconCircleBackground,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(playing ? Icons.graphic_eq : Icons.speaker_outlined,
                        size: 16,
                        color: playing ? tokens.activeColor : tokens.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Hanken Grotesk',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: tokens.entityName,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.entityState, fontSize: 11),
                ),
                if (volume != null)
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: tokens.activeColor,
                      inactiveTrackColor: tokens.iconCircleBackground,
                      thumbColor: tokens.activeColor,
                    ),
                    child: Slider(
                      value: (_dragVolume ?? volume).clamp(0.0, 1.0),
                      onChanged: (v) => setState(() => _dragVolume = v),
                      onChangeEnd: (v) {
                        store.callService('media_player', 'volume_set',
                            entityId: widget.entityId, data: {'volume_level': v});
                        setState(() => _dragVolume = null);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );

        return GestureDetector(onTap: widget.onTap, child: card);
      },
    );
  }

  String _stateLabel(String state) => switch (state) {
        'off' => 'Off',
        'idle' => 'Idle',
        'paused' => 'Paused',
        'standby' => 'Standby',
        'unavailable' => 'Unavailable',
        _ => state.isEmpty ? '' : state[0].toUpperCase() + state.substring(1),
      };
}
