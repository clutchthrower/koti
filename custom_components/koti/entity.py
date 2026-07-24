"""Shared Home Assistant device_info construction for every Koti entity.

Every entity across every platform (media_player, sensor, binary_sensor,
update, button) must use the exact same `identifiers`/`connections` to land
on one Device page — not a new one per platform.
"""

from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.helpers.device_registry import CONNECTION_NETWORK_MAC, DeviceInfo

from .const import DOMAIN
from .mac import mac_from


def device_info_for(entry: ConfigEntry) -> DeviceInfo:
    """Build this tablet's shared DeviceInfo from its config entry."""
    device_name = entry.data.get("name", entry.title)
    return DeviceInfo(
        identifiers={(DOMAIN, entry.unique_id)},
        # Same MAC the tablet's ESPHome Bluetooth-proxy registration uses —
        # sharing a `connections` entry is how Home Assistant's device
        # registry recognizes this and the ESPHome device as the same
        # physical tablet and merges them into one Device instead of two.
        connections={(CONNECTION_NETWORK_MAC, mac_from(entry.unique_id))},
        name=device_name,
        manufacturer="Koti",
        model="Koti Tablet",
        # Clickable link on the device page to the tablet's own REST API.
        configuration_url=f"http://{entry.data['host']}:{entry.data['port']}",
    )
