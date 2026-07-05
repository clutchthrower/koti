import 'dart:async';
import 'package:flutter/material.dart';

/// Simplified port of `hemma-smart-row.js`. Full pixel-perfect FLIP
/// transforms are a web-DOM technique; Flutter's implicit animations give an
/// equivalent smooth reorder via [AnimatedSwitcher]-style item repositioning
/// without needing manual getBoundingClientRect math.
///
/// Behavior preserved from the original:
/// - active items sort first, ties broken by activation order (FIFO)
/// - a [holdDuration] (default 2500ms) prevents flicker from transient
///   states like motion sensors before the sort re-evaluates
/// - sorting can be disabled entirely (mobile portrait/landscape, or via the
///   `Enable Smart Row Sorting` setting)
class SmartRow<T> extends StatefulWidget {
  final List<T> items;
  final bool Function(T item) isActive;
  final Widget Function(BuildContext context, T item, int position) itemBuilder;
  final bool sortingEnabled;
  final Duration holdDuration;
  final Axis direction;

  /// Scroll padding (horizontal rows only) — keeps the page gutter inside
  /// the scroll view so cards scroll all the way to the screen edge.
  final EdgeInsetsGeometry? padding;

  const SmartRow({
    super.key,
    required this.items,
    required this.isActive,
    required this.itemBuilder,
    this.sortingEnabled = true,
    this.holdDuration = const Duration(milliseconds: 2500),
    this.direction = Axis.horizontal,
    this.padding,
  });

  @override
  State<SmartRow<T>> createState() => _SmartRowState<T>();
}

class _SmartRowState<T> extends State<SmartRow<T>> {
  late List<T> _order;
  final List<T> _activationOrder = [];
  Timer? _resortTimer;

  @override
  void initState() {
    super.initState();
    _order = List.of(widget.items);
    _resort(immediate: true);
  }

  @override
  void didUpdateWidget(covariant SmartRow<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      for (final item in widget.items) {
        if (!_order.contains(item)) _order.add(item);
      }
      _order.removeWhere((item) => !widget.items.contains(item));
      _scheduleResort();
    }
  }

  void _scheduleResort() {
    _resortTimer?.cancel();
    _resortTimer = Timer(widget.holdDuration, _resort);
  }

  void _resort({bool immediate = false}) {
    if (!widget.sortingEnabled) {
      setState(() => _order = List.of(widget.items));
      return;
    }
    for (final item in widget.items) {
      if (widget.isActive(item) && !_activationOrder.contains(item)) {
        _activationOrder.add(item);
      } else if (!widget.isActive(item)) {
        _activationOrder.remove(item);
      }
    }
    final active = _activationOrder.where(widget.items.contains).toList();
    final inactive = widget.items.where((i) => !active.contains(i)).toList();
    setState(() => _order = [...active, ...inactive]);
  }

  @override
  void dispose() {
    _resortTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      for (var i = 0; i < _order.length; i++)
        AnimatedContainer(
          key: ValueKey(_order[i]),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: widget.itemBuilder(context, _order[i], i),
        ),
    ];

    return widget.direction == Axis.horizontal
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            child: Row(children: children),
          )
        : Column(children: children);
  }
}
