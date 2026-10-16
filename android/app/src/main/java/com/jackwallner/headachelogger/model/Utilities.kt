package com.jackwallner.headachelogger.model

import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/** Stored weather is always Celsius; the UI and CSV add Fahrenheit. Port of `HeadacheTemperatureFormatting`. */
object Temperature {
    fun celsiusToFahrenheit(celsius: Double): Double = celsius * 9.0 / 5.0 + 32.0

    /** Whole degrees with the unit; Fahrenheit unless `useCelsius`. Rounds half away from zero like Swift. */
    fun displayInteger(celsius: Double?, useCelsius: Boolean): String? {
        val c = celsius ?: return null
        return if (useCelsius) "${swiftRound(c)}°C" else "${swiftRound(celsiusToFahrenheit(c))}°F"
    }

    /** `"Clear, 72°F"`. */
    fun weatherSummaryWithTemperature(summary: String?, celsius: Double?, useCelsius: Boolean): String? {
        if (summary.isNullOrEmpty()) return null
        val temp = displayInteger(celsius, useCelsius) ?: return summary
        return "$summary, $temp"
    }

    private fun swiftRound(value: Double): Int = if (value < 0) -(-value).roundToInt() else value.roundToInt()
}

/** Open-Meteo hourly `time` strings vary slightly by endpoint. */
object OpenMeteoTime {
    private val formats = listOf("yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss")
        .map { DateTimeFormatter.ofPattern(it) }

    fun hourDate(raw: String, zone: ZoneId): Instant? {
        val trimmed = raw.trim()
        for (format in formats) {
            runCatching { return LocalDateTime.parse(trimmed, format).atZone(zone).toInstant() }
        }
        return runCatching { OffsetDateTime.parse(trimmed).toInstant() }.getOrNull()
    }
}

/** Derives main-sleep wake time from split sleep segments. Port of `SleepIntervalMerge`. */
object SleepIntervalMerge {
    data class Interval(val start: Instant, val end: Instant) {
        val durationSeconds: Double get() = Duration.between(start, end).toMillis() / 1000.0
    }

    fun merge(intervals: List<Interval>, mergeGapSeconds: Long): List<Interval> {
        val out = mutableListOf<Interval>()
        for (interval in intervals.sortedBy { it.start }) {
            val last = out.lastOrNull()
            if (last != null && !interval.start.isAfter(last.end.plusSeconds(mergeGapSeconds))) {
                out[out.lastIndex] = Interval(last.start, maxOf(last.end, interval.end))
            } else {
                out += interval
            }
        }
        return out
    }

    fun wakeTimeAfterLongestSleep(merged: List<Interval>): Instant? = merged.maxByOrNull { it.durationSeconds }?.end
}

data class QuizQuestion(val id: String, val question: String, val options: List<String>)

object QuizQuestions {
    val all = listOf(
        QuizQuestion("time_of_day", "What time of day do you most often get headaches?", listOf("Morning", "Afternoon", "Evening", "Overnight", "No pattern")),
        QuizQuestion("trigger_sleep", "Do you notice headaches after poor or too little sleep?", listOf("Yes", "No", "Not sure")),
        QuizQuestion("trigger_weather", "Have you noticed weather changes triggering your headaches?", listOf("Pressure drops", "Heat", "Cold", "No", "Not sure")),
        QuizQuestion("trigger_food", "Do certain foods or drinks seem to trigger your headaches?", listOf("Yes", "No", "Not sure")),
        QuizQuestion("side", "Are your headaches typically on one side of your head?", listOf("Yes, usually right", "Yes, usually left", "No, both sides", "It varies")),
        QuizQuestion("severity", "How severe are your headaches on a typical day?", listOf("Slight (can ignore it)", "Medium (noticeable but functional)", "Extreme (hard to function)", "It varies a lot")),
    )
}

/** Plain values for Proactive Alerts, read by the screen and the background worker alike. */
data class ProAlertPreferenceValues(
    val alertsEnabled: Boolean = false,
    val pressureDropThresholdHpa: Double = 4.0,
    val airQualityEnabled: Boolean = true,
    val airQualityThreshold: Int = 100,
    val quietHoursEnabled: Boolean = true,
    val quietHoursStart: Int = 22,
    val quietHoursEnd: Int = 7,
    val patternAlertsEnabled: Boolean = false,
    val patternAlertSensitivity: Double = 0.0,
) {
    /** Wraps midnight when end is before start. */
    fun isQuietHour(at: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (!quietHoursEnabled || quietHoursStart == quietHoursEnd) return false
        val hour = at.atZone(zone).hour
        return if (quietHoursStart < quietHoursEnd) hour in quietHoursStart until quietHoursEnd
        else hour >= quietHoursStart || hour < quietHoursEnd
    }
}
