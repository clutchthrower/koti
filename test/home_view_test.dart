import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koti/api/ha_rest_client.dart';
import 'package:koti/api/ha_websocket_client.dart';
import 'package:koti/edit/edit_mode.dart';
import 'package:koti/models/entity_state.dart';
import 'package:koti/models/room_config.dart';
import 'package:koti/screens/home_overview_screen.dart';
import 'package:koti/store/helper_store.dart';
import 'package:koti/store/settings_store.dart';
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

void main() {
  testWidgets('HomeView derives whole-home cards once states arrive',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = StateStore(
      ws: HaWebSocketClient(baseUrl: 'http://localhost:1', token: 't'),
      rest: HaRestClient(baseUrl: 'http://localhost:1', token: 't'),
    );
    final helpers = HelperStore(stateStore: store);
    final settings = SettingsStore()..rooms = [RoomConfig(id: 'x', name: 'X')];
    final theme = ThemeController();

    await tester.binding.setSurfaceSize(const Size(1280, 800));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<StateStore>.value(value: store),
          ChangeNotifierProvider<HelperStore>.value(value: helpers),
          ChangeNotifierProvider<EditModeController>(
              create: (_) => EditModeController()),
        ],
        child: KotiTheme(
          tokens: KotiTokens(
            brightness: Brightness.dark,
            accentColor: KotiTokens.defaultAccent,
            cardTransparency: 1.0,
          ),
          child: const MaterialApp(home: HomeView()),
        ),
      ),
    );
    await tester.pump();

    // Store still empty: no cards yet, but no crash either.
    expect(find.text('Front Door'), findsNothing);

    // Initial get_states sync lands.
    store.debugSetStates([
      _e('climate.home_thermostat', 'cool', {'friendly_name': 'Thermostat'}),
      _e('lock.front_door', 'locked', {'friendly_name': 'Front Door'}),
      _e('vacuum.sharkira', 'docked', {'friendly_name': 'Sharkira'}),
    ]);
    await tester.pump();
    // Let entrance animations play out.
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Front Door'), findsOneWidget);
    expect(find.text('Sharkira'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });
}
