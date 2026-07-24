"""Button platform for Koti players — restart app / reboot device."""

from __future__ import annotations

from homeassistant.components.button import ButtonDeviceClass, ButtonEntity
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
    async_add_entities(
        [
            KotiRestartAppButton(coordinator, entry),
            KotiRebootDeviceButton(coordinator, entry),
        ]
    )


class _KotiButton(CoordinatorEntity[KotiCoordinator], ButtonEntity):
    _attr_has_entity_name = True
    _attr_device_class = ButtonDeviceClass.RESTART

    def __init__(self, coordinator: KotiCoordinator, entry: ConfigEntry, key: str) -> None:
        super().__init__(coordinator)
        self._attr_unique_id = f"{entry.unique_id}_{key}"
        self._attr_device_info = device_info_for(entry)


class KotiRestartAppButton(_KotiButton):
    """Restarts the Koti app itself (not the whole device)."""

    _attr_translation_key = "restart_app"

    def __init__(self, coordinator: KotiCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator, entry, "restart_app")

    async def async_press(self) -> None:
        await self.coordinator.send_command("restartApp")


class KotiRebootDeviceButton(_KotiButton):
    """Reboots the whole tablet.

    Only works if the tablet has been set up as a Device Owner (see
    README.md) — a normal Android app can't reboot the device otherwise.
    The app-side command reports back plainly when that's the case; this
    button doesn't have a way to surface that reason itself since
    async_press has no return value, so check Home Assistant's logs (or
    the app's own log) if pressing this does nothing.
    """

    _attr_translation_key = "reboot_device"

    def __init__(self, coordinator: KotiCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator, entry, "reboot_device")

    async def async_press(self) -> None:
        await self.coordinator.send_command("rebootDevice")
