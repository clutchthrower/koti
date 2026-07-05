import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../hero/hero_room_card.dart';
import '../layout/entity_grid.dart';
import '../models/entity_state.dart';
import '../models/room_config.dart';
import '../store/settings_store.dart';
import '../store/state_store.dart';

/// The Home tab's content as a [RoomConfig]: the user's saved
/// customization if they've edited Home, otherwise derived automatically —
/// badges aggregated across every room, plus whole-home device cards
/// (thermostats, locks, doorbell, vacuums, covers, updates, batteries).
RoomConfig effectiveHomeConfig({
  required List<RoomConfig> rooms,
  required StateStore store,
  RoomConfig? saved,
}) {
  if (saved != null) return saved;

  final lights = <String>{};
  final media = <String>{};
  final people = <String>{};
  String? tempSensor;
  String? humiditySensor;
  String? climate;
  for (final r in rooms) {
    lights.addAll(r.lightEntities);
    if (r.lightGroupEntity != null) lights.add(r.lightGroupEntity!);
    media.addAll(r.mediaPlayers);
    people.addAll(r.presenceEntities);
    tempSensor ??= r.temperatureSensor;
    humiditySensor ??= r.humiditySensor;
    climate ??= r.climateEntity;
  }

  return RoomConfig(
    id: 'home',
    name: 'Home',
    climateEntity: climate,
    temperatureSensor: tempSensor,
    humiditySensor: humiditySensor,
    lightEntities: lights.toList(),
    mediaPlayers: media.toList(),
    presenceEntities: people.toList(),
    cards: _deriveHomeCards(store),
  );
}

List<CardConfig> _deriveHomeCards(StateStore store) {
  final all = store.all.values.toList()
    ..sort((a, b) => a.entityId.compareTo(b.entityId));
  final cards = <CardConfig>[];

  void addAll(Iterable<EntityState> entities, HemmaCardType type, int cap) {
    for (final e in entities.take(cap)) {
      cards.add(CardConfig(id: 'home-${e.entityId}', type: type, entityId: e.entityId));
    }
  }

  addAll(all.where((e) => e.domain == 'climate'), HemmaCardType.thermostat, 2);
  addAll(all.where((e) => e.domain == 'lock'), HemmaCardType.lock, 4);
  addAll(
    all.where(
        (e) => e.domain == 'binary_sensor' && e.entityId.contains('doorbell')),
    HemmaCardType.doorbell,
    1,
  );
  addAll(all.where((e) => e.domain == 'vacuum'), HemmaCardType.vacuum, 2);
  addAll(
    all.where((e) => e.domain == 'camera' && e.state != 'unavailable'),
    HemmaCardType.camera,
    2,
  );
  addAll(all.where((e) => e.domain == 'cover'), HemmaCardType.curtain, 2);
  addAll(all.where((e) => e.domain == 'fan'), HemmaCardType.fan, 2);
  if (all.any((e) => e.domain == 'update' && e.state == 'on')) {
    cards.add(const CardConfig(
        id: 'home-updates', type: HemmaCardType.updates, entityId: ''));
  }
  if (all.any((e) =>
      e.domain == 'sensor' && e.attr<String>('device_class', '') == 'battery')) {
    cards.add(const CardConfig(
        id: 'home-battery', type: HemmaCardType.battery, entityId: ''));
  }
  return cards.take(12).toList();
}

/// The "Home" tab: identical layout to a room view — blurred whole-home
/// photo, big "Home" title — using [effectiveHomeConfig] for its badges and
/// cards. Editable via the sidebar's "Edit Home".
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    // Rebuild only when the number of known entities changes (i.e. the
    // initial get_states sync lands, or something is added/removed) — not
    // on every state update, keeping repaints atomic per CLAUDE.md.
    context.select<StateStore, int>((s) => s.all.length);
    final store = Provider.of<StateStore>(context, listen: false);

    final home = effectiveHomeConfig(
      rooms: settings.rooms,
      store: store,
      saved: settings.homeRoom,
    );

    // Any edit materializes the (possibly auto-derived) config as the
    // saved Home layout — same as the drawer's Edit Home.
    return Stack(
      children: [
        Positioned.fill(
          child: HeroRoomCard(
            room: home,
            onRoomChanged: settings.setHomeRoom,
          ),
        ),
        Positioned.fill(
          child: EntityGrid(
            cards: home.cards,
            onCardsChanged: (cards) =>
                settings.setHomeRoom(home.copyWith(cards: cards)),
          ),
        ),
      ],
    );
  }
}
