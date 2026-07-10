"""Config flow for Koti — auto-discovers players via zeroconf, no setup."""

from __future__ import annotations

from typing import Any

import aiohttp
import voluptuous as vol

from homeassistant.config_entries import ConfigFlow
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.service_info.zeroconf import ZeroconfServiceInfo

from .const import CONF_ID, DEFAULT_PORT, DOMAIN

CONF_HOST = "host"
CONF_PORT = "port"
CONF_NAME = "name"


class KotiConfigFlow(ConfigFlow, domain=DOMAIN):
    """Handles both zeroconf auto-discovery and manual fallback entry."""

    VERSION = 1

    def __init__(self) -> None:
        self._discovered: dict[str, Any] = {}

    async def async_step_zeroconf(
        self, discovery_info: ZeroconfServiceInfo
    ) -> Any:
        device_id = discovery_info.properties.get(CONF_ID)
        name = discovery_info.properties.get(CONF_NAME) or discovery_info.name
        if not device_id:
            return self.async_abort(reason="no_device_id")

        await self.async_set_unique_id(device_id)
        self._abort_if_unique_id_configured(
            updates={
                CONF_HOST: discovery_info.host,
                CONF_PORT: discovery_info.port,
            }
        )

        self._discovered = {
            CONF_HOST: discovery_info.host,
            CONF_PORT: discovery_info.port,
            CONF_ID: device_id,
            CONF_NAME: name,
        }
        self.context["title_placeholders"] = {"name": name}
        return await self.async_step_discovery_confirm()

    async def async_step_discovery_confirm(
        self, user_input: dict[str, Any] | None = None
    ) -> Any:
        if user_input is not None:
            return self.async_create_entry(
                title=self._discovered[CONF_NAME], data=self._discovered
            )

        return self.async_show_form(
            step_id="discovery_confirm",
            description_placeholders={"name": self._discovered[CONF_NAME]},
        )

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> Any:
        errors: dict[str, str] = {}
        if user_input is not None:
            host = user_input[CONF_HOST]
            port = user_input.get(CONF_PORT, DEFAULT_PORT)
            info = await self._try_connect(host, port)
            if info is None:
                errors["base"] = "cannot_connect"
            else:
                device_id = info.get("deviceID", host)
                await self.async_set_unique_id(device_id)
                self._abort_if_unique_id_configured(
                    updates={CONF_HOST: host, CONF_PORT: port}
                )
                name = info.get("deviceName", host)
                return self.async_create_entry(
                    title=name,
                    data={
                        CONF_HOST: host,
                        CONF_PORT: port,
                        CONF_ID: device_id,
                        CONF_NAME: name,
                    },
                )

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_HOST): str,
                    vol.Optional(CONF_PORT, default=DEFAULT_PORT): int,
                }
            ),
            errors=errors,
        )

    async def _try_connect(self, host: str, port: int) -> dict[str, Any] | None:
        session = async_get_clientsession(self.hass)
        try:
            async with session.get(
                f"http://{host}:{port}/?cmd=deviceInfo",
                timeout=aiohttp.ClientTimeout(total=5),
            ) as response:
                if response.status != 200:
                    return None
                return await response.json()
        except (TimeoutError, aiohttp.ClientError):
            return None
