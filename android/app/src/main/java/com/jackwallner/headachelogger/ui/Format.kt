package com.jackwallner.headachelogger.ui

import androidx.compose.ui.graphics.Color
import com.jackwallner.headachelogger.model.CaptureStatus
import com.jackwallner.headachelogger.model.HeadacheSeverity
import com.jackwallner.headachelogger.ui.theme.Tint
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/** The iOS `Date.formatted` styles the screens use. */
object Format {
    private val zone: ZoneId get() = ZoneId.systemDefault()

    /** `.formatted(date: .abbreviated, time: .shortened)`: "Oct 16, 2026 at 9:41 AM". */
    fun dateTime(instant: Instant): String {
        val local = instant.atZone(zone)
        return "${DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.getDefault()).format(local)} at ${time(instant)}"
    }

    /** `.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()`: "Fri, Oct 16, 9:41 AM". */
    fun weekdayDateTime(instant: Instant): String =
        "${DateTimeFormatter.ofPattern("EEE, MMM d", Locale.getDefault()).format(instant.atZone(zone))}, ${time(instant)}"

    fun time(instant: Instant): String =
        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()).format(instant.atZone(zone))

    /** `DateFormatter.dateStyle = .medium`: "Oct 16, 2026". */
    fun mediumDate(date: LocalDate): String = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.getDefault()).format(date)

    fun mediumDate(instant: Instant): String = mediumDate(instant.atZone(zone).toLocalDate())

    fun hour(hour: Int): String = DateTimeFormatter.ofPattern("h a", Locale.US).format(java.time.LocalTime.of(hour.coerceIn(0, 23), 0))

    fun hourMinute(hour: Int, minute: Int): String =
        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()).format(java.time.LocalTime.of(hour, minute))

    fun oneDecimal(value: Double): String = String.format(Locale.US, "%.1f", value)

    fun grouped(value: Int): String = String.format(Locale.getDefault(), "%,d", value)

    fun plural(count: Int, singular: String, plural: String = singular + "s") = if (count == 1) singular else plural
}

fun severityColor(severity: HeadacheSeverity): Color = when (severity) {
    HeadacheSeverity.SLIGHT -> Tint.yellow
    HeadacheSeverity.MEDIUM -> Tint.orange
    HeadacheSeverity.EXTREME -> Tint.red
}

fun statusColor(status: CaptureStatus): Color = when (status) {
    CaptureStatus.COMPLETE -> Tint.green
    CaptureStatus.PARTIAL -> Tint.orange
    CaptureStatus.FAILED -> Tint.red
    CaptureStatus.PENDING -> Tint.blue
}

object AppBrand {
    const val NAME = "One Tap Headache Tracker"
}
