# Koti — Home Assistant Dashboard for Android Tablets

*Koti is Finnish for "home".*

Koti is a free, native Android app that turns any wall-mounted tablet into a
beautiful smart home dashboard for [Home Assistant](https://www.home-assistant.io/).
It is built with Flutter — not a browser or WebView — so it stays fast and smooth
even on older hardware (Android 7.0 and up).

The look is inspired by the calm, minimal aesthetic of Apple Home.

---

## Features

### Beautiful, room-by-room layout
- Blurred room background photos with large room titles and tab navigation
- Day and night backgrounds that switch automatically
- Glassy "pill" badges summarizing what's active across your home
- A **whole-home view** with aggregated badges and auto-generated cards for
  thermostats, locks, vacuums, pending HA updates, and low-battery devices

### Effortless setup — no typing required
- Automatically finds Home Assistant on your Wi-Fi (no IP address needed)
- Sign in with your normal HA username and password — no token copy-paste
- Rooms and cards are created automatically from your existing HA Areas
- The tablet registers itself as a device in Home Assistant straight away

### Smart home controls built in
Koti includes ready-made cards for the most common device types:

| Card | What it controls |
|---|---|
| **Lights** | On/off, brightness, colour temperature, RGB colour, light groups |
| **Thermostat** | Temperature target, current reading, HVAC mode |
| **Camera** | Live thumbnail (refreshes every 10 s), motion-alert pulse |
| **Curtains / Covers** | Open, close, stop, position slider |
| **Locks** | Lock/unlock with confirmation |
| **Media player** | Playback controls, volume, album art |
| **Vacuum** | Start, stop, return to dock |
| **Humidifier** | On/off, target humidity |
| **Motion sensor** | Active/clear state |
| **Energy sensor** | Current power reading |
| **Doorbell** | Ring alert |
| **Battery overview** | All low-battery devices in one tap |
| **Network** | Download/upload speed and ping |
| **Pending updates** | HA and add-on updates waiting to be installed |

### Edit your dashboard without leaving the app
- Long-press any card, badge, or room title to enter edit mode
- Add, remove, or rename cards and badges
- Set a per-room background photo (choose from bundled photos or your own)
- All changes save instantly — no YAML, no restarts

### Custom cards
Design your own cards as small JSON files — buttons, toggles, sliders,
templates, conditions, and per-card popups. Share them with copy/paste.
Ready-made examples are in [`cards/examples/`](cards/examples/) and the
full format is documented in [`docs/CARD_FORMAT.md`](docs/CARD_FORMAT.md).

### Tablet as a Bluetooth proxy
Turn the tablet into a passive Bluetooth proxy: it relays nearby BLE
advertisements to Home Assistant over Wi-Fi, so BLE trackers/sensors near the
tablet show up in Home Assistant with no extra hardware needed. Registers
directly under the tablet's own existing Koti device — no separate Bluetooth
proxy device, no manual pairing step.

### Tablet as a music speaker
Enable Sendspin in **Settings → Music Assistant** and the tablet appears in
Music Assistant's player list automatically. No player provider to install,
nothing to configure on the Music Assistant side.

### Wall-tablet niceties
- **Fullscreen / kiosk mode** — hides the status bar and navigation bar
- **Screensaver** with a clock, weather, and burn-in protection
  (including a DVD-logo bounce mode)
- **Screen brightness control** from within the app
- **In-app updates** — when a new version is released, the tablet prompts
  you to update automatically (no manual sideloading after the first install)

---

## Install

1. Download the APK from the [**latest release**](../../releases/latest).
2. On your tablet, enable *Install unknown apps* for your browser or file
   manager, then open the APK to install it.
3. Launch Koti — it will find Home Assistant on your network and walk you
   through sign-in. Your rooms and cards are set up automatically.

After the first install, Koti notifies of updates whenever a new version is
published here.

> **Minimum requirement:** Android 7.0 (API 24) or newer.

---

## Optional: Home Assistant integration

This gives Home Assistant direct control over the tablet. It is not required
for the dashboard to work.

**Install:**
Copy the [`custom_components/koti`](custom_components/koti) folder from this
repo into your HA config's `custom_components/` directory and restart Home
Assistant. The tablet advertises itself automatically — HA will show a
discovery notification. Approve it and a device appears with:

- Media controls
- Battery level and charging state sensors
- App version and update sensor
- **Restart App** button — restarts the Koti app remotely
- **Reboot Device** button — reboots the whole tablet (requires Device Owner setup, see below)

> **HACS:** Not yet available — manual install only for now.

### Optional: enable remote reboot

Android only allows a full device reboot from an app that has been set as
**Device Owner**. This must be done once, before adding any Google account to
the tablet:

```bash
adb shell dpm set-device-owner com.koti.dashboard/.KotiDeviceAdminReceiver
```

Without this, the *Reboot Device* button is visible but reports that it is
unavailable rather than silently failing. *Restart App* works without any
extra setup.

---

## Credits

Design, icons, fonts, and demo photos adapted from
[willsanderson/Hemma](https://github.com/willsanderson/Hemma) (MIT).
See [`NOTICE.md`](NOTICE.md) for full attribution.

---

## For developers

```bash
cp .env.example .env   # required to exist; fill in or leave blank
flutter pub get
flutter run
```
