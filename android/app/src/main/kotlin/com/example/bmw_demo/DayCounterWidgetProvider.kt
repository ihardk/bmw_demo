package com.example.bmw_demo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import java.io.File

/**
 * The home-screen day counter.
 *
 * The artwork is a PNG the app rendered from the very same card the user sees
 * in-app; the numbers on top are drawn natively and recomputed on every update,
 * so the widget never shows a stale count. Tapping it opens the app on that
 * counter.
 */
class DayCounterWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Midnight, a timezone change or a manual refresh all mean the day
        // count moved on.
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            ACTION_REFRESH -> refreshAll(context)
        }
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int
    ) {
        val views = RemoteViews(context.packageName, R.layout.day_counter_widget)
        val event = DayCounterStore.pinned(context)
        val now = System.currentTimeMillis()

        if (event == null) {
            views.setTextViewText(R.id.widget_count, "–")
            views.setTextViewText(R.id.widget_caption, "TAP TO SET UP")
            views.setTextViewText(R.id.widget_title, "Day Counter")
            views.setTextViewText(R.id.widget_fraction, "")
            views.setProgressBar(R.id.widget_progress, 100, 0, false)
        } else {
            val isToday = event.isToday(now)
            views.setTextViewText(
                R.id.widget_count,
                if (isToday) "Today" else event.count(now).toString()
            )
            views.setTextViewText(
                R.id.widget_caption,
                if (isToday) "" else event.caption(now).uppercase()
            )
            views.setTextViewText(
                R.id.widget_title,
                listOf(event.emoji, event.title)
                    .filter { it.isNotEmpty() }
                    .joinToString(" ")
            )
            views.setTextViewText(R.id.widget_fraction, event.fractionLabel(now))
            views.setProgressBar(R.id.widget_progress, 100, event.progressPercent(now), false)
        }

        applyArtwork(context, views)
        views.setOnClickPendingIntent(R.id.widget_root, launchIntent(context, event?.id))

        appWidgetManager.updateAppWidget(widgetId, views)
    }

    /**
     * Decodes the captured artwork in our own process and ships it as a bitmap
     * — the launcher cannot read files from this app's private storage, so a
     * file:// uri would come back blank.
     */
    private fun applyArtwork(context: Context, views: RemoteViews) {
        val file = File(context.filesDir, DayCounterStore.ARTWORK_FILE)
        if (!file.exists()) {
            views.setViewVisibility(R.id.widget_image, View.GONE)
            return
        }
        val options = BitmapFactory.Options().apply { inSampleSize = 2 }
        val bitmap = BitmapFactory.decodeFile(file.absolutePath, options)
        if (bitmap == null) {
            views.setViewVisibility(R.id.widget_image, View.GONE)
            return
        }
        views.setViewVisibility(R.id.widget_image, View.VISIBLE)
        views.setImageViewBitmap(R.id.widget_image, rounded(context, bitmap))
    }

    /**
     * Rounds the artwork here rather than in the layout: the corner-clipping
     * XML attribute is not available on every version this app runs on.
     */
    private fun rounded(context: Context, source: Bitmap): Bitmap {
        val radius = 24 * context.resources.displayMetrics.density
        val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        canvas.drawRoundRect(
            RectF(0f, 0f, source.width.toFloat(), source.height.toFloat()),
            radius,
            radius,
            paint
        )
        return output
    }

    private fun launchIntent(context: Context, eventId: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_EVENT_ID, eventId)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(context, 0, intent, flags)
    }

    companion object {
        const val EXTRA_EVENT_ID = "day_counter_event_id"
        const val ACTION_REFRESH = "com.example.bmw_demo.REFRESH_DAY_COUNTER"

        /** Redraws every placed instance of the widget. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                android.content.ComponentName(context, DayCounterWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            DayCounterWidgetProvider().onUpdate(context, manager, ids)
        }
    }
}
