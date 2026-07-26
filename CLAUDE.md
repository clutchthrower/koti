# Project Context: Koti (Ultra-Low RAM Dashboard App)

## Overview
This project converts the visual identity and minimalist layout of the [willsanderson/Hemma](https://github.com) Home Assistant dashboard into a highly optimized, compiled native Android application. 

The primary target runtime is an older tablet running **Android 7.0 (API Level 24)**. To protect limited hardware resources, this application must completely avoid heavy web browsers, WebViews, and high-frequency DOM repaints. The UI must be compiled directly to machine code, using the local network strictly for raw, lightweight data exchanges.

This project will be available as opensource to anyone on Github, so no private details or hardwired tokens/accounts/ect.

## Architecture & Development Environment
- **Development OS**: Ubuntu 24.04 LTS
- **Target OS**: Android 7.0 (API Level 24)
- **Framework**: Flutter (Dart)
- **State Management**: Simple, reactive low-overhead patterns (`ValueNotifier` or `Provider`)
- **Network Pipeline**: Direct, single persistent connection via `web_socket_channel`

+-------------------------------------------------------+
| Flutter Native App |
| (Local Vector Graphics, Compiled Layout Engine) |
+---------------------------+---------------------------+
| Direct Local Wi-Fi
| Persistent WebSocket Frame
v
+-------------------------------------------------------+
| Home Assistant Core |
| (Local Smart Home Hub on Network) |
+-------------------------------------------------------+

## Hemma Visual Design Translations
To preserve the Apple-Home inspired aesthetic of the Hemma repository without causing high CPU spikes on legacy hardware, the following design translation rules apply:
1. **Limit Real-Time Blurs**: Limit amount of computationally expensive graphic backdrop filter blurs (`BackdropFilter`). Try to replicate the "frosted glass" style first using solid, translucent container background values (e.g., dark colors with low opacity: `Colors.black.withOpacity(0.4)`).
2. **Asset Locality**: All room images, graphical templates, layout structures, and icon fonts must reside permanently in the local application bundle folder (`assets/`). No interface files or images may be loaded over Wi-Fi.
3. **Atomic Repaints**: Implement selective widget rebuilding. When a Home Assistant state change arrives over the WebSocket connection (e.g., `light.living_room` turned on), only that specific button widget should redraw.

## Home Assistant Connection Handshake
The app connects directly to `ws://YOUR_HOME_ASSISTANT_IP:8123/api/websocket`. Code generations must account for the standard auth handshake protocol:
1. **Receive Invitation**: `{ "type": "auth_required", "ha_version": "..." }`
2. **Send Credentials**: `{ "type": "auth", "access_token": "LONG_LIVED_ACCESS_TOKEN" }`
3. **Handle Confirmation**: `{ "type": "auth_ok", "ha_version": "..." }`
4. **Subscribe to States**: Request `get_states` to paint the layout initially, then listen to `subscribe_events` with `state_changed` to stream atomic updates.
5. **Auto Discovery**: When onboarding, should scan network for any local Home Assistant instance, and implement a log in solution to grab the Long-Lived Access Token

## Assistant Development Directives
When generating code, modifying configurations, or designing interfaces via `claude-code`:
1. Ensure all code compiles cleanly within **Dart and Flutter SDK constraints targeting API Level 24**.
2. Avoid external dependencies or massive UI library packages; maximize vanilla Flutter widgets to keep the compiled binary footprint under 30MB.
3. Include robust, silent auto-reconnection logic for the WebSocket stream to handle dropped Wi-Fi signals elegantly without crashing the app framework.
4. Provide absolute, clear terminal execution guidelines to the user, who is working inside an Ubuntu 24.04 command-line tool window.

## Future Feature Ideas
Things I'd like to add to the app later on:
1. Voice Satellite, wake word detection, Local AI

# More in-depth breakdown
Check the local file 'SPECIFICATIONS.md' for more in-depth details for the project
