"""Media player platform for Koti players."""

from __future__ import annotations

from collections.abc import Callable

from homeassistant.components.media_player import (
    MediaPlayerEntity,
    MediaPlayerEntityFeature,
    MediaPlayerState,
    MediaType,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import Event, EventStateChangedData, HomeAssistant, State, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.event import async_track_state_change_event
from homeassistant.helpers.update_coordinator import CoordinatorEntity
from homeassistant.util import dt as dt_util

from .const import DOMAIN
from .coordinator import KotiCoordinator
from .entity import device_info_for

# State/attributes mirrored verbatim from the Music-Assistant-mirrored
# sibling entity while a Sendspin session is live — see _mirror_state.
_MIRRORED_ATTRS = (
    "media_title",
    "media_artist",
    "media_album_name",
    "media_duration",
    "shuffle",
    "repeat",
)

SUPPORTED_FEATURES = (
    MediaPlayerEntityFeature.PLAY_MEDIA
    | MediaPlayerEntityFeature.STOP
    | MediaPlayerEntityFeature.PAUSE
    | MediaPlayerEntityFeature.PLAY
    | MediaPlayerEntityFeature.SEEK
    | MediaPlayerEntityFeature.VOLUME_SET
    | MediaPlayerEntityFeature.VOLUME_MUTE
    | MediaPlayerEntityFeature.NEXT_TRACK
    | MediaPlayerEntityFeature.PREVIOUS_TRACK
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
        # The app's own default device name (and the naming convention most
        # users land on) already starts with "Koti" — e.g. "Koti Dining
        # Room Tablet" — so blindly prepending it again produced a garbled
        # "Koti Koti Dining Room Tablet" display name.
        prefix = "" if device_name.lower().startswith("koti") else "Koti "
        self._attr_name = f"{prefix}{device_name}"
        # Deliberately NOT entry.unique_id verbatim. Music Assistant mirrors
        # a Sendspin client into HA as a "universal_player" entity whose own
        # unique_id is "up" + a device key derived from the raw player_id
        # (which for Sendspin is exactly our client_id, itself set to this
        # same entry.unique_id) — confirmed by reading MA's actual installed
        # source (universal_player/provider.py: `_get_device_key_from_players`
        # falls back to `player_id.replace(":", "").replace("-", "").lower()`
        # when no MAC/UUID identifier exists, then
        # `f"{UNIVERSAL_PLAYER_PREFIX}{device_key}"` with
        # UNIVERSAL_PLAYER_PREFIX = "up") and confirmed live against this
        # integration's own MA server (settings.json literally has
        # "up<device_id>" as the mirrored player's id). Matching that string
        # exactly — rather than the bare entry.unique_id — is what lets the
        # app's own dedup (music_players_popup.dart's _dedupedPlayerIds,
        # which groups entities by shared unique_id) recognize this entity
        # and MA's mirrored one as the same physical speaker.
        self._attr_unique_id = f"up{entry.unique_id}"
        self._attr_device_info = device_info_for(entry)
        # The Sendspin/Music-Assistant-mirrored sibling entity that shares
        # this same unique_id (see the comment above) — resolved lazily
        # since it may not exist in the registry yet (Sendspin only
        # registers with MA once the tablet actually connects). Set once
        # found in _ensure_sendspin_listener(); see its own docstring for
        # why this entity can't derive play/pause/track state on its own.
        self._sendspin_entity_id: str | None = None
        self._unsub_sendspin_listener: Callable[[], None] | None = None
        # The tablet's volume is just a physical STREAM_MUSIC level (see
        # setAudioVolume/MainActivity.kt) — there's no separate hardware
        # mute, so this remembers what to restore to on unmute.
        self._pre_mute_volume: float | None = None
        self._update_from_coordinator()

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        self._ensure_sendspin_listener()

    async def async_will_remove_from_hass(self) -> None:
        if self._unsub_sendspin_listener is not None:
            self._unsub_sendspin_listener()
            self._unsub_sendspin_listener = None
        await super().async_will_remove_from_hass()

    def _ensure_sendspin_listener(self) -> None:
        """Finds and subscribes to the Music-Assistant-mirrored sibling
        entity for this same physical tablet, if it exists yet.

        This entity's own REST API (KotiCoordinator's poll) only ever knows
        whether *its own* direct-URL just_audio playback is active — the
        Sendspin protocol streams raw PCM with no track metadata, so
        nothing about what Music Assistant is actually playing (state,
        title, artist, position...) is knowable from the tablet's own side
        at all. Music Assistant's own mirrored entity is the only place
        that ever knows it — so once Sendspin's connected, this entity's
        displayed state/attributes are mirrored from that sibling entity's
        HA state instead of being derived locally. Without this, this
        integration's own media_player looked permanently idle/blank the
        moment a Sendspin session took over, since nothing here ever fed it
        real state.
        """
        if self._sendspin_entity_id is not None:
            return
        registry = er.async_get(self.hass)
        for candidate in registry.entities.values():
            if (
                candidate.platform == "music_assistant"
                and candidate.domain == "media_player"
                and candidate.unique_id == self._attr_unique_id
            ):
                self._sendspin_entity_id = candidate.entity_id
                break
        if self._sendspin_entity_id is None:
            return
        self._unsub_sendspin_listener = async_track_state_change_event(
            self.hass, [self._sendspin_entity_id], self._handle_sendspin_state_change
        )
        self._mirror_state(self.hass.states.get(self._sendspin_entity_id))

    @callback
    def _handle_sendspin_state_change(self, event: Event[EventStateChangedData]) -> None:
        self._mirror_state(event.data["new_state"])
        self.async_write_ha_state()

    def _mirror_state(self, source: State | None) -> None:
        if source is None or source.state in ("unavailable", "unknown"):
            return
        self._attr_state = source.state
        for attr in _MIRRORED_ATTRS:
            setattr(self, f"_attr_{attr}", source.attributes.get(attr))
        volume = source.attributes.get("volume_level")
        if volume is not None:
            self._attr_volume_level = volume
        self._attr_is_volume_muted = source.attributes.get("is_volume_muted")
        position = source.attributes.get("media_position")
        if position is not None:
            self._attr_media_position = position
            self._attr_media_position_updated_at = source.attributes.get(
                "media_position_updated_at"
            ) or dt_util.utcnow()

    def _update_from_coordinator(self) -> None:
        data = self.coordinator.data or {}
        if self._sendspin_connected:
            # self.hass is unset on the very first call (from __init__,
            # before this entity's added to hass) — nothing to resolve yet.
            if self.hass is not None:
                self._ensure_sendspin_listener()
            # Real state comes from _mirror_state via the sibling listener
            # once resolved; until it resolves (a brief window right after
            # Sendspin connects, before Music Assistant's own entity shows
            # up in the registry), fall through to at least report PLAYING
            # rather than a stale/misleading IDLE.
            if self._sendspin_entity_id is not None:
                return
            self._attr_state = MediaPlayerState.PLAYING
            return
        # The direct-URL protocol only reports whether a URL is loaded, not
        # whether it's playing vs. paused — so a poll can only ever confirm
        # IDLE; play/pause/stop set the more specific state themselves below.
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

    @property
    def _sendspin_connected(self) -> bool:
        """Whether a Sendspin/Music Assistant session is currently live.

        play/pause/stop mean two different things depending on this: the
        direct-URL just_audio player (this entity's original purpose,
        e.g. playing a doorbell chime via play_media), or the actual music
        Sendspin is streaming. Only one physical speaker exists, so when a
        Sendspin session is connected that's obviously the one the user
        means to control — falls back to the direct-URL commands only
        when nothing's connected. play_media itself is unaffected by this:
        playing a specific URL is always the direct-URL path regardless.
        """
        return bool((self.coordinator.data or {}).get("sendspinConnected"))

    async def async_play_media(self, media_type: str, media_id: str, **kwargs) -> None:
        await self.coordinator.send_command("playSound", url=media_id, stream=4)
        self._attr_state = MediaPlayerState.PLAYING
        await self.coordinator.async_request_refresh()

    async def async_media_stop(self) -> None:
        if self._sendspin_connected:
            await self.coordinator.send_command("sendspinStop")
        else:
            await self.coordinator.send_command("stopSound")
            self._attr_state = MediaPlayerState.IDLE
        await self.coordinator.async_request_refresh()

    async def async_media_pause(self) -> None:
        if self._sendspin_connected:
            await self.coordinator.send_command("sendspinPause")
        else:
            await self.coordinator.send_command("pauseSound")
            self._attr_state = MediaPlayerState.PAUSED
        await self.coordinator.async_request_refresh()

    async def async_media_play(self) -> None:
        if self._sendspin_connected:
            await self.coordinator.send_command("sendspinPlay")
        else:
            await self.coordinator.send_command("resumeSound")
            self._attr_state = MediaPlayerState.PLAYING
        await self.coordinator.async_request_refresh()

    async def async_media_next_track(self) -> None:
        await self.coordinator.send_command("sendspinNext")
        await self.coordinator.async_request_refresh()

    async def async_media_previous_track(self) -> None:
        await self.coordinator.send_command("sendspinPrevious")
        await self.coordinator.async_request_refresh()

    async def async_media_seek(self, position: float) -> None:
        await self.coordinator.send_command("seekSound", position=round(position * 1000))
        await self.coordinator.async_request_refresh()

    async def async_set_volume_level(self, volume: float) -> None:
        await self.coordinator.send_command("setAudioVolume", level=round(volume * 100), stream=4)
        await self.coordinator.async_request_refresh()

    async def async_mute_volume(self, mute: bool) -> None:
        """No discrete mute at the protocol/hardware level — implemented as
        remember-and-zero, restore-on-unmute against the same physical
        volume async_set_volume_level already controls. Applies regardless
        of whether Sendspin's connected, since it's the same underlying
        STREAM_MUSIC level either way, not a per-source software mute.
        """
        if mute:
            self._pre_mute_volume = self.volume_level
            await self.async_set_volume_level(0)
        else:
            await self.async_set_volume_level(self._pre_mute_volume or 0.5)
        self._attr_is_volume_muted = mute
        self.async_write_ha_state()
