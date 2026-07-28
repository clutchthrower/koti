package com.koti.dashboard

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Process
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicLong

class MainActivity : FlutterActivity() {
    private var bleSink: EventChannel.EventSink? = null
    private var scanCallback: ScanCallback? = null

    // Separate NSD registration for the Koti player's own discovery
    // advertisement, so it can run independently of the Bluetooth proxy's.
    private var kotiNsdManager: NsdManager? = null
    private var kotiNsdListener: NsdManager.RegistrationListener? = null

    // Separate again for Sendspin's own discovery advertisement.
    private var sendspinNsdManager: NsdManager? = null
    private var sendspinNsdListener: NsdManager.RegistrationListener? = null

    private fun blePermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= 31)
            arrayOf(Manifest.permission.BLUETOOTH_SCAN)
        else
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun hasBlePermissions(): Boolean = blePermissions().all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    // Starts a passive-ish BLE scan streaming raw advertisements to Dart.
    // Home Assistant discovery/routing for this data is handled entirely
    // over the koti/native REST API + a webhook (see BleProxy/
    // custom_components/koti/bluetooth.py) — no mDNS advertisement or
    // ESPHome-protocol server here, unlike this method's previous version.
    private fun startBleScan(): String {
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
        return "ok"
    }

    private fun stopBleScan() {
        try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            scanCallback?.let { adapter?.bluetoothLeScanner?.stopScan(it) }
        } catch (_: Exception) {
        }
        scanCallback = null
    }

    // Real Android system volume (STREAM_MUSIC), not the audio player's own
    // gain — a media_player's "volume" needs to move the same slider the
    // user's physical volume buttons do, or it silently multiplies against
    // whatever the device happens to be set to.
    private fun audioManager() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun setMusicVolumePercent(percent: Int) {
        val am = audioManager()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val level = ((percent.coerceIn(0, 100) / 100.0) * max).toInt().coerceIn(0, max)
        am.setStreamVolume(AudioManager.STREAM_MUSIC, level, 0)
    }

    private fun getMusicVolumePercent(): Int {
        val am = audioManager()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0
        val current = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        return ((current.toDouble() / max) * 100).toInt().coerceIn(0, 100)
    }

    // Advertises this tablet as a Koti player over mDNS so the Koti Home
    // Assistant integration can auto-discover it — no manual IP/password
    // entry, matching the ESPHome-style zero-config pattern above.
    private fun startKotiDiscovery(name: String, id: String, port: Int): String {
        if (kotiNsdListener != null) return "ok"
        val info = NsdServiceInfo().apply {
            serviceName = name
            serviceType = "_koti._tcp."
            setPort(port)
            setAttribute("id", id)
            setAttribute("name", name)
        }
        kotiNsdListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(i: NsdServiceInfo?) {}
            override fun onRegistrationFailed(i: NsdServiceInfo?, e: Int) {}
            override fun onServiceUnregistered(i: NsdServiceInfo?) {}
            override fun onUnregistrationFailed(i: NsdServiceInfo?, e: Int) {}
        }
        kotiNsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager
        kotiNsdManager?.registerService(info, NsdManager.PROTOCOL_DNS_SD, kotiNsdListener)
        return "ok"
    }

    private fun stopKotiDiscovery() {
        try {
            kotiNsdListener?.let { kotiNsdManager?.unregisterService(it) }
        } catch (_: Exception) {
        }
        kotiNsdListener = null
    }

    // Advertises this tablet as a Sendspin client over mDNS (spec's
    // "server-initiated" discovery model) so Music Assistant's own
    // built-in Sendspin support finds and dials in — zero configuration,
    // no custom MA provider needed. `path` is a required TXT record per
    // the spec (the WebSocket endpoint Music Assistant should connect to).
    private fun startSendspinDiscovery(name: String, port: Int): String {
        if (sendspinNsdListener != null) return "ok"
        val info = NsdServiceInfo().apply {
            serviceName = name
            serviceType = "_sendspin._tcp."
            setPort(port)
            setAttribute("path", "/sendspin")
            setAttribute("name", name)
        }
        sendspinNsdListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(i: NsdServiceInfo?) {}
            override fun onRegistrationFailed(i: NsdServiceInfo?, e: Int) {}
            override fun onServiceUnregistered(i: NsdServiceInfo?) {}
            override fun onUnregistrationFailed(i: NsdServiceInfo?, e: Int) {}
        }
        sendspinNsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager
        sendspinNsdManager?.registerService(info, NsdManager.PROTOCOL_DNS_SD, sendspinNsdListener)
        return "ok"
    }

    private fun stopSendspinDiscovery() {
        try {
            sendspinNsdListener?.let { sendspinNsdManager?.unregisterService(it) }
        } catch (_: Exception) {
        }
        sendspinNsdListener = null
    }

    // The Sendspin player's raw-PCM output sink. A dedicated thread owns
    // the AudioTrack and drains a queue of already-decoded chunks — writes
    // to an AudioTrack in MODE_STREAM block until consumed, and blocking
    // the platform channel's own thread (where MethodChannel calls land)
    // would stall every other native call this app makes while audio plays.
    private var sendspinAudioTrack: AudioTrack? = null
    private var sendspinAudioThread: Thread? = null
    private var sendspinAudioQueue: LinkedBlockingQueue<ByteArray>? = null
    private val sendspinStopSignal = ByteArray(0)
    // A distinct sentinel from sendspinStopSignal, routed through the SAME
    // queue as audio chunks rather than calling AudioTrack.pause/flush/play
    // straight from the platform-channel thread — pause+flush racing
    // against the writer thread's own in-flight track.write() call (on a
    // DIFFERENT thread) could lose, leaving stale audio in the buffer even
    // after a "flush". Routing through the queue makes the writer thread
    // itself do the flush, right between chunks, with nothing else able to
    // sneak a write in between.
    private val sendspinFlushSignal = ByteArray(0)

    // Bytes per interleaved audio frame (channels * 2 for 16-bit PCM) and a
    // running count of frames actually handed to track.write() — read
    // together with AudioTrack.getTimestamp()'s reported framePosition (how
    // many frames have actually reached the DAC) to MEASURE this device's
    // real output latency, instead of declaring a fixed guessed constant.
    // getTimestamp() has been a stable plain-Java AudioTrack API since API
    // 19 — no native code/Oboe needed, and it works fine on this app's API
    // 24 baseline (unlike AAudio's more precise equivalent, which needs
    // API 26+).
    private var sendspinBytesPerFrame = 4
    private val sendspinTotalFramesWritten = AtomicLong(0)

    private fun startSendspinAudioSink(sampleRate: Int, channels: Int): String {
        stopSendspinAudioSink()
        val channelMask =
            if (channels >= 2) AudioFormat.CHANNEL_OUT_STEREO else AudioFormat.CHANNEL_OUT_MONO
        val minBufferSize =
            AudioTrack.getMinBufferSize(sampleRate, channelMask, AudioFormat.ENCODING_PCM_16BIT)
        if (minBufferSize <= 0) return "error"
        sendspinBytesPerFrame = (if (channels >= 2) 2 else 1) * 2
        sendspinTotalFramesWritten.set(0)

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelMask)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(minBufferSize * 2)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track.play()
        sendspinAudioTrack = track

        val queue = LinkedBlockingQueue<ByteArray>()
        sendspinAudioQueue = queue
        val thread = Thread {
            while (true) {
                val chunk = queue.take()
                if (chunk === sendspinStopSignal) break
                if (chunk === sendspinFlushSignal) {
                    try {
                        track.pause()
                        track.flush()
                        track.play()
                    } catch (_: Exception) {
                    }
                    continue
                }
                try {
                    track.write(chunk, 0, chunk.size)
                    sendspinTotalFramesWritten.addAndGet((chunk.size / sendspinBytesPerFrame).toLong())
                } catch (_: Exception) {
                    break
                }
            }
        }
        thread.isDaemon = true
        thread.start()
        sendspinAudioThread = thread
        return "ok"
    }

    private fun writeSendspinPcmChunk(bytes: ByteArray) {
        sendspinAudioQueue?.put(bytes)
    }

    // The gap between "we called write() for frame N" and "frame N is
    // actually audible" — bufferedFrames (written but not yet reported as
    // played by the HAL) expressed as a duration. Not reset across a
    // flush: getTimestamp()'s framePosition only ever advances (frames
    // actually consumed), it doesn't rewind when queued-but-unplayed data
    // is discarded, so sendspinTotalFramesWritten must track the same
    // absolute counter to stay comparable — only a fresh
    // startSendspinAudioSink() (a new AudioTrack) resets either. Returns 0
    // before the HAL has reported a first valid timestamp (right after
    // starting) rather than a made-up value.
    private fun getSendspinOutputLatencyUs(): Long {
        val track = sendspinAudioTrack ?: return 0L
        val timestamp = AudioTimestamp()
        if (!track.getTimestamp(timestamp)) return 0L
        val sampleRate = track.sampleRate
        if (sampleRate <= 0) return 0L
        val bufferedFrames = sendspinTotalFramesWritten.get() - timestamp.framePosition
        if (bufferedFrames <= 0) return 0L
        return bufferedFrames * 1_000_000L / sampleRate
    }

    // stream/clear (a track skip/seek — buffers should reset, but the
    // stream itself keeps going, so the AudioTrack stays alive). Drops
    // anything queued-but-not-yet-written, then has the writer thread
    // itself discard whatever's already in the AudioTrack's own internal
    // buffer (which keeps draining/playing after write() returns — that's
    // what let the old track's tail audibly overlap the new one).
    private fun flushSendspinAudioSink() {
        sendspinAudioQueue?.let { queue ->
            queue.clear()
            queue.put(sendspinFlushSignal)
        }
    }

    private fun stopSendspinAudioSink() {
        sendspinAudioQueue?.let { queue ->
            queue.clear()
            queue.put(sendspinStopSignal)
        }
        try {
            sendspinAudioThread?.join(500)
        } catch (_: InterruptedException) {
        }
        sendspinAudioThread = null
        sendspinAudioQueue = null
        try {
            sendspinAudioTrack?.pause()
            sendspinAudioTrack?.flush()
            sendspinAudioTrack?.stop()
            sendspinAudioTrack?.release()
        } catch (_: Exception) {
        }
        sendspinAudioTrack = null
    }

    // No permission needed for either battery level or charging status.
    private fun getBatteryStatus(): Map<String, Any> {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val status = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        return mapOf("level" to level, "charging" to charging)
    }

    // Two prior approaches to this were tried and both confirmed (via live
    // logcat inspection) to fail on this device:
    //  1. startActivity() immediately, then killProcess() ~300ms later —
    //     this app is single-process, so the freshly-started Activity
    //     shares this same PID; the delayed kill tore down that
    //     not-yet-rendered new instance right along with the old one.
    //  2. Schedule the relaunch via AlarmManager+PendingIntent (surviving
    //     independently of this process), kill this process immediately.
    //     Logcat showed the alarm firing and attempting the launch, but
    //     Android explicitly logged it as a rejected background activity
    //     start: `isCallingUidForeground: false, isBgStartWhitelisted:
    //     false` — by the time a system-delivered alarm fires, this app's
    //     UID has no foreground/visible state left to justify it, and
    //     Android 10 does enforce that (contrary to this comment's
    //     earlier assumption that only 12+ enforces it strictly). No
    //     task, no process, nothing — a fully silent drop.
    //
    // What actually works: start the new Activity instance directly, all
    // in one synchronous call, while this process is STILL the visible
    // foreground app (no alarm delay, no kill first) — Android has no
    // reason to treat that as a background start at all, since it
    // genuinely isn't one. FLAG_ACTIVITY_CLEAR_TASK finishes the old
    // instance as the new one takes over, which is what actually resets
    // app-level state (a fresh FlutterEngine/Dart isolate for the new
    // instance) without needing a true OS process kill — onDestroy()
    // (already below) tears down this instance's native BLE/mDNS/
    // Sendspin-audio resources as part of that same transition.
    private fun restartApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        if (intent != null) startActivity(intent)
    }

    // A normal Android app cannot reboot the device — android.permission.
    // REBOOT is signature-level. This only succeeds if the tablet has been
    // set up as a Device Owner (see KotiDeviceAdminReceiver's doc comment
    // and README.md for the one-time adb command); otherwise it reports
    // that plainly rather than silently failing.
    private fun rebootDevice(): String {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (!dpm.isDeviceOwnerApp(packageName)) return "requires_device_owner"
        val adminComponent = ComponentName(this, KotiDeviceAdminReceiver::class.java)
        return try {
            dpm.reboot(adminComponent)
            "ok"
        } catch (_: Exception) {
            "error"
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "koti/ble")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    bleSink = sink
                }

                override fun onCancel(args: Any?) {
                    bleSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "koti/native")
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
                    "startBleScan" -> {
                        result.success(startBleScan())
                    }
                    "stopBleScan" -> {
                        stopBleScan()
                        result.success(null)
                    }
                    "setMusicVolume" -> {
                        setMusicVolumePercent(call.argument<Int>("percent") ?: 100)
                        result.success(null)
                    }
                    "getMusicVolume" -> {
                        result.success(getMusicVolumePercent())
                    }
                    "startKotiDiscovery" -> {
                        result.success(
                            startKotiDiscovery(
                                call.argument<String>("name") ?: "Koti Tablet",
                                call.argument<String>("id") ?: "",
                                call.argument<Int>("port") ?: 8127
                            )
                        )
                    }
                    "stopKotiDiscovery" -> {
                        stopKotiDiscovery()
                        result.success(null)
                    }
                    "startSendspinAudioSink" -> {
                        result.success(
                            startSendspinAudioSink(
                                call.argument<Int>("sampleRate") ?: 48000,
                                call.argument<Int>("channels") ?: 2
                            )
                        )
                    }
                    "writeSendspinPcmChunk" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes != null) writeSendspinPcmChunk(bytes)
                        result.success(null)
                    }
                    "stopSendspinAudioSink" -> {
                        stopSendspinAudioSink()
                        result.success(null)
                    }
                    "flushSendspinAudioSink" -> {
                        flushSendspinAudioSink()
                        result.success(null)
                    }
                    "getSendspinOutputLatencyUs" -> {
                        result.success(getSendspinOutputLatencyUs())
                    }
                    "startSendspinDiscovery" -> {
                        result.success(
                            startSendspinDiscovery(
                                call.argument<String>("name") ?: "Koti Tablet",
                                call.argument<Int>("port") ?: 8928
                            )
                        )
                    }
                    "stopSendspinDiscovery" -> {
                        stopSendspinDiscovery()
                        result.success(null)
                    }
                    "getBatteryStatus" -> {
                        result.success(getBatteryStatus())
                    }
                    "restartApp" -> {
                        result.success(null)
                        restartApp()
                    }
                    "rebootDevice" -> {
                        result.success(rebootDevice())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        stopBleScan()
        stopKotiDiscovery()
        stopSendspinAudioSink()
        stopSendspinDiscovery()
        super.onDestroy()
    }
}
