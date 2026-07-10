"""Constants for the Koti integration."""

DOMAIN = "koti"

DEFAULT_PORT = 8127
DEFAULT_SCAN_INTERVAL = 10  # seconds

CONF_ID = "id"

# Koti's player speaks the Fully Kiosk Browser REST API (see
# lib/speaker/koti_player_server.dart in the Koti app repo) so it also
# works with Music Assistant's built-in "Fully Kiosk Browser" provider —
# not just this integration. Password is accepted but never checked; this
# device is only reachable on the LAN, matching the rest of this integration.
API_DEVICE_INFO = "deviceInfo"
API_PLAY_SOUND = "playSound"
API_STOP_SOUND = "stopSound"
API_PAUSE_SOUND = "pauseSound"
API_RESUME_SOUND = "resumeSound"
API_SEEK_SOUND = "seekSound"
API_SET_VOLUME = "setAudioVolume"
