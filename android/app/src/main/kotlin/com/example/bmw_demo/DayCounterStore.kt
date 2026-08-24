package com.example.bmw_demo

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * Everything the home-screen widget needs to keep counting on its own.
 *
 * The app writes an event here once; the widget recomputes the day count from
 * the stored target on every update, so the numbers stay right even if the app
 * is never opened again.
 */
object DayCounterStore {

    private const val PREFS = "bmw_demo.day_counter"
    private const val KEY_EVENTS = "events"
    private const val KEY_PINNED = "pinned_event"
    private const val KEY_LAUNCH_ID = "launch_event_id"

    const val ARTWORK_FILE = "day_counter_widget.png"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---------------------------------------------------------------- events

    fun saveEvents(context: Context, json: String) {
        prefs(context).edit().putString(KEY_EVENTS, json).apply()
    }

    fun loadEvents(context: Context): String? = prefs(context).getString(KEY_EVENTS, null)

    // ---------------------------------------------------------------- pinned

    /** Stores the single event the widget renders. [json] is a one-item array. */
    fun savePinned(context: Context, json: String) {
        val event = JSONArray(json).optJSONObject(0) ?: return
        prefs(context).edit().putString(KEY_PINNED, event.toString()).apply()
    }

    fun pinned(context: Context): PinnedEvent? {
        val raw = prefs(context).getString(KEY_PINNED, null) ?: return null
        return try {
            PinnedEvent.from(JSONObject(raw))
        } catch (error: Exception) {
            null
        }
    }

    fun pinnedId(context: Context): String? = pinned(context)?.id

    // ------------------------------------------------------------ launch id

    fun setLaunchEventId(context: Context, id: String?) {
        prefs(context).edit().putString(KEY_LAUNCH_ID, id).apply()
    }

    /** Reads and clears, so one tap never opens the counter twice. */
    fun takeLaunchEventId(context: Context): String? {
        val id = prefs(context).getString(KEY_LAUNCH_ID, null)
        if (id != null) setLaunchEventId(context, null)
        return id
    }
}

/** The stored event, plus the counting rules mirrored from the Dart model. */
data class PinnedEvent(
    val id: String,
    val title: String,
    val emoji: String,
    val targetMillis: Long,
    val spanDays: Int
) {
    companion object {
        fun from(json: JSONObject) = PinnedEvent(
            id = json.optString("id"),
            title = json.optString("title"),
            emoji = json.optString("emoji"),
            targetMillis = json.optLong("target"),
            spanDays = json.optInt("spanDays", 180).coerceAtLeast(1)
        )

        private fun midnight(millis: Long): Long = Calendar.getInstance().apply {
            timeInMillis = millis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    /**
     * Whole calendar days from today to the target; negative once it passes.
     *
     * Rounded rather than truncated, because a local day either side of a
     * clock change is 23 or 25 hours long.
     */
    private fun deltaDays(now: Long): Int {
        val elapsed = midnight(targetMillis) - midnight(now)
        val dayMillis = TimeUnit.DAYS.toMillis(1).toDouble()
        return Math.round(elapsed / dayMillis).toInt()
    }

    /** The big number: days remaining, or days elapsed once the date passes. */
    fun count(now: Long): Int = abs(deltaDays(now))

    fun isToday(now: Long): Boolean = deltaDays(now) == 0

    fun caption(now: Long): String {
        val unit = if (count(now) == 1) "Day" else "Days"
        return if (deltaDays(now) >= 0) "$unit Until" else "$unit Since"
    }

    /** Numerator of `X / spanDays`: 180/180 → 1/180, or 1/180 → 180/180. */
    fun fraction(now: Long): Int = count(now).coerceIn(0, spanDays)

    fun fractionLabel(now: Long): String = "${fraction(now)} / $spanDays"

    /** Journey progress as a percentage, for the widget's progress bar. */
    fun progressPercent(now: Long): Int {
        val delta = deltaDays(now)
        val travelled = if (delta > 0) spanDays - delta else -delta
        return (travelled.coerceIn(0, spanDays) * 100) / spanDays
    }
}
