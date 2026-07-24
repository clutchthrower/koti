package com.koti.dashboard

import android.app.admin.DeviceAdminReceiver

/**
 * Required for Device Owner mode (`adb shell dpm set-device-owner
 * com.koti.dashboard/.KotiDeviceAdminReceiver`, run before any Google
 * account is added to the tablet), which is what lets [MainActivity]'s
 * `rebootDevice` native call actually succeed — a normal Android app has no
 * way to reboot the device otherwise. No overrides needed: this app only
 * ever checks device-owner status itself, it doesn't use any of the
 * interactive device-admin policy prompts this receiver could otherwise
 * trigger.
 */
class KotiDeviceAdminReceiver : DeviceAdminReceiver()
