enum HemmaCardType {
  light,
  thermostat,
  fan,
  humidifier,
  airPurifier,
  media,
  lock,
  motion,
  doorbell,
  camera,
  vacuum,
  curtain,
  energy,
  network,
  battery,
  updates,
  plant,
  custom,
}

class CardConfig {
  final String id;
  final HemmaCardType type;
  final String entityId;
  final List<String> extraEntityIds; // e.g. multi-sensor motion, group members
  final String? labelOverride;

  /// For [HemmaCardType.custom]: the user-authored card design as decoded
  /// JSON (see docs/CARD_FORMAT.md). Kept as a raw map so configs written
  /// by newer app versions survive a round-trip through older ones.
  final Map<String, dynamic>? customSpec;

  const CardConfig({
    required this.id,
    required this.type,
    required this.entityId,
    this.extraEntityIds = const [],
    this.labelOverride,
    this.customSpec,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'entityId': entityId,
        'extraEntityIds': extraEntityIds,
        'labelOverride': labelOverride,
        if (customSpec != null) 'customSpec': customSpec,
      };

  factory CardConfig.fromJson(Map<String, dynamic> json) => CardConfig(
        id: json['id'] as String,
        type: HemmaCardType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => HemmaCardType.custom,
        ),
        entityId: json['entityId'] as String? ?? '',
        extraEntityIds: (json['extraEntityIds'] as List?)?.cast<String>() ?? const [],
        labelOverride: json['labelOverride'] as String?,
        customSpec: (json['customSpec'] as Map?)?.cast<String, dynamic>(),
      );
}

class RoomConfig {
  final String id;
  final String name;
  final String iconAsset;
  final String? climateEntity;
  final String? temperatureSensor;
  final String? humiditySensor;
  final String? aqiSensor;
  final String? lightGroupEntity;
  final List<String> lightEntities;
  final List<String> mediaPlayers;
  final String? motionSensor;
  final List<String> lockEntities;
  final List<String> coverEntities;
  final List<String> presenceEntities;
  final List<CardConfig> cards;
  final bool useTimeOfDayMobileBackground;

  /// Explicit background image path (asset or file). When null the room
  /// picks a bundled demo photo by keyword — see [_demoBase].
  final String? backgroundAsset;

  const RoomConfig({
    required this.id,
    required this.name,
    this.iconAsset = 'home',
    this.climateEntity,
    this.temperatureSensor,
    this.humiditySensor,
    this.aqiSensor,
    this.lightGroupEntity,
    this.lightEntities = const [],
    this.mediaPlayers = const [],
    this.motionSensor,
    this.lockEntities = const [],
    this.coverEntities = const [],
    this.presenceEntities = const [],
    this.cards = const [],
    this.useTimeOfDayMobileBackground = true,
    this.backgroundAsset,
  });

  /// Which bundled demo photo fits this room. Rooms auto-created from HA
  /// Areas have ids like `living_room` or `laundry_room` that don't match
  /// the four bundled demo images 1:1, so match on keywords and fall back
  /// to the whole-home shot instead of a black screen.
  String get _demoBase {
    final k = id.toLowerCase();
    if (k.contains('bed')) return 'bedroom-demo';
    if (k.contains('kitchen') || k.contains('dining') || k.contains('laundry')) {
      return 'kitchen-demo';
    }
    if (k.contains('living') || k.contains('lounge') || k.contains('family') ||
        k.contains('office') || k.contains('computer') || k.contains('media')) {
      return 'livingroom-demo';
    }
    return 'home-demo';
  }

  /// The original dashboard shows every view over a heavily blurred,
  /// dimmed room photo. Real-time blur is banned on this hardware
  /// (CLAUDE.md), so pre-blurred copies live in `assets/rooms/blur/`.
  String backgroundFor({required bool night, bool blurred = true}) {
    final custom = backgroundAsset;
    if (custom != null) {
      // 'demo:<base>' = user explicitly picked one of the bundled photos
      // (keeps day/night switching). An absolute path = their own photo,
      // pre-shrunk at pick time so it renders soft-blurred for free.
      if (custom.startsWith('demo:')) {
        final base = custom.substring(5);
        final file = night ? '$base-night.jpg' : '$base.jpg';
        return blurred ? 'assets/rooms/blur/$file' : 'assets/rooms/$file';
      }
      return custom;
    }
    final file = night ? '$_demoBase-night.jpg' : '$_demoBase.jpg';
    return blurred ? 'assets/rooms/blur/$file' : 'assets/rooms/$file';
  }

  String get desktopBackgroundAsset => backgroundFor(night: false);
  String get desktopBackgroundNightAsset => backgroundFor(night: true);

  static const Object _unset = Object();

  /// Copy with selective overrides. Nullable fields use an [_unset]
  /// sentinel so callers can explicitly clear them (pass null) as well as
  /// leave them untouched (omit).
  RoomConfig copyWith({
    String? id,
    String? name,
    String? iconAsset,
    Object? climateEntity = _unset,
    Object? temperatureSensor = _unset,
    Object? humiditySensor = _unset,
    Object? aqiSensor = _unset,
    Object? lightGroupEntity = _unset,
    List<String>? lightEntities,
    List<String>? mediaPlayers,
    Object? motionSensor = _unset,
    List<String>? lockEntities,
    List<String>? coverEntities,
    List<String>? presenceEntities,
    List<CardConfig>? cards,
    bool? useTimeOfDayMobileBackground,
    Object? backgroundAsset = _unset,
  }) {
    return RoomConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      iconAsset: iconAsset ?? this.iconAsset,
      climateEntity:
          identical(climateEntity, _unset) ? this.climateEntity : climateEntity as String?,
      temperatureSensor: identical(temperatureSensor, _unset)
          ? this.temperatureSensor
          : temperatureSensor as String?,
      humiditySensor: identical(humiditySensor, _unset)
          ? this.humiditySensor
          : humiditySensor as String?,
      aqiSensor: identical(aqiSensor, _unset) ? this.aqiSensor : aqiSensor as String?,
      lightGroupEntity: identical(lightGroupEntity, _unset)
          ? this.lightGroupEntity
          : lightGroupEntity as String?,
      lightEntities: lightEntities ?? this.lightEntities,
      mediaPlayers: mediaPlayers ?? this.mediaPlayers,
      motionSensor:
          identical(motionSensor, _unset) ? this.motionSensor : motionSensor as String?,
      lockEntities: lockEntities ?? this.lockEntities,
      coverEntities: coverEntities ?? this.coverEntities,
      presenceEntities: presenceEntities ?? this.presenceEntities,
      cards: cards ?? this.cards,
      useTimeOfDayMobileBackground:
          useTimeOfDayMobileBackground ?? this.useTimeOfDayMobileBackground,
      backgroundAsset: identical(backgroundAsset, _unset)
          ? this.backgroundAsset
          : backgroundAsset as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconAsset': iconAsset,
        'climateEntity': climateEntity,
        'temperatureSensor': temperatureSensor,
        'humiditySensor': humiditySensor,
        'aqiSensor': aqiSensor,
        'lightGroupEntity': lightGroupEntity,
        'lightEntities': lightEntities,
        'mediaPlayers': mediaPlayers,
        'motionSensor': motionSensor,
        'lockEntities': lockEntities,
        'coverEntities': coverEntities,
        'presenceEntities': presenceEntities,
        'cards': cards.map((c) => c.toJson()).toList(),
        'useTimeOfDayMobileBackground': useTimeOfDayMobileBackground,
        'backgroundAsset': backgroundAsset,
      };

  factory RoomConfig.fromJson(Map<String, dynamic> json) => RoomConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        iconAsset: json['iconAsset'] as String? ?? 'home',
        climateEntity: json['climateEntity'] as String?,
        temperatureSensor: json['temperatureSensor'] as String?,
        humiditySensor: json['humiditySensor'] as String?,
        aqiSensor: json['aqiSensor'] as String?,
        lightGroupEntity: json['lightGroupEntity'] as String?,
        lightEntities: (json['lightEntities'] as List?)?.cast<String>() ?? const [],
        mediaPlayers: (json['mediaPlayers'] as List?)?.cast<String>() ?? const [],
        motionSensor: json['motionSensor'] as String?,
        lockEntities: (json['lockEntities'] as List?)?.cast<String>() ?? const [],
        coverEntities: (json['coverEntities'] as List?)?.cast<String>() ?? const [],
        presenceEntities: (json['presenceEntities'] as List?)?.cast<String>() ?? const [],
        cards: (json['cards'] as List? ?? [])
            .map((c) => CardConfig.fromJson((c as Map).cast<String, dynamic>()))
            .toList(),
        useTimeOfDayMobileBackground: json['useTimeOfDayMobileBackground'] as bool? ?? true,
        backgroundAsset: json['backgroundAsset'] as String?,
      );

  factory RoomConfig.demo(String id, String name) => RoomConfig(
        id: id,
        name: name,
        cards: const [],
      );
}
