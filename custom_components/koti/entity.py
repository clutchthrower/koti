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
        # A stable, locally-administered MAC derived from the device id
        # (see mac.py) — not used for any cross-integration Device merge
        # today (the Bluetooth proxy registers its own scanner directly
        # under this same Device via bluetooth.py, no separate MAC-matched
        # Device involved), just a real identifier for anything else that
        # might recognize this tablet by its MAC in the future.
        connections={(CONNECTION_NETWORK_MAC, mac_from(entry.unique_id))},
        name=device_name,
        manufacturer="Koti",
        model="Koti Tablet",
        # Clickable link on the device page to the tablet's own REST API.
        configuration_url=f"http://{entry.data['host']}:{entry.data['port']}",
    )
