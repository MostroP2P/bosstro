package foundation.mostro.bosstro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The device I/O the solver key needs and Flutter does not offer
 * (lib/core/services/device_security.dart):
 *
 * - `setSecure`: FLAG_SECURE while a screen shows the secret key, so it is
 *   kept out of screenshots, screen recording and the recent-apps thumbnail.
 * - `copySensitive`: copies text marked EXTRA_IS_SENSITIVE, so Android 13+
 *   hides it in the copy preview and keyboards keep it out of their
 *   clipboard history.
 * - `clearSensitive`: clears the clipboard if it still holds what
 *   `copySensitive` put there, and nothing else.
 *
 * It also creates the notification channel of the new-dispute push. With the
 * app in the background or not running, Android shows that push by itself:
 * no Dart runs then, so Dart cannot be what creates the channel. With the app
 * in the foreground Firebase shows nothing and hands the push to the app.
 */
class MainActivity : FlutterActivity() {
    /** What `copySensitive` last copied, until it is cleared or replaced. */
    private var sensitive: String? = null

    /**
     * Whether the activity is in the foreground. From Android 10 a background
     * app reads an empty clipboard, which must not pass for a cleared one.
     */
    private var resumed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createDisputesChannel()
    }

    /**
     * The manifest keeps the activity through a change of the system's
     * language (`configChanges`), so `onCreate` does not run again for it.
     */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        createDisputesChannel()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        if (call.arguments as Boolean) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "copySensitive" -> {
                        copySensitive(call.arguments as String)
                        result.success(null)
                    }
                    "clearSensitive" -> result.success(clearSensitive())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * The channel the push server names in a new-dispute push. Created every
     * time the app starts and the configuration changes: it costs nothing
     * when it exists, and creating it again is what renames it after a change
     * of the system's language. A change made while the app is not running
     * shows at its next start. Its importance is only a first value, which
     * the solver then owns in Android's settings.
     *
     * The id is permanent: Android keeps the solver's settings by it, and the
     * push server sends it.
     */
    private fun createDisputesChannel() {
        // Channels exist from Android 8; below it a notification has none.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            DISPUTES_CHANNEL,
            getString(R.string.push_disputes_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun clipboard() =
        getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private fun copySensitive(text: String) {
        val clip = ClipData.newPlainText("", text)
        clip.description.extras = PersistableBundle().apply {
            // The constant exists from API 33; the key is honoured by
            // keyboards on older versions too.
            val key = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ClipDescription.EXTRA_IS_SENSITIVE
            } else {
                "android.content.extra.IS_SENSITIVE"
            }
            putBoolean(key, true)
        }
        clipboard().setPrimaryClip(clip)
        sensitive = text
    }

    /**
     * Clears the clipboard if it still holds the sensitive text. Returns
     * whether that is settled: true when cleared, or when the clipboard holds
     * something else now (the user copied over it); false when it cannot be
     * read (the app is in the background), so Dart retries on resume.
     */
    private fun clearSensitive(): Boolean {
        val expected = sensitive ?: return true
        if (!resumed) return false
        val clip = clipboard().primaryClip
        val current =
            if (clip != null && clip.itemCount > 0) clip.getItemAt(0).text?.toString() else null
        if (current == expected) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard().clearPrimaryClip()
            } else {
                clipboard().setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }
        sensitive = null
        return true
    }

    private companion object {
        const val CHANNEL = "foundation.mostro.bosstro/device_security"
        const val DISPUTES_CHANNEL = "bosstro_disputes"
    }
}
