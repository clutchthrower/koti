import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/entity_state.dart';
import '../store/state_store.dart';

/// Searchable picker over live entities from [StateStore], optionally
/// filtered by domain and/or `device_class`. Used throughout Room settings
/// so users select entities from what HA actually reports instead of typing
/// entity IDs by hand.
class EntityPickerField extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final List<String>? domains;
  final List<String>? deviceClasses;
  final bool allowClear;
  /// Hides `unavailable`/`unknown` entities — useful when picking "the one
  /// live entity that represents this device" (e.g. a speaker's own player
  /// entity), where a stale/orphaned duplicate would otherwise be an easy
  /// mistake to pick. Leave false (the default) for pickers where an
  /// entity being temporarily offline shouldn't hide it, e.g. wiring up a
  /// room's sensor.
  final bool excludeUnavailable;

  const EntityPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.domains,
    this.deviceClasses,
    this.allowClear = true,
    this.excludeUnavailable = false,
  });

  List<EntityState> _filtered(StateStore store) {
    return store.all.values.where((e) {
      if (domains != null && !domains!.contains(e.domain)) return false;
      if (deviceClasses != null &&
          !deviceClasses!.contains(e.attr<String>('device_class', ''))) {
        return false;
      }
      if (excludeUnavailable && (e.state == 'unavailable' || e.state == 'unknown')) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.attr<String>('friendly_name', a.entityId)
          .compareTo(b.attr<String>('friendly_name', b.entityId)));
  }

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<StateStore>(context, listen: false);
    final entity = value != null ? store.get(value!) : null;
    final displayText = entity?.attr<String>('friendly_name', value!) ?? value ?? '';

    return InkWell(
      onTap: () => _openPicker(context, store),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: allowClear && value != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          displayText.isEmpty ? 'Not set' : displayText,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, StateStore store) async {
    final options = _filtered(store);
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EntityPickerSheet(label: label, options: options),
    );
    if (selected != null) onChanged(selected);
  }
}

/// Chip-based multi-select variant, e.g. "Additional Light Entities (up to
/// 8)" or "Media Players (up to 14)".
class MultiEntityPickerField extends StatelessWidget {
  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final List<String>? domains;
  final int? maxCount;

  const MultiEntityPickerField({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.domains,
    this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<StateStore>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in values)
              Chip(
                label: Text(store.get(id)?.attr<String>('friendly_name', id) ?? id),
                onDeleted: () => onChanged(values.where((v) => v != id).toList()),
              ),
            if (maxCount == null || values.length < maxCount!)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () async {
                  final options = store.all.values
                      .where((e) =>
                          (domains == null || domains!.contains(e.domain)) &&
                          !values.contains(e.entityId))
                      .toList()
                    ..sort((a, b) => a.attr<String>('friendly_name', a.entityId)
                        .compareTo(b.attr<String>('friendly_name', b.entityId)));
                  final selected = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => _EntityPickerSheet(label: label, options: options),
                  );
                  if (selected != null) onChanged([...values, selected]);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _EntityPickerSheet extends StatefulWidget {
  final String label;
  final List<EntityState> options;
  const _EntityPickerSheet({required this.label, required this.options});

  @override
  State<_EntityPickerSheet> createState() => _EntityPickerSheetState();
}

class _EntityPickerSheetState extends State<_EntityPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options.where((e) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.entityId.toLowerCase().contains(q) ||
          e.attr<String>('friendly_name', '').toLowerCase().contains(q);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Text('Select ${widget.label}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search entities…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            if (widget.options.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  'No matching entities found. Make sure the app is connected to Home Assistant.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final e = filtered[i];
                  return ListTile(
                    title: Text(e.attr<String>('friendly_name', e.entityId)),
                    subtitle: Text(e.entityId),
                    onTap: () => Navigator.of(context).pop(e.entityId),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
