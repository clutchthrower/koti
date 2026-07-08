import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cards/base_entity_card.dart';
import '../models/entity_state.dart';
import '../popups/popup_base.dart';
import '../store/state_store.dart';
import '../theme/koti_theme.dart';
import '../theme/tokens.dart';
import '../widgets/entity_watcher.dart';
import '../widgets/koti_icon.dart';
import 'card_spec.dart';
import 'template_engine.dart';

/// Renders a [CustomCardSpec] — a user-authored JSON card design — from
/// the same vanilla pieces every built-in card uses. Interpreting the
/// small block tree costs nothing at runtime; like every card it only
/// rebuilds when one of its bound entities changes.
class CustomCard extends StatelessWidget {
  final CustomCardSpec spec;

  /// Entity picked in the card editor; overrides the spec's own `entity`
  /// so shared cards work on the importer's devices.
  final String? entityOverride;
  final String? labelOverride;
  final int position;

  const CustomCard({
    super.key,
    required this.spec,
    this.entityOverride,
    this.labelOverride,
    this.position = 0,
  });

  String? get _defaultEntity =>
      (entityOverride?.isNotEmpty ?? false) ? entityOverride : spec.entity;

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<StateStore>(context, listen: false);
    final watchIds =
        extractEntityIds(spec.toJson(), defaultEntityId: _defaultEntity)
            .toList();

    return EntityWatcher(
      entityIds: watchIds,
      builder: (context, states) {
        final scope = TemplateScope(
          defaultEntityId: _defaultEntity,
          lookup: (id) => states[id] ?? store.get(id),
        );

        final label = labelOverride ?? renderTemplate(spec.name, scope);
        final tap = spec.tap ??
            (spec.popup.isNotEmpty ? const {'action': 'popup'} : null);
        final onTap =
            buildAction(context, tap, spec: spec, defaultEntity: _defaultEntity, title: label);

        if (spec.face.isNotEmpty) {
          return _FreeFormFace(
            spec: spec,
            scope: scope,
            defaultEntity: _defaultEntity,
            active: evalCondition(spec.activeWhen, scope),
            onTap: onTap,
          );
        }

        final progress = resolveNumber(spec.progressValue, scope);
        return KotiEntityCard(
          iconName: CustomCardSpec.knownIcons.contains(spec.icon)
              ? spec.icon
              : CustomCardSpec.fallbackIcon,
          label: label,
          stateText: renderTemplate(spec.stateText, scope),
          active: evalCondition(spec.activeWhen, scope),
          position: position,
          progress: progress == null
              ? null
              : (progress / spec.progressMax).clamp(0.0, 1.0),
          onTap: onTap,
          trailing: spec.quick == null
              ? null
              : _QuickActionButton(
                  spec: spec, defaultEntity: _defaultEntity, title: label),
        );
      },
    );
  }
}

/// Turns an action map into a tap callback (null = not tappable).
/// Actions: none | toggle | service | popup — see docs/CARD_FORMAT.md.
VoidCallback? buildAction(
  BuildContext context,
  Map<String, dynamic>? action, {
  required CustomCardSpec spec,
  required String? defaultEntity,
  required String title,
}) {
  if (action == null) return null;
  final store = Provider.of<StateStore>(context, listen: false);
  final entity = action['entity'] as String? ?? defaultEntity;

  switch (action['action']) {
    case 'toggle':
      if (entity == null) return null;
      return () =>
          store.callService('homeassistant', 'toggle', entityId: entity);
    case 'service':
      final service = action['service'] as String? ?? '';
      final dot = service.indexOf('.');
      if (dot <= 0) return null;
      final data = (action['data'] as Map?)?.cast<String, dynamic>();
      return () => store.callService(
            service.substring(0, dot),
            service.substring(dot + 1),
            entityId: data?.containsKey('entity_id') ?? false ? null : entity,
            data: data,
          );
    case 'popup':
      return () => showCustomCardPopup(context,
          spec: spec, defaultEntity: defaultEntity, title: title);
  }
  return null;
}

Future<void> showCustomCardPopup(
  BuildContext context, {
  required CustomCardSpec spec,
  required String? defaultEntity,
  required String title,
}) {
  // An empty popup still shows something useful: the entity itself.
  final blocks = spec.popup.isNotEmpty
      ? spec.popup
      : [
          {'type': 'entity'}
        ];
  return showKotiPopup(
    context,
    title: title,
    builder: (context) => CustomBlocks(
      blocks: blocks,
      spec: spec,
      defaultEntity: defaultEntity,
      title: title,
      canvas: spec.popupLayout == 'canvas' && spec.popup.isNotEmpty,
      canvasSize: Size(spec.canvasWidth, spec.canvasHeight),
    ),
  );
}

/// A free-form card face: same shell as [KotiEntityCard] (specular
/// border, active overlay, radius) with user blocks inside. Content that
/// doesn't fit the tile clips cleanly instead of erroring.
class _FreeFormFace extends StatelessWidget {
  final CustomCardSpec spec;
  final TemplateScope scope;
  final String? defaultEntity;
  final bool active;
  final VoidCallback? onTap;

  const _FreeFormFace({
    required this.spec,
    required this.scope,
    required this.defaultEntity,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          gradient: tokens.borderGradient,
        ),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.cardRadius - 1),
            color: active
                ? Color.alphaBlend(
                    tokens.entityBackgroundActive, tokens.entityBackground)
                : tokens.entityBackground,
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: CustomBlocks(
              blocks: spec.face,
              spec: spec,
              defaultEntity: defaultEntity,
              title: renderTemplate(spec.name, scope),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final CustomCardSpec spec;
  final String? defaultEntity;
  final String title;

  const _QuickActionButton(
      {required this.spec, required this.defaultEntity, required this.title});

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final quick = spec.quick!;
    final iconName = quick['icon'] as String? ?? 'power_on';
    final onTap = buildAction(
      context,
      (quick['action'] as Map?)?.cast<String, dynamic>(),
      spec: spec,
      defaultEntity: defaultEntity,
      title: title,
    );
    return IconButton(
      onPressed: onTap,
      icon: KotiIcon(
        CustomCardSpec.knownIcons.contains(iconName)
            ? iconName
            : CustomCardSpec.fallbackIcon,
        size: 20,
        color: tokens.textPrimary,
      ),
    );
  }
}

/// Renders a block list. Used for both free-form card faces and popups;
/// watches every entity the blocks reference so popups update live too.
class CustomBlocks extends StatelessWidget {
  final List<Map<String, dynamic>> blocks;
  final CustomCardSpec spec;
  final String? defaultEntity;
  final String title;

  /// Canvas layout: every block carries its own `x`/`y`/`w`/`h` (0..1
  /// fractions of [canvasSize]) and is placed freely via [Positioned]
  /// instead of stacking top-to-bottom — see [CustomCardSpec.popupLayout].
  final bool canvas;
  final Size canvasSize;

  const CustomBlocks({
    super.key,
    required this.blocks,
    required this.spec,
    required this.defaultEntity,
    required this.title,
    this.canvas = false,
    this.canvasSize = const Size(360, 480),
  });

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<StateStore>(context, listen: false);
    final watchIds =
        extractEntityIds(blocks, defaultEntityId: defaultEntity).toList();

    return EntityWatcher(
      entityIds: watchIds,
      builder: (context, states) {
        final scope = TemplateScope(
          defaultEntityId: defaultEntity,
          lookup: (id) => states[id] ?? store.get(id),
        );
        if (canvas) {
          return AspectRatio(
            aspectRatio: canvasSize.width / canvasSize.height,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  for (final block in blocks)
                    _positionedBlock(context, block, scope, constraints),
                ],
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final block in blocks) _buildBlock(context, block, scope),
          ],
        );
      },
    );
  }

  Widget _positionedBlock(BuildContext context, Map<String, dynamic> block,
      TemplateScope scope, BoxConstraints constraints) {
    final x = (block['x'] as num?)?.toDouble() ?? 0.0;
    final y = (block['y'] as num?)?.toDouble() ?? 0.0;
    // Always resolve a concrete width/height (never leave Positioned
    // unconstrained) — some blocks (e.g. text) size themselves to fill,
    // which needs bounded constraints from the Stack or it throws.
    final w = (block['w'] as num?)?.toDouble() ?? (1.0 - x).clamp(0.05, 1.0);
    final h = (block['h'] as num?)?.toDouble() ?? 0.12;
    return Positioned(
      left: x * constraints.maxWidth,
      top: y * constraints.maxHeight,
      width: w * constraints.maxWidth,
      height: h * constraints.maxHeight,
      child: _buildBlock(context, block, scope),
    );
  }

  Widget _buildBlock(
      BuildContext context, Map<String, dynamic> block, TemplateScope scope) {
    final showWhen = block['showWhen'] as String?;
    if (showWhen != null && !evalCondition(showWhen, scope)) {
      return const SizedBox.shrink();
    }

    final tokens = KotiTheme.of(context);
    switch (block['type']) {
      case 'text':
        return _textBlock(block, scope, tokens);
      case 'icon':
        return _iconBlock(block, scope, tokens);
      case 'row':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final b in (block['blocks'] as List? ?? const [])
                  .whereType<Map>()
                  .map((b) => b.cast<String, dynamic>()))
                _buildBlock(context, b, scope),
            ],
          ),
        );
      case 'gap':
        return SizedBox(height: (block['height'] as num?)?.toDouble() ?? 8);
      case 'divider':
        return Divider(color: tokens.textSecondary.withValues(alpha: 0.25));
      case 'progress':
        final value = resolveNumber(block['value'] as String?, scope);
        final max = (block['max'] as num?)?.toDouble() ?? 100;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value == null ? 0 : (value / max).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: tokens.iconCircleBackground,
              color: tokens.activeColor,
            ),
          ),
        );
      case 'button':
        return _buttonBlock(context, block, scope);
      case 'buttons':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in (block['buttons'] as List? ?? const [])
                  .whereType<Map>()
                  .map((b) => b.cast<String, dynamic>()))
                _buttonBlock(context, b, scope),
            ],
          ),
        );
      case 'toggle':
        return _ToggleBlock(
            block: block, defaultEntity: defaultEntity, scope: scope);
      case 'slider':
        return _SliderBlock(
            block: block, defaultEntity: defaultEntity, scope: scope);
      case 'entity':
        return _entityBlock(context, block, scope, tokens);
    }
    return Text(
      'Unknown block: ${block['type']}',
      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
    );
  }

  Widget _textBlock(
      Map<String, dynamic> block, TemplateScope scope, KotiTokens tokens) {
    final (size, weight) = switch (block['size'] as String?) {
      'small' => (12.0, FontWeight.w500),
      'large' => (18.0, FontWeight.w600),
      'title' => (22.0, FontWeight.w700),
      _ => (14.0, FontWeight.w500),
    };
    final color = switch (block['color'] as String?) {
      'active' => tokens.activeColor,
      'secondary' => tokens.textSecondary,
      final String hex when hex.startsWith('#') && hex.length == 7 =>
        Color(0xFF000000 | int.parse(hex.substring(1), radix: 16)),
      _ => (block['size'] == 'small') ? tokens.textSecondary : tokens.textPrimary,
    };
    final align = switch (block['align'] as String?) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          renderTemplate(block['text'] as String? ?? '', scope),
          textAlign: align,
          style: TextStyle(
            fontFamily: 'Hanken Grotesk',
            fontSize: size,
            fontWeight: weight,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _iconBlock(
      Map<String, dynamic> block, TemplateScope scope, KotiTokens tokens) {
    var iconName = block['icon'] as String? ?? CustomCardSpec.fallbackIcon;
    if (!CustomCardSpec.knownIcons.contains(iconName)) {
      iconName = CustomCardSpec.fallbackIcon;
    }
    final active = evalCondition(block['activeWhen'] as String?, scope);
    final size = (block['size'] as num?)?.toDouble() ?? 44;
    if (block['circle'] == false) {
      return KotiIcon(iconName,
          size: size * 0.59,
          color: active ? tokens.activeColor : tokens.textPrimary);
    }
    return KotiIconCircle(
      iconName: iconName,
      iconColor: active ? tokens.activeColor : tokens.textPrimary,
      backgroundColor: tokens.iconCircleBackground,
      diameter: size,
    );
  }

  Widget _buttonBlock(
      BuildContext context, Map<String, dynamic> block, TemplateScope scope) {
    final tokens = KotiTheme.of(context);
    final onTap = buildAction(
      context,
      (block['action'] as Map?)?.cast<String, dynamic>(),
      spec: spec,
      defaultEntity: defaultEntity,
      title: title,
    );
    final text = block['text'] as String?;
    final iconName = block['icon'] as String?;
    final icon = iconName == null
        ? null
        : KotiIcon(
            CustomCardSpec.knownIcons.contains(iconName)
                ? iconName
                : CustomCardSpec.fallbackIcon,
            size: 18,
            color: tokens.textPrimary,
          );
    final filled = block['style'] == 'filled';

    if (text == null && icon != null) {
      return IconButton.outlined(onPressed: onTap, icon: icon);
    }
    final label = Text(renderTemplate(text ?? '', scope));
    if (icon != null) {
      return filled
          ? FilledButton.icon(onPressed: onTap, icon: icon, label: label)
          : OutlinedButton.icon(onPressed: onTap, icon: icon, label: label);
    }
    return filled
        ? FilledButton(onPressed: onTap, child: label)
        : OutlinedButton(onPressed: onTap, child: label);
  }

  Widget _entityBlock(BuildContext context, Map<String, dynamic> block,
      TemplateScope scope, KotiTokens tokens) {
    final entityId = block['entity'] as String? ?? defaultEntity;
    final entity = entityId == null ? null : scope.lookup(entityId);
    var iconName = block['icon'] as String? ??
        CustomCardSpec.iconForDomain(entityId?.split('.').first);
    if (!CustomCardSpec.knownIcons.contains(iconName)) {
      iconName = CustomCardSpec.fallbackIcon;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          KotiIconCircle(
            iconName: iconName,
            iconColor: tokens.textPrimary,
            backgroundColor: tokens.iconCircleBackground,
            diameter: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entity?.attr<String>('friendly_name', entityId ?? '?') ??
                      entityId ??
                      'No entity',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Hanken Grotesk',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: tokens.textPrimary),
                ),
                Text(
                  entity == null
                      ? 'Unavailable'
                      : renderTemplate('{state|title}',
                          TemplateScope(defaultEntityId: entityId, lookup: scope.lookup)),
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final String? defaultEntity;
  final TemplateScope scope;

  const _ToggleBlock(
      {required this.block, required this.defaultEntity, required this.scope});

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final store = Provider.of<StateStore>(context, listen: false);
    final entityId = block['entity'] as String? ?? defaultEntity;
    final EntityState? entity = entityId == null ? null : scope.lookup(entityId);
    final label = block['label'] as String? ??
        entity?.attr<String>('friendly_name', entityId ?? '') ??
        entityId ??
        '';
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(renderTemplate(label, scope),
          style: TextStyle(color: tokens.textPrimary, fontSize: 14)),
      value: entity?.state == 'on',
      onChanged: entityId == null
          ? null
          : (_) =>
              store.callService('homeassistant', 'toggle', entityId: entityId),
    );
  }
}

class _SliderBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final String? defaultEntity;
  final TemplateScope scope;

  const _SliderBlock(
      {required this.block, required this.defaultEntity, required this.scope});

  @override
  State<_SliderBlock> createState() => _SliderBlockState();
}

class _SliderBlockState extends State<_SliderBlock> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final tokens = KotiTheme.of(context);
    final store = Provider.of<StateStore>(context, listen: false);
    final block = widget.block;

    final min = (block['min'] as num?)?.toDouble() ?? 0;
    final max = (block['max'] as num?)?.toDouble() ?? 100;
    final step = (block['step'] as num?)?.toDouble();
    final current =
        (resolveNumber(block['value'] as String?, widget.scope) ?? min)
            .clamp(min, max);
    final value = (_dragValue ?? current).clamp(min, max);

    final service = block['service'] as String? ?? '';
    final dot = service.indexOf('.');
    final field = block['field'] as String?;
    final entityId = block['entity'] as String? ?? widget.defaultEntity;
    final usable = dot > 0 && field != null && entityId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block['label'] != null)
          Text(renderTemplate(block['label'] as String, widget.scope),
              style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions:
              step != null && step > 0 ? ((max - min) / step).round() : null,
          label: value.toStringAsFixed(0),
          onChanged: usable ? (v) => setState(() => _dragValue = v) : null,
          onChangeEnd: !usable
              ? null
              : (v) {
                  final data = {
                    ...?(block['data'] as Map?)?.cast<String, dynamic>(),
                    field: v == v.roundToDouble() ? v.round() : v,
                  };
                  store.callService(
                    service.substring(0, dot),
                    service.substring(dot + 1),
                    entityId: entityId,
                    data: data,
                  );
                  setState(() => _dragValue = null);
                },
        ),
      ],
    );
  }
}
