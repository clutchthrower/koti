import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cards/card_factory.dart';
import '../edit/card_edit_sheet.dart';
import '../edit/edit_mode.dart';
import '../models/room_config.dart';
import '../store/state_store.dart';
import '../theme/hemma_theme.dart';
import '../theme/tokens.dart';
import '../utils/device_mode.dart';
import 'smart_row.dart';

/// Lays out entity cards the way the original does: a single horizontal
/// row hugging the bottom edge in landscape, a 2-column vertical grid
/// under the title block in portrait. Long-pressing a card enters
/// homescreen-style edit mode (remove ✕ / tap to edit / + to add) when
/// [onCardsChanged] is provided.
class EntityGrid extends StatelessWidget {
  final List<CardConfig> cards;
  final ValueChanged<List<CardConfig>>? onCardsChanged;

  const EntityGrid({super.key, required this.cards, this.onCardsChanged});

  bool _isActive(BuildContext context, CardConfig card) {
    final store = Provider.of<StateStore>(context, listen: false);
    final entity = store.get(card.entityId);
    if (entity == null) return false;
    const activeStates = {
      'on', 'playing', 'buffering', 'unlocked', 'problem', 'cleaning', 'returning'
    };
    return activeStates.contains(entity.state);
  }

  Future<void> _editCard(BuildContext context, CardConfig card) async {
    final result = await showCardEditSheet(context, existing: card);
    if (result == null) return;
    final updated = List.of(cards);
    final i = updated.indexWhere((c) => c.id == card.id);
    if (i == -1) return;
    if (result.deleted) {
      updated.removeAt(i);
    } else {
      updated[i] = result.card!;
    }
    onCardsChanged?.call(updated);
  }

  Future<void> _addCard(BuildContext context) async {
    final result = await showCardEditSheet(context);
    if (result?.card != null) {
      onCardsChanged?.call([...cards, result!.card!]);
    }
  }

  /// Normal mode: long-press enters editing. Edit mode: the card itself is
  /// inert; tapping opens the editor and ✕ removes it.
  Widget _wrapTile(BuildContext context, EditModeController edit, CardConfig card,
      Widget child) {
    if (onCardsChanged == null) return child;
    if (!edit.editing) {
      return GestureDetector(onLongPress: edit.enter, child: child);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: IgnorePointer(child: child)),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _editCard(context, card),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: () {
              final updated = List.of(cards)..removeWhere((c) => c.id == card.id);
              onCardsChanged?.call(updated);
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color.fromRGBO(0, 0, 0, 0.6),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addTile(BuildContext context, Size tile) {
    final tokens = HemmaTheme.of(context);
    return GestureDetector(
      onTap: () => _addCard(context),
      child: Container(
        width: tile.width,
        height: tile.height,
        decoration: BoxDecoration(
          color: tokens.cardBackground.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.35)),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.add, size: 36, color: Colors.white70),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = deviceModeFor(context);
    final portrait = isPortrait(context);
    final tokens = HemmaTheme.of(context);
    final themeController = context.watch<ThemeController>();
    final edit = context.watch<EditModeController>();
    final size = MediaQuery.sizeOf(context);
    final editing = edit.editing && onCardsChanged != null;

    if (portrait) {
      final tile = HemmaTokens.tileSizeMobilePortrait;
      final gutter = mode == DeviceMode.mobile ? tokens.pageGutterMobile : size.width * 0.04;
      final itemCount = cards.length + (editing ? 1 : 0);
      return Padding(
        padding: EdgeInsets.only(
          top: tokens.tilesTopPortrait,
          left: gutter,
          right: gutter,
        ),
        child: GridView.builder(
          padding: const EdgeInsets.only(bottom: 40),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: tile.width / tile.height,
          ),
          itemCount: itemCount,
          itemBuilder: (context, i) => i == cards.length
              ? _addTile(context, tile)
              : _wrapTile(context, edit, cards[i], buildEntityCard(cards[i], i)),
        ),
      );
    }

    final tile = mode == DeviceMode.mobile
        ? HemmaTokens.tileSizeMobileLandscape
        : mode == DeviceMode.tablet
            ? HemmaTokens.tileSizeTablet
            : HemmaTokens.tileSizeDesktop;
    final gutter = mode == DeviceMode.desktop ? size.width * 0.08 : size.width * 0.04;

    // Single row hugging the bottom edge, starting at the page gutter —
    // matches the reference screenshots' card strip. The gutter lives
    // INSIDE the scroll view (as scroll padding), not outside it: an outer
    // Padding would clip scrolled-past cards at the gutter edge instead of
    // letting them slide off the physical screen edge. While editing,
    // smart sorting is suspended so tiles stay put under the user's finger.
    final stripPadding = EdgeInsets.only(left: gutter - 4, right: gutter - 4);
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: SizedBox(
          height: tile.height,
          child: editing
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: stripPadding,
                  child: Row(
                    children: [
                      for (var i = 0; i < cards.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SizedBox(
                            width: tile.width,
                            height: tile.height,
                            child: _wrapTile(
                                context, edit, cards[i], buildEntityCard(cards[i], i)),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _addTile(context, tile),
                      ),
                    ],
                  ),
                )
              : SmartRow<CardConfig>(
                  items: cards,
                  isActive: (card) => _isActive(context, card),
                  sortingEnabled: themeController.smartRowSortingEnabled,
                  padding: stripPadding,
                  itemBuilder: (context, card, position) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      width: tile.width,
                      height: tile.height,
                      child: _wrapTile(
                          context, edit, card, buildEntityCard(card, position)),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
