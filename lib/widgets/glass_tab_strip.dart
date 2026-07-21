import 'package:flutter/material.dart';

import '../theme/koti_theme.dart';

/// A pill-shaped tab strip in the same visual language as [KotiTopNav]'s
/// room tabs (translucent dark pill, lighter pill highlight on the
/// selected tab) — used wherever a page needs its own tab row without
/// pulling in Material's default [TabBar] look.
class GlassTabStrip extends StatelessWidget {
  final TabController controller;
  final List<String> labels;

  /// True for a strip that only takes as much width as its labels need
  /// (scrolls if it overflows) — false to stretch tabs evenly across the
  /// available width.
  final bool scrollable;

  const GlassTabStrip({
    super.key,
    required this.controller,
    required this.labels,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tabs = [
          for (var i = 0; i < labels.length; i++)
            _GlassTab(
              label: labels[i],
              selected: controller.index == i,
              onTap: () => controller.animateTo(i),
            ),
        ];
        return Container(
          decoration: BoxDecoration(
            color: KotiTheme.of(context).pillBackground,
            borderRadius: BorderRadius.circular(9999),
          ),
          padding: const EdgeInsets.all(5),
          child: scrollable
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: tabs),
                )
              : Row(children: [for (final t in tabs) Expanded(child: t)]),
        );
      },
    );
  }
}

class _GlassTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GlassTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? KotiTheme.of(context).pillSelectedBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}
