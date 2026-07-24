"""Update platform for Koti players — app version/update status.

Read-only: reports installed vs. latest version, no remote-triggered
install flow (UpdateEntityFeature.INSTALL isn't declared) — the app
already has its own in-app update/install flow, and this just reports
its current status rather than adding a second, materially bigger
remote-install feature.
"""

from __future__ import annotations

from homeassistant.components.update import UpdateEntity
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
    async_add_entities([KotiUpdateEntity(coordinator, entry)])


class KotiUpdateEntity(CoordinatorEntity[KotiCoordinator], UpdateEntity):
    """The Koti app's own version/update status."""

    _attr_has_entity_name = True
    _attr_translation_key = "app_update"

    def __init__(self, coordinator: KotiCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.unique_id}_app_update"
        self._attr_device_info = device_info_for(entry)

    @property
    def installed_version(self) -> str | None:
        return (self.coordinator.data or {}).get("appVersion")

    @property
    def latest_version(self) -> str | None:
        data = self.coordinator.data or {}
        return data.get("appLatestVersion") or data.get("appVersion")
