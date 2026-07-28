"""Bluetooth proxy support for Koti.

Registers this tablet's own BLE scan data directly with Home Assistant's
Bluetooth stack via a webhook, under this same integration's Device —
instead of the tablet implementing the actual ESPHome native-API protocol
(which is what used to make HA's own `esphome` integration auto-discover
the tablet as a second, unrelated Device; see git history for
`lib/api/esphome_server.dart`, since removed).

Passive/presence-only, matching the tablet's own capability: nothing here
ever accepts a GATT connection through the tablet, only relays
advertisements it already observed.
"""

from __future__ import annotations

import base64
import logging
import time
from typing import Any

from aiohttp.web import Request, Response, json_response
from bluetooth_data_tools import monotonic_time_coarse

from homeassistant.components import bluetooth
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import CALLBACK_TYPE, HomeAssistant

_LOGGER = logging.getLogger(__name__)


class KotiBleScanner(bluetooth.BaseHaRemoteScanner):
    """Remote scanner fed by this tablet's own native BLE scan.

    `connectable=False` — the tablet only ever relays raw advertisements it
    already saw over the air, never a live GATT connection.
    """

    def __init__(self, entry: ConfigEntry) -> None:
        connector = bluetooth.HaBluetoothConnector(
            client=None, source=entry.entry_id, can_connect=lambda: False
        )
        super().__init__(entry.entry_id, entry.title, connector, False)

    def async_process_batch(self, batch: list[dict[str, Any]]) -> None:
        """Feed one webhook POST's worth of advertisements into HA.

        Each item is `{address, rssi, raw (base64 AD structures), timestamp
        (client epoch ms when captured)}` — see lib/api/ble_proxy.dart.
        `_async_on_raw_advertisement` does the actual AD-structure parsing
        (via `bluetooth_data_tools`), the same helper a raw-advertisements
        scanner like ESPHome's own uses.
        """
        now_monotonic = monotonic_time_coarse()
        now_wall = time.time()
        for item in batch:
            address = item.get("address")
            raw_b64 = item.get("raw")
            if not address or not raw_b64:
                continue
            try:
                raw = base64.b64decode(raw_b64)
            except (ValueError, TypeError):
                continue
            sent_wall = (item.get("timestamp") or 0) / 1000.0
            advertisement_monotonic_time = now_monotonic - (now_wall - sent_wall)
            self._async_on_raw_advertisement(
                address,
                item.get("rssi", 0) or 0,
                raw,
                {},
                advertisement_monotonic_time,
            )


def async_register_scanner(hass: HomeAssistant, entry: ConfigEntry) -> tuple[KotiBleScanner, CALLBACK_TYPE]:
    """Register the scanner with HA's Bluetooth stack.

    Deliberately omits `source_domain`/`source_config_entry_id`/
    `source_device_id` — passing those (as HA's own `esphome` integration
    does) triggers an automatic `INTEGRATION_DISCOVERY` config flow that
    creates a SEPARATE `bluetooth`-domain Device for the scanner, which is
    exactly the extra-device problem this whole module exists to avoid.
    Confirmed by reading `HomeAssistantBluetoothManager.
    async_register_hass_scanner` directly: that flow only fires when both
    `source_domain` and `source_config_entry_id` are truthy.
    """
    scanner = KotiBleScanner(entry)
    unregister = bluetooth.async_register_scanner(hass, scanner)
    cancel_setup = scanner.async_setup()

    def _unload() -> None:
        cancel_setup()
        unregister()

    return scanner, _unload


def async_webhook_handler_for(scanner: KotiBleScanner):
    """Builds the aiohttp webhook handler closing over `scanner`."""

    async def _handle(hass: HomeAssistant, webhook_id: str, request: Request) -> Response:
        try:
            batch = await request.json()
        except ValueError:
            return json_response({"status": "error"}, status=400)
        if not isinstance(batch, list):
            return json_response({"status": "error"}, status=400)
        scanner.async_process_batch(batch)
        return json_response({"status": "ok"})

    return _handle
