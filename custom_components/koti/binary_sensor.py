"""Binary sensor platform for Koti players — charging status."""

from __future__ import annotations

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.config_entries import ConfigEntry
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
    async_add_entities([KotiChargingSensor(coordinator, entry)])


class KotiChargingSensor(CoordinatorEntity[KotiCoordinator], BinarySensorEntity):
    """Whether the tablet is currently charging."""

    _attr_has_entity_name = True
    _attr_translation_key = "charging"
    _attr_device_class = BinarySensorDeviceClass.BATTERY_CHARGING

    def __init__(self, coordinator: KotiCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.unique_id}_charging"
        self._attr_device_info = device_info_for(entry)

    @property
    def is_on(self) -> bool | None:
        data = self.coordinator.data or {}
        return data.get("batteryCharging")
