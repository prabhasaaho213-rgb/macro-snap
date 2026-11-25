package com.macrosnap.macro_snap

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.view.WindowCompat
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Main entry point for MacroSnap.
 *
 * Uses [WindowCompat.setDecorFitsSystemWindows] to enable edge-to-edge
 * rendering on Android 15 (SDK 35) and Android 16 (SDK 36).
 *
 * The newer [androidx.activity.EdgeToEdge] API requires AndroidX Activity
 * 1.9+, which isn't bundled with Flutter 3.47. This deprecated call
 * achieves the same result and is confirmed working across all API levels.
 * Flutter's rendering pipeline draws under the system bars, and
 * [Scaffold] / [SafeArea] handle insets — so no layout changes needed.
 *
 * Extends [FlutterFragmentActivity] (not [FlutterActivity]) so the `health`
 * plugin can use [registerForActivityResult] when requesting Health Connect
 * permissions — that API contract requires the FragmentActivity base.
 */
class MainActivity : FlutterFragmentActivity() {
    private var stepSensorManager: SensorManager? = null
    private var stepListener: SensorEventListener? = null
    private var stepEventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Draw under system bars on Android 15+ (SDK 35+).
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "macrosnap/launcher",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openPlayStore" -> result.success(openPlayStore())
                "saveToGallery" -> result.success(saveToGallery(call.argument<String>("path")))
                else -> result.notImplemented()
            }
        }

        // The Play Install Referrer — how an invite survives the install.
        //
        // A /join/CODE link opened by someone without the app sends them to the
        // store with `referrer=join_code=CODE`. Play records that string
        // against the install, and this is the only place it can be read back;
        // without it the code was consumed by the install and lost, so the
        // friend had to tap the link a second time once the app was there.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "macrosnap/install_referrer",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getReferrer" -> readInstallReferrer(result)
                else -> result.notImplemented()
            }
        }

        // The phone's own step counter. Health Connect is OPTIONAL in this app:
        // steps have to keep working for a phone that never installed or
        // authorised a health app, and the hardware counter the OS already
        // keeps is the only source that needs no other app and no account.
        //
        // The stream emits the CUMULATIVE count since boot (a Long), exactly
        // what TYPE_STEP_COUNTER reports; StepCounterService turns that into a
        // day total and survives reboots. No plugin: this is the same reason
        // the launcher channel above exists — a sensor listener needs no
        // dependency and no Play Services.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "macrosnap/steps",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    stepEventSink = events
                    startStepSensor()
                }

                override fun onCancel(arguments: Any?) {
                    stopStepSensor()
                }
            },
        )
    }

    /**
     * Hands Dart the referrer string Play recorded for this install.
     *
     * Answers exactly once. An empty string means Play has no referrer (an
     * organic install) and is final; null means the read itself failed, which
     * the Dart side treats as "try again next launch" rather than burning the
     * single read. The connection is closed on every path — a live
     * [InstallReferrerClient] holds a bound Play Store service.
     */
    private fun readInstallReferrer(result: MethodChannel.Result) {
        val client = try {
            InstallReferrerClient.newBuilder(applicationContext).build()
        } catch (_: Exception) {
            result.success(null)
            return
        }
        var answered = false
        fun reply(value: String?) {
            if (answered) return
            answered = true
            try {
                client.endConnection()
            } catch (_: Exception) {
                // Already closed, or the service was never bound.
            }
            runOnUiThread { result.success(value) }
        }
        try {
            client.startConnection(
                object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(responseCode: Int) {
                        if (responseCode == InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED) {
                            // No Play Store on this device: there will never be a
                            // referrer here, so answer "none" rather than make
                            // Dart retry this every launch.
                            reply("")
                            return
                        }
                        if (responseCode != InstallReferrerClient.InstallReferrerResponse.OK) {
                            // SERVICE_UNAVAILABLE is what Play reports in the first
                            // moments after an install; null asks Dart to try again
                            // on the next launch instead of burning the read.
                            reply(null)
                            return
                        }
                        val referrer = try {
                            client.installReferrer.installReferrer
                        } catch (_: Exception) {
                            null
                        }
                        reply(referrer)
                    }

                    override fun onInstallReferrerServiceDisconnected() {
                        reply(null)
                    }
                },
            )
        } catch (_: Exception) {
            reply(null)
        }
    }

    /**
     * Starts the hardware step counter. Emits an error (which Dart reports as
     * "no sensor on this device") rather than staying silent when the phone has
     * no counter, so the Health tab can say so honestly.
     *
     * ACTIVITY_RECOGNITION is requested by Dart before this is called: on
     * Android 10+ the sensor is gated behind that runtime permission.
     */
    private fun startStepSensor() {
        val manager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (manager == null || sensor == null) {
            stepEventSink?.error(
                "unavailable",
                "No step counter sensor on this device",
                null,
            )
            return
        }
        stopStepSensor()
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val total = event.values.firstOrNull() ?: return
                stepEventSink?.success(total.toLong())
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        if (manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)) {
            stepSensorManager = manager
            stepListener = listener
        } else {
            stepEventSink?.error(
                "unavailable",
                "The step counter could not be started",
                null,
            )
        }
    }

    private fun stopStepSensor() {
        stepListener?.let { stepSensorManager?.unregisterListener(it) }
        stepListener = null
        stepSensorManager = null
    }

    override fun onDestroy() {
        stopStepSensor()
        super.onDestroy()
    }

    /**
     * Copies a local image file into the device's photo gallery — how a
     * meal's photo gets an explicit "Save to Gallery" button without a
     * gallery-saver plugin (the dependency freeze means a MethodChannel is
     * both lighter and free).
     *
     * API 29+ inserts through MediaStore under Pictures/MacroSnap; until Q
     * the file is written into the public Pictures folder and indexed by a
     * MediaScanner pass. Returns false (never throws) when the file is
     * missing or the insert fails, so Dart can show an honest error.
     */
    private fun saveToGallery(path: String?): Boolean {
        if (path == null) return false
        val file = File(path)
        if (!file.exists()) return false
        val name = "MacroSnap_" + System.currentTimeMillis() + ".jpg"
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = applicationContext.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/MacroSnap",
                    )
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = resolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: return false
                resolver.openOutputStream(uri)?.use { out ->
                    file.inputStream().use { it.copyTo(out) }
                } ?: return false
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                true
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_PICTURES,
                    ),
                    "MacroSnap",
                )
                if (!dir.exists()) dir.mkdirs()
                val dest = File(dir, name)
                file.copyTo(dest, overwrite = true)
                MediaScannerConnection.scanFile(
                    applicationContext,
                    arrayOf(dest.absolutePath),
                    arrayOf("image/jpeg"),
                    null,
                )
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Opens the MacroSnap listing in Google Play Store.
     *
     * The plain `market://` intent is hijacked by OEM app stores on several
     * devices (V-Appstore on Vivo, GetApps on Xiaomi, etc. — they register
     * the same scheme), so "Rate Us" landed in the wrong store. Pinning the
     * intent to the Play Store package (`com.android.vending`) makes the
     * system deliver it only to Google Play.
     */
    private fun openPlayStore(): Boolean {
        val pkg = "com.macrosnap.macro_snap"
        // 1) Explicit Play Store intent — market:// pinned to com.android.vending.
        try {
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://details?id=$pkg"),
            ).setPackage("com.android.vending")
            startActivity(intent)
            return true
        } catch (e: ActivityNotFoundException) {
            // Play Store not installed or can't handle it — try the web URL.
        }
        // 2) Web listing pinned to Play Store (handles https://play.google.com).
        try {
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$pkg"),
            ).setPackage("com.android.vending")
            startActivity(intent)
            return true
        } catch (e: ActivityNotFoundException) {
            // Play Store missing entirely — fall back to any browser.
        }
        // 3) Last resort: any app that can open the web listing.
        return try {
            startActivity(
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=$pkg"),
                ),
            )
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
