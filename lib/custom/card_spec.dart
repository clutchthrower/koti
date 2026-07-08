import 'dart:convert';

/// A user-authored card design: plain JSON data interpreted by
/// `CustomCard` — never code. The full format is documented in
/// docs/CARD_FORMAT.md; example cards live in cards/examples/.
///
/// Sharing model: this JSON *is* the card. Export = copy it, import =
/// paste it, and the importer just picks their own device in the card
/// editor (the picked entity overrides the spec's `entity`).
class CustomCardSpec {
  /// Icon names bundled in assets/icons/ — anything else falls back to
  /// [fallbackIcon] at render time (icons never load over the network).
  static const knownIcons = {
    'access_point', 'apple', 'apple_tv', 'aqi-high', 'aqi-low', 'aqi-medium',
    'arrow-down', 'arrow-up', 'battery', 'bedroom', 'clock', 'close',
    'console', 'cooling', 'curtain-closed', 'curtain-open', 'decrease',
    'doorbell', 'door_open', 'door', 'electric', 'energy', 'fan', 'fridge',
    'gas', 'heating', 'homepod', 'home', 'hot_water', 'humidifier-on',
    'humidifier', 'humidity', 'increase', 'kitchen', 'lamp', 'light',
    'living-room', 'lock-open', 'lock', 'lock-unlocking', 'media', 'menu',
    'motion', 'music', 'mute', 'pause', 'pendant-light', 'pendent', 'person',
    'plant', 'play-next', 'play', 'plex', 'plug', 'power_off', 'power_on',
    'purifier', 'scenes', 'skip_next', 'skip_previous', 'sony', 'speaker',
    'temp-high', 'temp-low', 'temp-medium', 'thermostat', 'tv-play', 'tv',
    'unmute', 'updates', 'vacuum-charge', 'vacuum-clean', 'vacuum', 'wifi',
  };

  static const fallbackIcon = 'home';

  static const blockTypes = {
    'text', 'icon', 'row', 'gap', 'divider', 'progress', 'button', 'buttons',
    'toggle', 'slider', 'entity',
  };

  static const actionTypes = {'none', 'toggle', 'service', 'popup'};

  final String name; // template
  final String icon;
  final String? entity;
  final String stateText; // template for the card's second line
  final String? activeWhen; // condition -> highlights the card
  final String? progressValue; // value path, 0..progressMax
  final double progressMax;
  final Map<String, dynamic>? tap; // action; default: popup if any, else none
  final Map<String, dynamic>? quick; // {icon, action} corner quick-action
  final List<Map<String, dynamic>> face; // optional free-form card face
  final List<Map<String, dynamic>> popup; // popup blocks

  /// `"stack"` (default): popup blocks lay out top-to-bottom, `row` blocks
  /// group children side-by-side. `"canvas"`: every block carries its own
  /// `x`/`y`/`w`/`h` (0..1 fractions of [canvasWidth]x[canvasHeight]) and is
  /// placed freely, like a design-tool canvas — built for cards exported by
  /// the web card builder (see docs/CARD_FORMAT.md).
  final String popupLayout;
  final double canvasWidth;
  final double canvasHeight;

  const CustomCardSpec({
    this.name = '{name}',
    this.icon = fallbackIcon,
    this.entity,
    this.stateText = '{state|title}',
    this.activeWhen,
    this.progressValue,
    this.progressMax = 100,
    this.tap,
    this.quick,
    this.face = const [],
    this.popup = const [],
    this.popupLayout = 'stack',
    this.canvasWidth = 360,
    this.canvasHeight = 480,
  });

  static List<Map<String, dynamic>> _blockList(dynamic raw) =>
      (raw as List? ?? const [])
          .whereType<Map>()
          .map((b) => b.cast<String, dynamic>())
          .toList();

  factory CustomCardSpec.fromJson(Map<String, dynamic> json) => CustomCardSpec(
        name: json['name'] as String? ?? '{name}',
        icon: json['icon'] as String? ?? fallbackIcon,
        entity: json['entity'] as String?,
        stateText: json['state'] as String? ?? '{state|title}',
        activeWhen: json['activeWhen'] as String?,
        progressValue: (json['progress'] is Map)
            ? (json['progress'] as Map)['value'] as String?
            : json['progress'] as String?,
        progressMax: (json['progress'] is Map)
            ? ((json['progress'] as Map)['max'] as num?)?.toDouble() ?? 100
            : 100,
        tap: (json['tap'] as Map?)?.cast<String, dynamic>(),
        quick: (json['quick'] as Map?)?.cast<String, dynamic>(),
        face: _blockList(json['blocks']),
        popup: _blockList(json['popup']),
        popupLayout: json['popupLayout'] as String? ?? 'stack',
        canvasWidth: _canvasDim(json['canvasSize'], 0, 360),
        canvasHeight: _canvasDim(json['canvasSize'], 1, 480),
      );

  static double _canvasDim(dynamic raw, int index, double fallback) {
    if (raw is! List || raw.length <= index) return fallback;
    return (raw[index] as num?)?.toDouble() ?? fallback;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'icon': icon,
        if (entity != null) 'entity': entity,
        'state': stateText,
        if (activeWhen != null) 'activeWhen': activeWhen,
        if (progressValue != null)
          'progress': progressMax == 100
              ? progressValue
              : {'value': progressValue, 'max': progressMax},
        if (tap != null) 'tap': tap,
        if (quick != null) 'quick': quick,
        if (face.isNotEmpty) 'blocks': face,
        if (popup.isNotEmpty) 'popup': popup,
        if (popupLayout != 'stack') 'popupLayout': popupLayout,
        if (popupLayout == 'canvas') 'canvasSize': [canvasWidth, canvasHeight],
      };

  /// Parses editor/import text. Throws [FormatException] with a message
  /// fit for showing under the editor field.
  static CustomCardSpec parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('The card must be a JSON object: { ... }');
    }
    return CustomCardSpec.fromJson(decoded.cast<String, dynamic>());
  }

  /// Non-fatal issues (unknown icon/block/action names) — the renderer
  /// falls back gracefully, but the editor shows these so shared cards
  /// don't silently degrade.
  List<String> validate() {
    final warnings = <String>[];
    if (!knownIcons.contains(icon)) {
      warnings.add('Unknown icon "$icon" (using "$fallbackIcon" instead)');
    }

    void checkAction(Map<String, dynamic>? action, String where) {
      if (action == null) return;
      final type = action['action'];
      if (!actionTypes.contains(type)) {
        warnings.add('Unknown action "$type" in $where');
      } else if (type == 'service' &&
          !(action['service'] as String? ?? '').contains('.')) {
        warnings.add('Service in $where must be "domain.service"');
      }
    }

    void checkBlocks(List<Map<String, dynamic>> blocks, String where) {
      for (final block in blocks) {
        final type = block['type'];
        if (!blockTypes.contains(type)) {
          warnings.add('Unknown block type "$type" in $where');
          continue;
        }
        checkAction(
            (block['action'] as Map?)?.cast<String, dynamic>(), '$where/$type');
        if (type == 'row') checkBlocks(_blockList(block['blocks']), where);
        if (type == 'buttons') {
          for (final b in _blockList(block['buttons'])) {
            checkAction((b['action'] as Map?)?.cast<String, dynamic>(),
                '$where/buttons');
          }
        }
        if (type == 'slider' &&
            !(block['service'] as String? ?? '').contains('.')) {
          warnings.add('Slider in $where needs "service": "domain.service"');
        }
      }
    }

    checkAction(tap, 'tap');
    checkAction((quick?['action'] as Map?)?.cast<String, dynamic>(), 'quick');
    checkBlocks(face, 'blocks');
    checkBlocks(popup, 'popup');

    if (popupLayout == 'canvas') {
      for (final block in popup) {
        if (block['x'] == null || block['y'] == null) {
          warnings.add(
              'Block "${block['type']}" in popup has no x/y position (canvas layout) — it will render at the top-left corner');
        }
      }
    } else if (popup.any((b) => b['x'] != null || b['y'] != null)) {
      warnings.add(
          'Blocks have x/y positions but popupLayout isn\'t "canvas" — positions will be ignored');
    }
    return warnings;
  }

  String toPrettyJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  /// A working starting point for the editor, shaped by the picked
  /// entity's domain so the first save already does something sensible.
  static String starterFor(String? entityId) {
    final domain = entityId?.split('.').first;
    final icon = _domainIcons[domain] ?? fallbackIcon;
    final togglable = const {
      'light', 'switch', 'fan', 'input_boolean', 'humidifier', 'media_player',
    }.contains(domain);

    final spec = {
      'name': '{name}',
      'icon': icon,
      'state': '{state|title}',
      if (togglable) 'activeWhen': "state == 'on'",
      'tap': {'action': 'popup'},
      if (togglable)
        'quick': {
          'icon': 'power_on',
          'action': {'action': 'toggle'},
        },
      'popup': [
        // No explicit entity: the block follows the card's picked device,
        // so the starter stays shareable as-is.
        {'type': 'entity'},
        {'type': 'divider'},
        if (togglable)
          {'type': 'toggle', 'label': 'Power'}
        else
          {'type': 'text', 'text': 'State: {state}'},
        {
          'type': 'buttons',
          'buttons': [
            {
              'text': 'Turn on',
              'action': {'action': 'service', 'service': 'homeassistant.turn_on'},
            },
            {
              'text': 'Turn off',
              'action': {'action': 'service', 'service': 'homeassistant.turn_off'},
            },
          ],
        },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(spec);
  }

  static const _domainIcons = {
    'light': 'light',
    'switch': 'power_on',
    'fan': 'fan',
    'sensor': 'temp-medium',
    'binary_sensor': 'motion',
    'media_player': 'speaker',
    'lock': 'lock',
    'vacuum': 'vacuum',
    'climate': 'thermostat',
    'cover': 'curtain-open',
    'person': 'person',
    'plant': 'plant',
    'humidifier': 'humidifier',
    'camera': 'doorbell',
    'script': 'scenes',
    'scene': 'scenes',
    'automation': 'scenes',
    'input_boolean': 'power_on',
  };

  /// Icon for the `entity` block when none is given.
  static String iconForDomain(String? domain) =>
      _domainIcons[domain] ?? fallbackIcon;
}
