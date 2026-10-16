package com.jackwallner.headachelogger.model

import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

/** Port of `HealthKitService.sleepContextBefore`: the night before an event, from asleep intervals. */
object SleepContext {
    const val MERGE_GAP_SECONDS = 45L * 60

    /** Yesterday 18:00 through the earlier of the event and today's noon; the prior 24 hours if that is empty. */
    fun window(event: Instant, zone: ZoneId = ZoneId.systemDefault()): Pair<Instant, Instant> {
        val local = event.atZone(zone)
        val previousEvening = local.toLocalDate().minusDays(1).atTime(LocalTime.of(18, 0)).atZone(zone).toInstant()
        val todayNoon = local.toLocalDate().atTime(LocalTime.NOON).atZone(zone).toInstant()
        val end = minOf(event, todayNoon)
        val start = if (previousEvening.isBefore(end)) previousEvening else event.minus(Duration.ofDays(1))
        return start to end
    }

    /** Total asleep hours (null when none) and the wake time after the longest merged block. */
    fun summarize(asleep: List<SleepIntervalMerge.Interval>): Pair<Double?, Instant?> {
        val merged = SleepIntervalMerge.merge(asleep, MERGE_GAP_SECONDS)
        val total = merged.sumOf { it.durationSeconds }
        val wake = SleepIntervalMerge.wakeTimeAfterLongestSleep(merged)
        return (if (total > 0) total / 3600 else null) to wake
    }

    fun snapshot(asleep: List<SleepIntervalMerge.Interval>, event: Instant): HealthSnapshot {
        val (hours, wake) = summarize(asleep)
        val sinceWake = wake?.takeIf { it.isBefore(event) }?.let { Duration.between(it, event).toMillis() / 3_600_000.0 }
        return HealthSnapshot(hours, wake, sinceWake)
    }
}
