import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../custom/card_spec.dart';
import '../models/room_config.dart';
import '../widgets/entity_picker.dart';

/// Human-readable names for card types, used everywhere card types are
/// shown to the user (edit sheets, room settings).
String cardTypeLabel(KotiCardType type) => switch (type) {
      KotiCardType.light => 'Light',
      KotiCardType.thermostat => 'Thermostat',
      KotiCardType.fan => 'Fan',
      KotiCardType.humidifier => 'Humidifier',
      KotiCardType.airPurifier => 'Air Purifier',
      KotiCardType.media => 'Media Player',
      KotiCardType.lock => 'Lock',
      KotiCardType.motion => 'Motion Sensor',
      KotiCardType.doorbell => 'Doorbell',
      KotiCardType.camera => 'Camera',
      KotiCardType.vacuum => 'Vacuum',
      KotiCardType.curtain => 'Curtain / Cover',
      KotiCardType.energy => 'Energy Usage',
      KotiCardType.network => 'Network',
      KotiCardType.battery => 'Battery Levels',
      KotiCardType.updates => 'Updates',
      KotiCardType.plant => 'Plant',
      KotiCardType.custom => 'Custom',
    };

/// Which entity domains fit each card type (null = no entity needed).
List<String>? cardTypeDomains(KotiCardType type) => switch (type) {
      KotiCardType.light => const ['light'],
      KotiCardType.thermostat => const ['climate'],
      KotiCardType.fan => const ['fan'],
      KotiCardType.humidifier => const ['humidifier'],
      KotiCardType.airPurifier => const ['fan', 'humidifier'],
      KotiCardType.media => const ['media_player'],
      KotiCardType.lock => const ['lock'],
      KotiCardType.motion => const ['binary_sensor'],
      KotiCardType.doorbell => const ['binary_sensor', 'camera'],
      KotiCardType.camera => const ['camera'],
      KotiCardType.vacuum => const ['vacuum'],
      KotiCardType.curtain => const ['cover'],
      KotiCardType.energy => const ['sensor'],
      KotiCardType.network => const ['sensor'],
      KotiCardType.battery => null,
      KotiCardType.updates => null,
      KotiCardType.plant => const ['plant'],
      KotiCardType.custom => null,
    };

/// Result of [showCardEditSheet]: either a card to save, or a deletion.
class CardEditResult {
  final CardConfig? card;
  final bool deleted;
  const CardEditResult.saved(this.card) : deleted = false;
  const CardEditResult.delete()
      : card = null,
        deleted = true;
}

/// One card editor for the whole app: pick what the card is, which device
/// it controls, and (optionally) a friendlier display name.
Future<CardEditResult?> showCardEditSheet(
  BuildContext context, {
  CardConfig? existing,
}) {
  return showModalBottomSheet<CardEditResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CardEditSheet(existing: existing),
  );
}

class _CardEditSheet extends StatefulWidget {
  final CardConfig? existing;
  const _CardEditSheet({this.existing});

  @override
  State<_CardEditSheet> createState() => _CardEditSheetState();
}

class _CardEditSheetState extends State<_CardEditSheet> {
  late KotiCardType _type;
  String? _entityId;
  String? _motionEntityId;
  late final TextEditingController _label;
  late final TextEditingController _spec;
  String? _specError;
  List<String> _specWarnings = const [];

  @override
  void initState() {
    super.initState();
    _type = widget.existing?.type ?? KotiCardType.light;
    _entityId =
        (widget.existing?.entityId.isEmpty ?? true) ? null : widget.existing!.entityId;
    _motionEntityId = widget.existing?.extraEntityIds.isNotEmpty ?? false
        ? widget.existing!.extraEntityIds.first
        : null;
    _label = TextEditingController(text: widget.existing?.labelOverride ?? '');
    _spec = TextEditingController(
      text: widget.existing?.customSpec == null
          ? ''
          : const JsonEncoder.withIndent('  ')
              .convert(widget.existing!.customSpec),
    );
    _validateSpec();
  }

  @override
  void dispose() {
    _label.dispose();
    _spec.dispose();
    super.dispose();
  }

  void _validateSpec() {
    if (_type != KotiCardType.custom) return;
    if (_spec.text.trim().isEmpty) {
      _specError = null;
      _specWarnings = const [];
      return;
    }
    try {
      _specWarnings = CustomCardSpec.parse(_spec.text).validate();
      _specError = null;
    } on FormatException catch (e) {
      _specError = e.message;
      _specWarnings = const [];
    }
  }

  Map<String, dynamic>? get _parsedSpec {
    if (_type != KotiCardType.custom || _spec.text.trim().isEmpty) return null;
    try {
      return CustomCardSpec.parse(_spec.text).toJson();
    } on FormatException {
      return null;
    }
  }

  bool get _canSave {
    if (_type == KotiCardType.custom) {
      return _spec.text.trim().isNotEmpty && _specError == null;
    }
    return _entityId != null || cardTypeDomains(_type) == null;
  }

  void _save() {
    Navigator.of(context).pop(CardEditResult.saved(CardConfig(
      id: widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      type: _type,
      entityId: _entityId ?? '',
      extraEntityIds: _type == KotiCardType.camera
          ? (_motionEntityId != null ? [_motionEntityId!] : const [])
          : widget.existing?.extraEntityIds ?? const [],
      labelOverride: _label.text.trim().isEmpty ? null : _label.text.trim(),
      customSpec: _parsedSpec,
    )));
  }

  Future<void> _pasteSpec() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _spec.text = text;
      _validateSpec();
    });
  }

  void _copySpec() {
    Clipboard.setData(ClipboardData(text: _spec.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Card copied — paste it anywhere to share')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;

    // SafeArea matters here: typing (e.g. in the JSON editor) summons the
    // Android nav bar on wall tablets, which would otherwise cover the
    // Add/Save row.
    return SafeArea(
      child: Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isNew ? 'Add Card' : 'Edit Card',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<KotiCardType>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Card type',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in KotiCardType.values)
                DropdownMenuItem(value: t, child: Text(cardTypeLabel(t))),
            ],
            onChanged: (v) => setState(() {
              _type = v!;
              _entityId = null; // domain changed, old entity no longer fits
              _motionEntityId = null;
              _validateSpec();
            }),
          ),
          const SizedBox(height: 12),
          if (_type == KotiCardType.custom) ...[
            EntityPickerField(
              label: 'Device (optional — overrides the design\'s entity)',
              value: _entityId,
              domains: null,
              onChanged: (v) => setState(() => _entityId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _spec,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Card design (JSON)',
                hintText:
                    'Paste a shared card here, or tap Starter to begin',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                errorText: _specError,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(_validateSpec),
            ),
            if (_specWarnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _specWarnings.join('\n'),
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Starter'),
                  onPressed: () => setState(() {
                    _spec.text = CustomCardSpec.starterFor(_entityId);
                    _validateSpec();
                  }),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Paste'),
                  onPressed: _pasteSpec,
                ),
                if (_spec.text.trim().isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    onPressed: _copySpec,
                  ),
              ],
            ),
          ] else if (cardTypeDomains(_type) != null) ...[
            EntityPickerField(
              label: 'Device',
              value: _entityId,
              domains: cardTypeDomains(_type),
              onChanged: (v) => setState(() => _entityId = v),
            ),
            if (_type == KotiCardType.camera) ...[
              const SizedBox(height: 12),
              EntityPickerField(
                label: 'Motion sensor (optional)',
                value: _motionEntityId,
                domains: const ['binary_sensor'],
                deviceClasses: const ['motion', 'occupancy'],
                onChanged: (v) => setState(() => _motionEntityId = v),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'When set, the card pulses a red border while motion is detected.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
            ],
          ] else
            Text(
              'This card finds its devices automatically.',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              hintText: 'Leave empty to use the device\'s own name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (!isNew)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Remove', style: TextStyle(color: Colors.red)),
                  onPressed: () =>
                      Navigator.of(context).pop(const CardEditResult.delete()),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _canSave ? _save : null,
                child: Text(isNew ? 'Add' : 'Save'),
              ),
            ],
          ),
        ],
        ),
      ),
      ),
    );
  }
}
