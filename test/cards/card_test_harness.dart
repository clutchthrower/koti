import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koti/api/ha_rest_client.dart';
import 'package:koti/api/ha_websocket_client.dart';
import 'package:koti/models/entity_state.dart';
import 'package:koti/store/settings_store.dart';
import 'package:koti/store/state_store.dart';
import 'package:koti/theme/koti_theme.dart';
import 'package:koti/theme/tokens.dart';

/// Builds an [EntityState] with `lastChanged`/`lastUpdated` defaulted to now
/// — every card test in test/cards/ constructs its fixtures this way.
EntityState fakeEntity(String id, String state, [Map<String, dynamic>? attrs]) =>
    EntityState(
      entityId: id,
      state: state,
      attributes: attrs ?? const {},
      lastChanged: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

/// Shared plumbing every entity card needs to render standalone in a widget
/// test: a [StateStore] pre-seeded with fixture entities (service calls
/// captured instead of hitting the network — see [calls]), a
/// [SettingsStore] (some cards, e.g. CameraCard, read `activeUrl`/
/// `accessToken` off it via Provider), and the KotiTheme/MaterialApp
/// scaffolding every card assumes is present above it in the real app.
class CardTestHarness {
  CardTestHarness();

  late final StateStore store;
  late final SettingsStore settings;
  final calls = <String>[];

  Future<void> pump(
    WidgetTester tester,
    Widget card, {
    Iterable<EntityState> entities = const [],
    double width = 220,
    double height = 220,
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StateStore>.value(value: store),
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
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
                child: SizedBox(width: width, height: height, child: card),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // KotiEntityCard's entrance fade/slide starts on a Future.delayed(0)
    // (position * 40ms, 0 for the default position) and animates over
    // 400ms — a bare pump() leaves that timer/ticker pending, which trips
    // flutter_test's "no pending timers" invariant at test teardown even
    // though it never affects what's actually asserted.
    await tester.pump(const Duration(milliseconds: 500));
  }
}
