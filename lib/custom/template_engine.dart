import '../models/entity_state.dart';

/// Tiny template + condition language for custom cards (docs/CARD_FORMAT.md).
///
/// Templates: text with `{...}` tokens —
///   `{state}` `{name}` `{entity_id}` `{attributes.brightness}` on the
///   card's own entity, or `{sensor.kitchen_temp.state}` /
///   `{sensor.kitchen_temp.attributes.unit_of_measurement}` cross-entity.
///   A bare entity token (`{sensor.kitchen_temp}`) means its state.
///   Optional filters after `|`: round, round1, upper, lower, title.
///
/// Conditions (`activeWhen` / `showWhen`): `lhs op rhs` with
///   == != > < >= <= contains, where each side is a path, a 'quoted'
///   string, or a number. A bare path is truthy for on-like states.
///
/// This is a string interpreter on purpose: no scripting engine, nothing
/// executable can be smuggled in via a shared card file.
typedef EntityLookup = EntityState? Function(String entityId);

class TemplateScope {
  final String? defaultEntityId;
  final EntityLookup lookup;

  const TemplateScope({this.defaultEntityId, required this.lookup});
}

/// Path roots that refer to the card's own entity rather than naming
/// another one (`attributes.x` must not be read as entity `attributes.x`).
const _reservedRoots = {'state', 'name', 'entity_id', 'attributes', 'attr'};

/// States that count as "truthy"/active when a condition is a bare path.
const _truthyStates = {
  'on', 'true', 'yes', 'home', 'open', 'opening', 'playing', 'unlocked',
  'heat', 'cool', 'heating', 'cooling', 'drying', 'cleaning', 'running',
  'active', 'detected', 'occupied', 'wet', 'motion', 'charging',
};

final _tokenPattern = RegExp(r'\{([^{}]+)\}');

/// Looks up a dotted path against the scope. Returns null when the entity
/// or attribute doesn't exist (rendered as an em dash in templates).
dynamic resolvePath(String token, TemplateScope scope) {
  var parts = token.trim().split('.');
  if (parts.isEmpty || parts.first.isEmpty) return null;

  String? entityId;
  if (parts.length >= 2 && !_reservedRoots.contains(parts.first)) {
    entityId = '${parts[0]}.${parts[1]}';
    parts = parts.sublist(2);
    if (parts.isEmpty) parts = ['state'];
  }
  entityId ??= scope.defaultEntityId;
  if (entityId == null) return null;
  final entity = scope.lookup(entityId);
  if (entity == null) return null;

  switch (parts.first) {
    case 'state':
      return entity.state;
    case 'name':
      return entity.attr<String>('friendly_name', entity.entityId);
    case 'entity_id':
      return entity.entityId;
    case 'attributes':
    case 'attr':
      dynamic value = entity.attributes;
      for (final key in parts.sublist(1)) {
        if (value is Map) {
          value = value[key];
        } else {
          return null;
        }
      }
      return value;
  }
  return null;
}

String _formatValue(dynamic value) {
  if (value == null) return '—';
  if (value is num) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }
  return value.toString();
}

String _applyFilter(String value, String filter) {
  switch (filter.trim()) {
    case 'round':
      final n = num.tryParse(value);
      return n == null ? value : n.round().toString();
    case 'round1':
      final n = num.tryParse(value);
      return n == null ? value : n.toStringAsFixed(1);
    case 'upper':
      return value.toUpperCase();
    case 'lower':
      return value.toLowerCase();
    case 'title':
      return value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
  }
  return value;
}

String renderTemplate(String template, TemplateScope scope) {
  return template.replaceAllMapped(_tokenPattern, (m) {
    final pieces = m.group(1)!.split('|');
    var text = _formatValue(resolvePath(pieces.first, scope));
    for (final filter in pieces.sublist(1)) {
      text = _applyFilter(text, filter);
    }
    return text;
  });
}

dynamic _resolveOperand(String raw, TemplateScope scope) {
  final s = raw.trim();
  if (s.length >= 2 &&
      ((s.startsWith("'") && s.endsWith("'")) ||
          (s.startsWith('"') && s.endsWith('"')))) {
    return s.substring(1, s.length - 1);
  }
  final n = num.tryParse(s);
  if (n != null) return n;
  return resolvePath(s, scope);
}

bool _isTruthy(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return _truthyStates.contains(value.toString().toLowerCase());
}

bool evalCondition(String? expr, TemplateScope scope) {
  if (expr == null || expr.trim().isEmpty) return false;

  if (expr.contains(' contains ')) {
    final idx = expr.indexOf(' contains ');
    final lhs = _resolveOperand(expr.substring(0, idx), scope);
    final rhs = _resolveOperand(expr.substring(idx + 10), scope);
    if (lhs == null || rhs == null) return false;
    return lhs.toString().contains(rhs.toString());
  }

  // Earliest operator wins; prefer the longer form on ties so '>=' isn't
  // read as '>'.
  String? op;
  var opIndex = -1;
  for (final candidate in const ['==', '!=', '>=', '<=', '>', '<']) {
    final idx = expr.indexOf(candidate);
    if (idx < 0) continue;
    if (opIndex == -1 || idx < opIndex ||
        (idx == opIndex && candidate.length > op!.length)) {
      op = candidate;
      opIndex = idx;
    }
  }

  if (op == null) return _isTruthy(_resolveOperand(expr, scope));

  final lhs = _resolveOperand(expr.substring(0, opIndex), scope);
  final rhs = _resolveOperand(expr.substring(opIndex + op.length), scope);

  final lNum = lhs is num ? lhs : num.tryParse(lhs?.toString() ?? '');
  final rNum = rhs is num ? rhs : num.tryParse(rhs?.toString() ?? '');

  switch (op) {
    case '==':
      if (lNum != null && rNum != null) return lNum == rNum;
      return lhs?.toString() == rhs?.toString();
    case '!=':
      if (lNum != null && rNum != null) return lNum != rNum;
      return lhs?.toString() != rhs?.toString();
    case '>=':
      return lNum != null && rNum != null && lNum >= rNum;
    case '<=':
      return lNum != null && rNum != null && lNum <= rNum;
    case '>':
      return lNum != null && rNum != null && lNum > rNum;
    case '<':
      return lNum != null && rNum != null && lNum < rNum;
  }
  return false;
}

/// Resolves a value path (or a literal number) to a double — used by
/// progress bars and sliders.
double? resolveNumber(String? token, TemplateScope scope) {
  if (token == null || token.trim().isEmpty) return null;
  final literal = double.tryParse(token.trim());
  if (literal != null) return literal;
  final value = resolvePath(token, scope);
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

final _entityRefPattern = RegExp(r'\{\s*([a-z_][a-z0-9_]*\.[a-z0-9_]+)');

/// Walks a decoded spec and collects every entity the card reads or
/// controls, so the card can subscribe to exactly those (atomic repaints).
Set<String> extractEntityIds(Object? node, {String? defaultEntityId}) {
  final ids = <String>{if (defaultEntityId != null) defaultEntityId};

  void walk(Object? n) {
    if (n is String) {
      for (final m in _entityRefPattern.allMatches(n)) {
        final ref = m.group(1)!;
        if (!_reservedRoots.contains(ref.split('.').first)) ids.add(ref);
      }
    } else if (n is Map) {
      final entity = n['entity'];
      if (entity is String && entity.contains('.')) ids.add(entity);
      n.values.forEach(walk);
    } else if (n is List) {
      n.forEach(walk);
    }
  }

  walk(node);
  return ids;
}
