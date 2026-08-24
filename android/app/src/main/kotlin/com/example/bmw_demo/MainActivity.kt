package com.example.bmw_demo

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private var pendingEventId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureWidgetTap(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The app was already running when the widget was tapped; Dart picks
        // this up on the next resume.
        captureWidgetTap(intent)
    }

    /** Parks the id of the counter whose widget launched us, if any. */
    private fun captureWidgetTap(intent: Intent?) {
        val eventId = intent?.getStringExtra(DayCounterWidgetProvider.EXTRA_EVENT_ID)
            ?: return
        pendingEventId = eventId
        DayCounterStore.setLaunchEventId(this, eventId)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveEvents" -> {
                        DayCounterStore.saveEvents(this, call.arguments as String)
                        result.success(null)
                    }

                    "loadEvents" -> result.success(DayCounterStore.loadEvents(this))

                    "pinEvent" -> result.success(pinEvent(call.argument("event"), call.argument("artwork")))

                    "pinnedEventId" -> result.success(DayCounterStore.pinnedId(this))

                    "takeLaunchEventId" -> {
                        val id = pendingEventId ?: DayCounterStore.takeLaunchEventId(this)
                        pendingEventId = null
                        DayCounterStore.setLaunchEventId(this, null)
                        result.success(id)
                    }

                    "requestPin" -> result.success(requestPinToHomeScreen())

                    else -> result.notImplemented()
                }
            }
    }

    /** Stores the counter and its artwork, then redraws any placed widget. */
    private fun pinEvent(eventJson: String?, artwork: ByteArray?): Boolean {
        if (eventJson == null) return false
        DayCounterStore.savePinned(this, eventJson)
        if (artwork != null && artwork.isNotEmpty()) {
            File(filesDir, DayCounterStore.ARTWORK_FILE).writeBytes(artwork)
        }
        DayCounterWidgetProvider.refreshAll(this)
        return true
    }

    /**
     * Asks the launcher to place the widget (Android 8+). Launchers may refuse,
     * in which case the widget is still available from the widget tray.
     */
    private fun requestPinToHomeScreen(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) return false
        return manager.requestPinAppWidget(
            ComponentName(this, DayCounterWidgetProvider::class.java),
            null,
            null
        )
    }

    companion object {
        private const val CHANNEL = "bmw_demo/day_counter"
    }
}
