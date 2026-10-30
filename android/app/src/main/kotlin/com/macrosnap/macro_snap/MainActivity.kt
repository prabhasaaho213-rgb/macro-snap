package com.macrosnap.macro_snap

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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
 */

class MainActivity : FlutterActivity() {
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
