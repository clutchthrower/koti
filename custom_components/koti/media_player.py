"""Media player platform for Koti players."""

from __future__ import annotations

from homeassistant.components.media_player import (
    MediaPlayerEntity,
    MediaPlayerEntityFeature,
    MediaPlayerState,
    MediaType,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.device_registry import CONNECTION_NETWORK_MAC, DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity
from homeassistant.util import dt as dt_util

from .const import DOMAIN
from .coordinator import KotiCoordinator
from .mac import mac_from

SUPPORTED_FEATURES = (
    MediaPlayerEntityFeature.PLAY_MEDIA
    | MediaPlayerEntityFeature.STOP
    | MediaPlayerEntityFeature.PAUSE
    | MediaPlayerEntityFeature.PLAY
    | MediaPlayerEntityFeature.SEEK
    | MediaPlayerEntityFeature.VOLUME_SET
)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    coordinator: KotiCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([KotiMediaPlayer(coordinator, entry)])


class KotiMediaPlayer(CoordinatorEntity[KotiCoordinator], MediaPlayerEntity):
    """A Koti tablet acting as a Music Assistant player."""

    # Music Assistant's own player (either its built-in "Fully Kiosk Browser"
    # provider, or the Koti player provider) names its mirrored HA entity
    # after this same device's reported name (deviceName), with no prefix.
    # Explicitly naming this one "Koti {name}" instead of leaving it
    # has_entity_name-unnamed keeps it out of that same entity_id slug
    # entirely — media_player.koti_{name} vs. MA's media_player.{name} —
    # so the two read as clean, distinctly-purposed entities (direct REST
    # control vs. full Music Assistant control) instead of one looking like
    # an accidental duplicate of the other with an opaque "_2", or a
    # confusing "Direct Control" suffix bolted onto the device's own name.
    _attr_has_entity_name = False
    _attr_supported_features = SUPPORTED_FEATURES
    _attr_media_content_type = MediaType.MUSIC

    def __init__(self, coordinator: KotiCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._entry = entry
        device_name = entry.data.get("name", entry.title)
        self._attr_name = f"Koti {device_name}"
        self._attr_unique_id = entry.unique_id
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.unique_id)},
            # Same MAC the tablet's ESPHome Bluetooth-proxy registration
            # uses — sharing a `connections` entry is how Home Assistant's
            # device registry recognizes this and the ESPHome device as the
            # same physical tablet and merges them into one Device instead
            # of two.
            connections={(CONNECTION_NETWORK_MAC, mac_from(entry.unique_id))},
            name=device_name,
            manufacturer="Koti",
            model="Koti Tablet",
            # Clickable link on the device page to the tablet's own REST API.
            configuration_url=f"http://{entry.data['host']}:{entry.data['port']}",
        )
        self._update_from_coordinator()

    def _update_from_coordinator(self) -> None:
        data = self.coordinator.data or {}
        # The protocol only reports whether a URL is loaded, not whether
        # it's playing vs. paused — so a poll can only ever confirm IDLE;
        # play/pause/stop set the more specific state themselves below.
        if not data.get("soundUrlPlaying"):
            self._attr_state = MediaPlayerState.IDLE
        elif self._attr_state not in (MediaPlayerState.PLAYING, MediaPlayerState.PAUSED):
            self._attr_state = MediaPlayerState.PLAYING
        volume = data.get("audioVolume")
        self._attr_volume_level = volume / 100 if volume is not None else None
        position = data.get("audioPosition")
        if position is not None:
            self._attr_media_position = position / 1000
            self._attr_media_position_updated_at = dt_util.utcnow()

    def _handle_coordinator_update(self) -> None:
        self._update_from_coordinator()
        super()._handle_coordinator_update()

    async def async_play_media(self, media_type: str, media_id: str, **kwargs) -> None:
        await self.coordinator.send_command("playSound", url=media_id, stream=4)
        self._attr_state = MediaPlayerState.PLAYING
        await self.coordinator.async_request_refresh()

    async def async_media_stop(self) -> None:
        await self.coordinator.send_command("stopSound")
        self._attr_state = MediaPlayerState.IDLE
        await self.coordinator.async_request_refresh()

    async def async_media_pause(self) -> None:
        await self.coordinator.send_command("pauseSound")
        self._attr_state = MediaPlayerState.PAUSED
        await self.coordinator.async_request_refresh()

    async def async_media_play(self) -> None:
        await self.coordinator.send_command("resumeSound")
        self._attr_state = MediaPlayerState.PLAYING
        await self.coordinator.async_request_refresh()

    async def async_media_seek(self, position: float) -> None:
        await self.coordinator.send_command("seekSound", position=round(position * 1000))
        await self.coordinator.async_request_refresh()

    async def async_set_volume_level(self, volume: float) -> None:
        await self.coordinator.send_command("setAudioVolume", level=round(volume * 100), stream=4)
        await self.coordinator.async_request_refresh()
