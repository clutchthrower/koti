"""Constants for the Koti integration."""

DOMAIN = "koti"

DEFAULT_PORT = 8127
DEFAULT_SCAN_INTERVAL = 10  # seconds

CONF_ID = "id"
# Persisted once per config entry (minted on first setup) — the webhook a
# tablet's own BLE scan data gets POSTed to. See bluetooth.py.
CONF_BLE_WEBHOOK_ID = "ble_webhook_id"

# Music Assistant registers its own Sendspin-mirrored Device for the *same*
# physical tablet, keyed on this same device id — but with no MAC or other
# `connections` in common, so it never auto-merges with this integration's
# own Device (see _async_link_sibling_devices in __init__.py).
MUSIC_ASSISTANT_DOMAIN = "music_assistant"
# Confirmed live (core.device_registry): a Sendspin player's HA-mirrored
# device identifier is "up" + the same device id this app reports as its
# Sendspin client_id / Koti CONF_ID.
MUSIC_ASSISTANT_ID_PREFIX = "up"
