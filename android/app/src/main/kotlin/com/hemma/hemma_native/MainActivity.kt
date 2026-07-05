package com.hemma.hemma_native

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bleSink: EventChannel.EventSink? = null
    private var scanCallback: ScanCallback? = null
    private var nsdManager: NsdManager? = null
    private var nsdListener: NsdManager.RegistrationListener? = null

    private fun blePermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= 31)
            arrayOf(Manifest.permission.BLUETOOTH_SCAN)
        else
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun hasBlePermissions(): Boolean = blePermissions().all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    // Starts a passive-ish BLE scan streaming raw advertisements to Dart,
    // and advertises the ESPHome API service over mDNS so Home Assistant
    // discovers the tablet as a Bluetooth proxy.
    private fun startBleProxy(name: String, friendlyName: String, mac: String, port: Int): String {
        if (!hasBlePermissions()) {
            ActivityCompat.requestPermissions(this, blePermissions(), 4711)
            return "permission_requested"
        }
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        if (adapter == null || !adapter.isEnabled) return "bluetooth_off"
        val scanner = adapter.bluetoothLeScanner ?: return "bluetooth_off"

        if (scanCallback == null) {
            scanCallback = object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    val bytes = result.scanRecord?.bytes ?: return
                    val payload = mapOf(
                        "address" to result.device.address,
                        "rssi" to result.rssi,
                        "data" to bytes
                    )
                    runOnUiThread { bleSink?.success(payload) }
                }
            }
            scanner.startScan(
                null,
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_BALANCED).build(),
                scanCallback
            )
        }

        if (nsdListener == null) {
            val info = NsdServiceInfo().apply {
                serviceName = name
                serviceType = "_esphomelib._tcp."
                setPort(port)
                setAttribute("version", "2026.6.0")
                setAttribute("mac", mac.replace(":", "").lowercase())
                setAttribute("platform", "HEMMA")
                setAttribute("network", "wifi")
                setAttribute("friendly_name", friendlyName)
            }
            nsdListener = object : NsdManager.RegistrationListener {
                override fun onServiceRegistered(i: NsdServiceInfo?) {}
                override fun onRegistrationFailed(i: NsdServiceInfo?, e: Int) {}
                override fun onServiceUnregistered(i: NsdServiceInfo?) {}
                override fun onUnregistrationFailed(i: NsdServiceInfo?, e: Int) {}
            }
            nsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager
            nsdManager?.registerService(info, NsdManager.PROTOCOL_DNS_SD, nsdListener)
        }
        return "ok"
    }

    private fun stopBleProxy() {
        try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            scanCallback?.let { adapter?.bluetoothLeScanner?.stopScan(it) }
        } catch (_: Exception) {
        }
        scanCallback = null
        try {
            nsdListener?.let { nsdManager?.unregisterService(it) }
        } catch (_: Exception) {
        }
        nsdListener = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "hemma/ble")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    bleSink = sink
                }

                override fun onCancel(args: Any?) {
                    bleSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hemma/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Opens the system's home-app picker so the user can set
                    // Hemma as the launcher (and undo it the same way).
                    "openHomeSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_SETTINGS))
                            } catch (_: Exception) {
                            }
                        }
                        result.success(null)
                    }
                    // Hands a downloaded APK to the system installer
                    // (in-app update flow).
                    "installApk" -> {
                        try {
                            val file = java.io.File(call.argument<String>("path")!!)
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                    // Holds/releases FLAG_KEEP_SCREEN_ON so the panel can
                    // stay awake past the OS's screen-timeout ceiling.
                    "setKeepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: true
                        runOnUiThread {
                            if (on)
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            else
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "startBleProxy" -> {
                        result.success(
                            startBleProxy(
                                call.argument<String>("name") ?: "koti-tablet",
                                call.argument<String>("friendlyName") ?: "Koti Tablet",
                                call.argument<String>("mac") ?: "021122334455",
                                call.argument<Int>("port") ?: 6053
                            )
                        )
                    }
                    "stopBleProxy" -> {
                        stopBleProxy()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        stopBleProxy()
        super.onDestroy()
    }
}
