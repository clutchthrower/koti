"""DataUpdateCoordinator for a Koti player."""

from __future__ import annotations

import asyncio
import logging
from datetime import timedelta

import aiohttp

from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import DEFAULT_SCAN_INTERVAL

_LOGGER = logging.getLogger(__name__)

# Backoff after consecutive failures, matching the tolerance a tablet that's
# briefly asleep or off Wi-Fi needs: quick retries at first, then back off
# so a long-gone device doesn't spam the network.
NORMAL_INTERVAL = DEFAULT_SCAN_INTERVAL
MEDIUM_BACKOFF = 60
MAX_BACKOFF = 300
MEDIUM_BACKOFF_THRESHOLD = 4
MAX_BACKOFF_THRESHOLD = 12

HTTP_TIMEOUT = aiohttp.ClientTimeout(total=10, connect=5)


class KotiCoordinator(DataUpdateCoordinator):
    """Polls a Koti player's /info endpoint and sends it commands."""

    def __init__(self, hass: HomeAssistant, host: str, port: int) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=f"Koti {host}",
            update_interval=timedelta(seconds=NORMAL_INTERVAL),
        )
        self.host = host
        self.port = port
        self.base_url = f"http://{host}:{port}"
        self._session: aiohttp.ClientSession | None = None
        self._consecutive_failures = 0

    async def _get_session(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(timeout=HTTP_TIMEOUT)
        return self._session

    async def async_shutdown(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()
            self._session = None
        await super().async_shutdown()

    def _apply_backoff(self) -> None:
        self._consecutive_failures += 1
        if self._consecutive_failures <= MEDIUM_BACKOFF_THRESHOLD:
            interval = NORMAL_INTERVAL
        elif self._consecutive_failures <= MAX_BACKOFF_THRESHOLD:
            interval = MEDIUM_BACKOFF
        else:
            interval = MAX_BACKOFF
        self.update_interval = timedelta(seconds=interval)

    def _reset_backoff(self) -> None:
        if self._consecutive_failures > 0:
            _LOGGER.info("Reconnected to Koti player at %s", self.host)
        self._consecutive_failures = 0
        self.update_interval = timedelta(seconds=NORMAL_INTERVAL)

    async def _async_update_data(self) -> dict:
        session = await self._get_session()
        try:
            async with asyncio.timeout(10):
                async with session.get(f"{self.base_url}/?cmd=deviceInfo") as response:
                    response.raise_for_status()
                    data = await response.json()
        except (TimeoutError, aiohttp.ClientError) as err:
            self._apply_backoff()
            raise UpdateFailed(f"Koti player at {self.host} unreachable: {err}") from err
        self._reset_backoff()
        return data

    async def send_command(self, command: str, **kwargs) -> bool:
        """Sends a command, ignoring the response body — commands are
        fire-and-forget; the next poll picks up the resulting state."""
        try:
            session = await self._get_session()
            params = {"cmd": command, **{k: str(v) for k, v in kwargs.items()}}
            async with session.get(f"{self.base_url}/", params=params) as response:
                return response.status == 200
        except (TimeoutError, aiohttp.ClientError) as err:
            _LOGGER.warning("Command %s to %s failed: %s", command, self.host, err)
            return False
