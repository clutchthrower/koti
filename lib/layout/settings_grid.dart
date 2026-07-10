import 'package:flutter/material.dart';

import '../cards/base_entity_card.dart';
import '../theme/koti_theme.dart';
import '../theme/tokens.dart';
import '../utils/device_mode.dart';

/// One settings tile — deliberately the same shape [EntityGrid] builds its
/// cards from, so Settings can share its exact layout math and read as a
/// continuation of the room views rather than a different kind of screen.
class SettingsEntry {
  final IconData icon;
  final String label;
  final String stateText;
  final bool active;
  final VoidCallback? onTap;

  const SettingsEntry({
    required this.icon,
    required this.label,
    required this.stateText,
    this.active = false,
    this.onTap,
  });
}

/// Same portrait 2-column-grid / landscape bottom-hugging-row layout as
/// [EntityGrid], minus the editing machinery — settings tiles are a fixed
/// list, not user-configurable cards.
class SettingsGrid extends StatelessWidget {
  final List<SettingsEntry> entries;

  const SettingsGrid({super.key, required this.entries});

  Widget _tile(SettingsEntry entry, int position) => KotiEntityCard(
        materialIcon: entry.icon,
        label: entry.label,
        stateText: entry.stateText,
        active: entry.active,
        position: position,
        onTap: entry.onTap,
      );

  @override
  Widget build(BuildContext context) {
    final mode = deviceModeFor(context);
    final portrait = isPortrait(context);
    final tokens = KotiTheme.of(context);
    final size = MediaQuery.sizeOf(context);

    if (portrait) {
      final tile = KotiTokens.tileSizeMobilePortrait;
      final gutter = mode == DeviceMode.mobile ? tokens.pageGutterMobile : size.width * 0.04;
      // Same fade-mask trick as EntityGrid: cards scrolling up dissolve
      // instead of vanishing at a hard line under the title.
      const fadeExtent = 48.0;
      return Padding(
        padding: EdgeInsets.only(
          top: tokens.tilesTopPortrait - fadeExtent,
          left: gutter,
          right: gutter,
        ),
        child: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.transparent, Colors.white],
            stops: [0.0, (fadeExtent / rect.height).clamp(0.0, 1.0)],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: GridView.builder(
            padding: const EdgeInsets.only(top: fadeExtent + 8, bottom: 40),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: tile.width / tile.height,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) => _tile(entries[i], i),
          ),
        ),
      );
    }

    final tile = mode == DeviceMode.mobile
        ? KotiTokens.tileSizeMobileLandscape
        : mode == DeviceMode.tablet
            ? KotiTokens.tileSizeTablet
            : KotiTokens.tileSizeDesktop;
    final gutter = mode == DeviceMode.desktop ? size.width * 0.08 : size.width * 0.04;
    final stripPadding = EdgeInsets.only(left: gutter - 4, right: gutter - 4);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: SizedBox(
          height: tile.height,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: stripPadding,
            itemCount: entries.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: tile.width,
                height: tile.height,
                child: _tile(entries[i], i),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
