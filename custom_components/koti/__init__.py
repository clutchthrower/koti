"""The Koti integration — auto-discovered tablets, exposed as a media_player
entity (media_player.koti_{name}) so it's directly controllable, plus a
Bluetooth proxy (bluetooth.py) that registers under this same Device rather
than a separate one.
"""

from __future__ import annotations

import logging

from homeassistant.components import webhook
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import CALLBACK_TYPE, HomeAssistant, callback as hass_callback
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er

from .bluetooth import async_register_scanner, async_webhook_handler_for
from .const import (
    CONF_BLE_WEBHOOK_ID,
    CONF_ID,
    DOMAIN,
    MUSIC_ASSISTANT_DOMAIN,
    MUSIC_ASSISTANT_ID_PREFIX,
)
from .coordinator import KotiCoordinator

_LOGGER = logging.getLogger(__name__)

PLATFORMS = [
    Platform.MEDIA_PLAYER,
    Platform.SENSOR,
    Platform.BINARY_SENSOR,
    Platform.UPDATE,
    Platform.BUTTON,
]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    coordinator = KotiCoordinator(
        hass, host=entry.data["host"], port=entry.data["port"]
    )
    # Best-effort, not async_config_entry_first_refresh() — that raises
    # ConfigEntryNotReady on a failed first poll, which skips
    # async_forward_entry_setups() below entirely, leaving the entry with
    # zero entities (not even unavailable ones) until a later automatic
    # retry happens to land after the tablet's actually reachable. This
    # tablet is a phone-class Android device that can take 15+ seconds to
    # cold-boot its REST server — a real, observed race right after a
    # fresh install+onboard, not a hypothetical. Entities get created
    # regardless and just report unavailable (CoordinatorEntity.available
    # already handles that) until the first successful poll.
    await coordinator.async_refresh()

    reported_id = coordinator.data.get("deviceID") if coordinator.data else None
    if reported_id:
        await _async_migrate_device_id_if_needed(hass, entry, reported_id)

    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = coordinator
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    _async_link_sibling_devices(hass, entry)
    await _async_setup_ble_proxy(hass, entry, coordinator)
    return True


async def _async_setup_ble_proxy(
    hass: HomeAssistant, entry: ConfigEntry, coordinator: KotiCoordinator
) -> None:
    """Registers this tablet's BLE scanner under this same Device and tells
    the tablet where to POST its advertisements.

    The webhook id is minted once and persisted in the config entry — the
    tablet doesn't need re-telling on every Home Assistant restart, but it's
    harmless/idempotent to redo, so this always re-pushes it (covers the
    tablet having been factory-reset or re-onboarded without HA knowing).
    """
    webhook_id = entry.data.get(CONF_BLE_WEBHOOK_ID)
    if not webhook_id:
        webhook_id = webhook.async_generate_id()
        hass.config_entries.async_update_entry(
            entry, data={**entry.data, CONF_BLE_WEBHOOK_ID: webhook_id}
        )

    scanner, cancel_scanner = async_register_scanner(hass, entry)
    entry.async_on_unload(cancel_scanner)

    webhook.async_register(
        hass, DOMAIN, "Koti BLE Proxy", webhook_id, async_webhook_handler_for(scanner)
    )
    entry.async_on_unload(lambda: webhook.async_unregister(hass, webhook_id))

    if await coordinator.send_command("setBleWebhook", webhookId=webhook_id):
        return

    # The tablet's REST server can take 15+ seconds to cold-boot after a
    # fresh install/reboot (same race documented on the async_refresh()
    # call above) — a delivery attempt landing in that window would
    # otherwise never be retried until the next full HA restart/reload,
    # silently leaving the Bluetooth proxy pointed nowhere. Piggyback on
    # the coordinator's own recurring poll (which already has its own
    # backoff for an unreachable tablet) and keep retrying until it lands.
    remove_listener: CALLBACK_TYPE | None = None

    async def _async_retry_delivery() -> None:
        if await coordinator.send_command("setBleWebhook", webhookId=webhook_id):
            _LOGGER.info("Delivered BLE webhook id to %s after a retry", entry.title)
            if remove_listener:
                remove_listener()

    @hass_callback
    def _on_coordinator_update() -> None:
        hass.async_create_task(_async_retry_delivery())

    remove_listener = coordinator.async_add_listener(_on_coordinator_update)
    entry.async_on_unload(remove_listener)


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unload_ok:
        coordinator: KotiCoordinator = hass.data[DOMAIN].pop(entry.entry_id)
        await coordinator.async_shutdown()
    return unload_ok


async def _async_migrate_device_id_if_needed(
    hass: HomeAssistant, entry: ConfigEntry, reported_id: str
) -> None:
    """Re-key the config entry + entity if the tablet's self-reported device
    id ever no longer matches what this entry was set up with — instead of
    leaving a stale identifier that would register as a second, phantom
    device on next discovery. Koti's device id is a random value the app
    generates once and stores locally (see lib/store/settings_store.dart),
    not an OS-scoped id like Android's ANDROID_ID, but this covers it if a
    future app version ever changes how that id is derived (e.g. moving to
    a hardware-backed id for extra stability across reinstalls) — the same
    situation dashie-ha-integration's own device-id migration handles for
    its ANDROID_ID -> stableDeviceID transition.

    Idempotent: a no-op once entry.data[CONF_ID] already matches.
    """
    current_id = entry.data.get(CONF_ID)
    if not current_id or current_id == reported_id:
        return

    # Bail out if another config entry already claims the reported id —
    # migrating would collide. Log a warning so the user can resolve the
    # duplicate manually rather than silently losing one entry's identity.
    for other in hass.config_entries.async_entries(DOMAIN):
        if other.entry_id == entry.entry_id:
            continue
        if other.unique_id == reported_id or other.data.get(CONF_ID) == reported_id:
            _LOGGER.warning(
                "Cannot migrate device id for %s (%s -> %s): config entry %s "
                "already uses that id. Delete one of the duplicate entries "
                "manually.",
                entry.title,
                current_id,
                reported_id,
                other.entry_id,
            )
            return

    _LOGGER.info(
        "Migrating device id for %s: %s -> %s", entry.title, current_id, reported_id
    )

    entity_registry = er.async_get(hass)
    for ent in list(er.async_entries_for_config_entry(entity_registry, entry.entry_id)):
        if ent.unique_id == current_id:
            entity_registry.async_update_entity(ent.entity_id, new_unique_id=reported_id)

    device_registry = dr.async_get(hass)
    device = device_registry.async_get_device(identifiers={(DOMAIN, current_id)})
    if device:
        device_registry.async_update_device(
            device.id, new_identifiers={(DOMAIN, reported_id)}
        )

    hass.config_entries.async_update_entry(
        entry,
        unique_id=reported_id,
        data={**entry.data, CONF_ID: reported_id},
    )
    _LOGGER.info("Device id migration complete for %s", entry.title)


def _async_link_sibling_devices(hass: HomeAssistant, entry: ConfigEntry) -> None:
    """Nest this tablet's Music Assistant (Sendspin) Device under this
    integration's own Device, so opening the Koti Device leads to it too
    instead of it sitting as an unrelated entry elsewhere in Settings >
    Devices.

    This can't be a real merge (that only happens when two Devices share an
    identical `connections` entry) — Music Assistant never reports this
    tablet's MAC, only its own domain-specific id, so the best available
    link is `via_device_id` (the same mechanism Home Assistant's own
    `bluetooth` integration uses to nest a Bluetooth-proxy Device under its
    parent). Safe to call on every setup: a no-op once already linked, and
    never touches a device it doesn't find.
    """
    device_registry = dr.async_get(hass)
    koti_device = device_registry.async_get_device(identifiers={(DOMAIN, entry.data[CONF_ID])})
    if not koti_device:
        return

    sibling = device_registry.async_get_device(
        identifiers={(MUSIC_ASSISTANT_DOMAIN, f"{MUSIC_ASSISTANT_ID_PREFIX}{entry.data[CONF_ID]}")}
    )
    if sibling and sibling.via_device_id != koti_device.id:
        device_registry.async_update_device(sibling.id, via_device_id=koti_device.id)
