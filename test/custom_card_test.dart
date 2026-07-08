import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koti/api/ha_rest_client.dart';
import 'package:koti/api/ha_websocket_client.dart';
import 'package:koti/custom/card_spec.dart';
import 'package:koti/custom/custom_card.dart';
import 'package:koti/custom/template_engine.dart';
import 'package:koti/models/entity_state.dart';
import 'package:koti/store/state_store.dart';
import 'package:koti/theme/koti_theme.dart';
import 'package:koti/theme/tokens.dart';

EntityState _e(String id, String state, [Map<String, dynamic>? attrs]) =>
    EntityState(
      entityId: id,
      state: state,
      attributes: attrs ?? const {},
      lastChanged: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

TemplateScope _scope(List<EntityState> entities, {String? defaultEntity}) {
  final byId = {for (final e in entities) e.entityId: e};
  return TemplateScope(
      defaultEntityId: defaultEntity, lookup: (id) => byId[id]);
}

void main() {
  group('template engine', () {
    final scope = _scope([
      _e('light.desk', 'on',
          {'friendly_name': 'Desk Lamp', 'brightness': 128}),
      _e('sensor.temp', '21.5',
          {'friendly_name': 'Temp', 'unit_of_measurement': '°C'}),
    ], defaultEntity: 'light.desk');

    test('renders default-entity and cross-entity tokens', () {
      expect(renderTemplate('{name} is {state}', scope), 'Desk Lamp is on');
      expect(renderTemplate('{attributes.brightness}', scope), '128');
      expect(renderTemplate('{sensor.temp.state}{sensor.temp.attributes.unit_of_measurement}', scope),
          '21.5°C');
      expect(renderTemplate('{sensor.temp}', scope), '21.5'); // bare = state
    });

    test('filters and missing values', () {
      expect(renderTemplate('{sensor.temp.state|round}', scope), '22');
      expect(renderTemplate('{state|title}', scope), 'On');
      expect(renderTemplate('{sensor.nope.state}', scope), '—');
      expect(renderTemplate('{attributes.nope}', scope), '—');
    });

    test('conditions', () {
      expect(evalCondition("state == 'on'", scope), isTrue);
      expect(evalCondition("state != 'on'", scope), isFalse);
      expect(evalCondition('attributes.brightness > 100', scope), isTrue);
      expect(evalCondition('sensor.temp.state >= 21.5', scope), isTrue);
      expect(evalCondition('sensor.temp.state < 21', scope), isFalse);
      expect(evalCondition('state', scope), isTrue); // bare truthy
      expect(evalCondition("entity_id contains 'desk'", scope), isTrue);
      expect(evalCondition(null, scope), isFalse);
    });

    test('extracts referenced entities, skipping reserved roots', () {
      final ids = extractEntityIds({
        'state': '{attributes.brightness} / {sensor.temp.state}',
        'popup': [
          {'type': 'toggle', 'entity': 'switch.heater'},
        ],
      }, defaultEntityId: 'light.desk');
      expect(ids, {'light.desk', 'sensor.temp', 'switch.heater'});
    });
  });

  group('card spec', () {
    test('parses, validates, and round-trips', () {
      final spec = CustomCardSpec.parse('''
      {
        "name": "{name}", "icon": "fan", "entity": "fan.attic",
        "activeWhen": "state == 'on'",
        "popup": [{"type": "toggle"}]
      }''');
      expect(spec.icon, 'fan');
      expect(spec.validate(), isEmpty);
      final reparsed = CustomCardSpec.fromJson(spec.toJson());
      expect(reparsed.entity, 'fan.attic');
      expect(reparsed.popup.single['type'], 'toggle');
    });

    test('rejects bad JSON, warns on unknown names', () {
      expect(() => CustomCardSpec.parse('{nope'), throwsFormatException);
      expect(() => CustomCardSpec.parse('[1,2]'), throwsFormatException);
      final spec = CustomCardSpec.parse(
          '{"icon": "flux-capacitor", "popup": [{"type": "hologram"}]}');
      expect(spec.validate(), hasLength(2));
    });

    test('starter spec is valid', () {
      final spec = CustomCardSpec.parse(CustomCardSpec.starterFor('light.desk'));
      expect(spec.validate(), isEmpty);
      expect(spec.icon, 'light');
    });

    test('every shared example card parses cleanly', () {
      final dir = Directory('cards/examples');
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files, isNotEmpty);
      for (final file in files) {
        final spec = CustomCardSpec.parse(file.readAsStringSync());
        expect(spec.validate(), isEmpty, reason: file.path);
      }
    });
  });

  group('CustomCard widget', () {
    late StateStore store;
    final calls = <String>[];

    Widget harness(CustomCardSpec spec) {
      SharedPreferences.setMockInitialValues({});
      store = StateStore(
        ws: HaWebSocketClient(baseUrl: 'http://localhost:1', token: 't'),
        rest: HaRestClient(baseUrl: 'http://localhost:1', token: 't'),
      );
      store.debugServiceInterceptor = (domain, service, data, entityId) =>
          calls.add('$domain.$service $entityId ${data ?? ''}'.trim());
      store.debugSetStates([
        _e('switch.washer', 'on',
            {'friendly_name': 'Washer', 'remaining': 42}),
      ]);
      calls.clear();

      return ChangeNotifierProvider<StateStore>.value(
        value: store,
        child: KotiTheme(
          tokens: KotiTokens(
            brightness: Brightness.dark,
            accentColor: KotiTokens.defaultAccent,
            cardTransparency: 1.0,
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 260,
                  height: 150,
                  child: CustomCard(spec: spec, entityOverride: 'switch.washer'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders templated face and opens a live popup', (tester) async {
      final spec = CustomCardSpec.fromJson({
        'name': '{name}',
        'icon': 'power_on',
        'state': '{attributes.remaining} min left',
        'activeWhen': "state == 'on'",
        'popup': [
          {'type': 'text', 'text': 'Remaining: {attributes.remaining}'},
          {
            'type': 'buttons',
            'buttons': [
              {
                'text': 'Stop',
                'action': {'action': 'service', 'service': 'switch.turn_off'},
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(harness(spec));
      await tester.pump(const Duration(seconds: 1)); // entrance animation

      expect(find.text('Washer'), findsOneWidget);
      expect(find.text('42 min left'), findsOneWidget);

      await tester.tap(find.text('Washer'));
      await tester.pump(const Duration(milliseconds: 300)); // popup transition

      expect(find.text('Remaining: 42'), findsOneWidget);

      // Popup content is live: a state change re-renders the template.
      store.debugSetStates([
        _e('switch.washer', 'on', {'friendly_name': 'Washer', 'remaining': 41}),
      ]);
      await tester.pump();
      expect(find.text('Remaining: 41'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      expect(calls, ['switch.turn_off switch.washer']);
    });

    testWidgets('quick action fires without opening the popup',
        (tester) async {
      final spec = CustomCardSpec.fromJson({
        'name': '{name}',
        'icon': 'power_on',
        'quick': {
          'icon': 'power_off',
          'action': {'action': 'toggle'},
        },
        'popup': [
          {'type': 'toggle', 'label': 'Power'},
        ],
      });

      await tester.pumpWidget(harness(spec));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byType(IconButton));
      expect(calls, ['homeassistant.toggle switch.washer']);
      expect(find.text('Power'), findsNothing); // popup did not open
    });

    testWidgets('canvas-layout popup positions blocks freely', (tester) async {
      final spec = CustomCardSpec.fromJson({
        'name': '{name}',
        'icon': 'power_on',
        'popupLayout': 'canvas',
        'canvasSize': [360, 480],
        'popup': [
          {
            'type': 'text',
            'text': 'Top label',
            'x': 0.1,
            'y': 0.05,
            'w': 0.5,
            'h': 0.1,
          },
          {
            'type': 'text',
            'text': 'Bottom label',
            'x': 0.1,
            'y': 0.8,
            'w': 0.5,
            'h': 0.1,
          },
        ],
      });

      await tester.pumpWidget(harness(spec));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Washer'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Top label'), findsOneWidget);
      expect(find.text('Bottom label'), findsOneWidget);
      final topY = tester.getTopLeft(find.text('Top label')).dy;
      final bottomY = tester.getTopLeft(find.text('Bottom label')).dy;
      expect(bottomY, greaterThan(topY));
    });
  });
}
