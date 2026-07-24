# Koti

*Koti — Finnish for "home".*

A fast, native Android dashboard for [Home Assistant](https://www.home-assistant.io/),
built for old wall-mounted tablets. It recreates the calm, Apple-Home-inspired look of the
[willsanderson/Hemma](https://github.com/willsanderson/Hemma) Lovelace dashboard (which
inspired this project, and its former name "Hemma Native") as a compiled Flutter app — no WebView, no browser, no per-frame blur — so it stays smooth on
hardware as old as Android 7.0 (API 24).

## Features

- **The Hemma look**: blurred room photos, big room titles, badge pills, bottom card
  strip, room-name tab navigation — day/night backgrounds switch with the sun.
- **Zero-typing onboarding**: scans the LAN for Home Assistant (mDNS), signs in with your
  HA username/password (no token copy-paste), auto-creates rooms from your HA Areas, and
  registers the tablet as a device in HA (`mobile_app`).
- **Homescreen-style editing**: long-press any card, badge, or title to enter edit mode —
  add/remove/rename cards and badges, set per-room backgrounds (bundled photos or your own),
  all saved instantly.
- **Whole-home view**: aggregated badges plus auto-derived cards for thermostats, locks,
  vacuums, pending updates, and battery levels.
- **Bluetooth proxy**: optionally relays nearby BLE advertisements to Home Assistant using
  the ESPHome native API — HA discovers the tablet on *Devices & services* like any
  ESPHome Bluetooth proxy.
- **Tablet as a speaker**: enable Sendspin in Settings → Music Assistant and the tablet
  shows up in Music Assistant's player list automatically — Sendspin is Music Assistant's
  own built-in synchronized-audio protocol, so there's no player provider to install and
  nothing to configure on the MA side at all. The tablet also always runs a small REST API
  that [custom_components/koti](custom_components/koti) uses for direct control from Home
  Assistant itself (independent of Music Assistant) — and that's compatible with Music
  Assistant's built-in "Fully Kiosk Browser" provider too, for anyone who'd rather use that.
- **Wall-tablet niceties**: fullscreen mode, launcher (home-app) mode, screensaver with
  clock/weather and burn-in protection (including a DVD-logo bounce), device brightness
  control, and in-app updates from GitHub Releases.
- **Custom cards**: design your own cards as small JSON files — templates, conditions,
  buttons, sliders, toggles, and per-card popups — and share them with copy/paste. See
  [docs/CARD_FORMAT.md](docs/CARD_FORMAT.md) and ready-made examples in
  [cards/examples/](cards/examples/).

## Install

Grab the APK from the [latest release](../../releases/latest) and sideload it
(enable *Install unknown apps* for your browser/file manager). On first launch the app
finds Home Assistant on your Wi-Fi and walks you through sign-in. Once installed, the app
updates itself from new releases here.

### Home Assistant integration (optional, for direct control)

Not on HACS yet — install manually: copy `custom_components/koti` from this repo into your
HA config's `custom_components/` folder and restart Home Assistant. The tablet advertises
itself automatically, no setup needed in the app — HA notifies you when it discovers the
tablet; approve it and a device appears with: a `media_player.koti_{name}` entity (direct
play/pause/next/previous/volume control — routes to whatever Music Assistant/Sendspin
session is connected when there is one, or the tablet's own direct-URL playback
otherwise), battery level and charging sensors, an app-version/update sensor, and
"Restart App"/"Reboot Device" buttons.

**Reboot Device** only works if the tablet has been set up as a
[Device Owner](https://developer.android.com/work/dpc/build-dpc#do) — a normal Android app
has no way to reboot the device otherwise. This is optional and per-tablet: run, before
adding any Google account to the tablet,
```
adb shell dpm set-device-owner com.koti.dashboard/.KotiDeviceAdminReceiver
```
Without this, the button still appears but reports it isn't available rather than doing
nothing silently. "Restart App" (just this app, not the whole device) needs no setup at all.

## Development

```bash
cp .env.example .env   # required to exist (it's a declared asset); fill in or leave as-is
flutter pub get
flutter run
```

- `.env` lets onboarding screens offer a one-tap dev fill of your HA URL/token. It is
  gitignored and never committed.
- `tool/` holds host-side sanity checks that run against a real HA instance
  (`dart run tool/provision_check.dart`, `tool/esphome_proxy_check.dart`, …).

### Releasing

Actions tab → **Release** → *Run workflow* → enter a version like `1.1.0` (plus optional
notes). CI bumps `pubspec.yaml`, runs the tests, builds a signed APK (keystore lives in
repo secrets), tags `v1.1.0`, and publishes the release — tablets show a blocking update
screen within 6 hours.

Manual fallback: bump `version:` in `pubspec.yaml`, `flutter build apk --release`
(signing from the untracked `android/key.properties`), then create a `vX.Y.Z` release
with the APK attached.

## Credits

Design, icons, fonts, and demo photos adapted from
[willsanderson/Hemma](https://github.com/willsanderson/Hemma) (MIT) — see `NOTICE.md`.
