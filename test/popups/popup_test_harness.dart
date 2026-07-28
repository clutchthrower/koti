import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koti/api/ha_rest_client.dart';
import 'package:koti/api/ha_websocket_client.dart';
import 'package:koti/models/entity_state.dart';
import 'package:koti/store/helper_store.dart';
import 'package:koti/store/settings_store.dart';
import 'package:koti/store/state_store.dart';
import 'package:koti/theme/koti_theme.dart';
import 'package:koti/theme/tokens.dart';

/// Builds an [EntityState] with `lastChanged`/`lastUpdated` defaulted to
/// now — every popup test constructs its fixtures this way.
EntityState fakeEntity(String id, String state, [Map<String, dynamic>? attrs]) =>
    EntityState(
      entityId: id,
      state: state,
      attributes: attrs ?? const {},
      lastChanged: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

/// Popups (`showXPopup`) are plain functions that call `showKotiPopup`, not
/// widgets — this hosts a single button whose `onPressed` invokes the given
/// callback with a real `BuildContext` (so `showKotiPopup`'s anchor-finding
/// `context.findRenderObject()` has something concrete to measure), wired
/// up with the same StateStore/SettingsStore/HelperStore/KotiTheme
/// scaffolding a popup opened from within the real app would have above it.
class PopupTestHarness {
  PopupTestHarness();

  late final StateStore store;
  late final SettingsStore settings;
  late final HelperStore helpers;
  final calls = <String>[];

  Future<void> pump(
    WidgetTester tester,
    void Function(BuildContext context) onPressed, {
    Iterable<EntityState> entities = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    store = StateStore(
      ws: HaWebSocketClient(baseUrl: 'http://localhost:1', token: 't'),
      rest: HaRestClient(baseUrl: 'http://localhost:1', token: 't'),
    );
    store.debugServiceInterceptor = (domain, service, data, entityId) =>
        calls.add('$domain.$service $entityId ${data ?? ''}'.trim());
    store.debugSetStates(entities);

    settings = SettingsStore();
    helpers = HelperStore(stateStore: store);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StateStore>.value(value: store),
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
          ChangeNotifierProvider<HelperStore>.value(value: helpers),
        ],
        child: KotiTheme(
          tokens: KotiTokens(
            brightness: Brightness.dark,
            accentColor: KotiTokens.defaultAccent,
            cardTransparency: 1.0,
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                // showKotiPopup sizes itself off this anchor's width (roughly
                // 1.5x it, clamped 300-480) — a bare button's natural width
                // is narrow enough to force the popup down to its 300px
                // floor, which is unrealistically tighter than any real
                // anchor (a room hero, a card) and overflows content that
                // fits fine in the app itself. Sized to land near the popup's
                // actual max width instead.
                child: SizedBox(
                  width: 320,
                  height: 56,
                  child: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => onPressed(context),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}
