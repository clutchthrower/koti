"""Sensor platform for Koti players — battery level."""

from __future__ import annotations

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity, SensorStateClass
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import PERCENTAGE
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import KotiCoordinator
from .entity import device_info_for


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator: KotiCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([KotiBatterySensor(coordinator, entry)])


class KotiBatterySensor(CoordinatorEntity[KotiCoordinator], SensorEntity):
    """The tablet's own battery level."""

    _attr_has_entity_name = True
    _attr_translation_key = "battery"
    _attr_device_class = SensorDeviceClass.BATTERY
    _attr_state_class = SensorStateClass.MEASUREMENT
    _attr_native_unit_of_measurement = PERCENTAGE

    def __init__(self, coordinator: KotiCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.unique_id}_battery"
        self._attr_device_info = device_info_for(entry)

    @property
    def native_value(self) -> int | None:
        data = self.coordinator.data or {}
        return data.get("batteryLevel")
