import 'package:flutter/material.dart';

import '../custom/card_spec.dart';
import '../custom/custom_card.dart';
import '../models/room_config.dart';
import 'air_purifier_card.dart';
import 'base_entity_card.dart';
import 'battery_card.dart';
import 'camera_card.dart';
import 'curtain_card.dart';
import 'doorbell_card.dart';
import 'energy_card.dart';
import 'fan_card.dart';
import 'humidifier_card.dart';
import 'light_card.dart';
import 'lock_card.dart';
import 'media_card.dart';
import 'motion_card.dart';
import 'network_card.dart';
import 'plant_card.dart';
import 'thermostat_card.dart';
import 'updates_card.dart';
import 'vacuum_card.dart';

/// Maps a [CardConfig] entry (add/remove/reorder per room in Settings) to
/// its concrete card widget.
Widget buildEntityCard(CardConfig config, int position) {
  switch (config.type) {
    case HemmaCardType.light:
      return LightCard(
        entityId: config.entityId,
        label: config.labelOverride,
        position: position,
      );
    case HemmaCardType.thermostat:
      return ThermostatCard(
        entityId: config.entityId,
        tempSensorEntityId: config.extraEntityIds.isNotEmpty ? config.extraEntityIds.first : null,
        label: config.labelOverride,
        position: position,
      );
    case HemmaCardType.fan:
      return FanCard(
          entityId: config.entityId, label: config.labelOverride, position: position);
    case HemmaCardType.humidifier:
      return HumidifierCard(entityId: config.entityId, position: position);
    case HemmaCardType.airPurifier:
      return AirPurifierCard(entityId: config.entityId, position: position);
    case HemmaCardType.media:
      return MediaCard(
          entityId: config.entityId, label: config.labelOverride, position: position);
    case HemmaCardType.lock:
      return LockCard(
          entityId: config.entityId, label: config.labelOverride, position: position);
    case HemmaCardType.motion:
      return MotionCard(
        sensorEntityIds: [config.entityId, ...config.extraEntityIds],
        position: position,
      );
    case HemmaCardType.doorbell:
      return DoorbellCard(
          entityId: config.entityId, label: config.labelOverride, position: position);
    case HemmaCardType.camera:
      return CameraCard(
          entityId: config.entityId, label: config.labelOverride, position: position);
    case HemmaCardType.vacuum:
      return VacuumCard(
          entityId: config.entityId, label: config.labelOverride, position: position);
    case HemmaCardType.curtain:
      return CurtainCard(
          entityId: config.entityId, label: config.labelOverride, position: position);
    case HemmaCardType.energy:
      return EnergyCard(powerSensorEntityId: config.entityId, position: position);
    case HemmaCardType.network:
      return NetworkCard(
        downloadSensorEntityId: config.entityId,
        uploadSensorEntityId: config.extraEntityIds.isNotEmpty ? config.extraEntityIds.first : null,
        pingSensorEntityId: config.extraEntityIds.length > 1 ? config.extraEntityIds[1] : null,
        position: position,
      );
    case HemmaCardType.battery:
      return BatteryCard(
        entityFilter: config.extraEntityIds.isNotEmpty ? config.extraEntityIds : null,
        position: position,
      );
    case HemmaCardType.updates:
      return UpdatesCard(position: position);
    case HemmaCardType.plant:
      return PlantCard(plantEntityId: config.entityId, position: position);
    case HemmaCardType.custom:
      final raw = config.customSpec;
      if (raw == null) {
        return HemmaEntityCard(
          iconName: 'home',
          label: config.labelOverride ?? 'Custom card',
          stateText: 'Not configured',
          active: false,
          position: position,
        );
      }
      return CustomCard(
        spec: CustomCardSpec.fromJson(raw),
        entityOverride: config.entityId.isEmpty ? null : config.entityId,
        labelOverride: config.labelOverride,
        position: position,
      );
  }
}
