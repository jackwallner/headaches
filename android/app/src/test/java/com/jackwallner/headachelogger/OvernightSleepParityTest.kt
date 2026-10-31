package com.jackwallner.headachelogger

import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.HeatmapData
import com.jackwallner.headachelogger.model.SleepContext
import com.jackwallner.headachelogger.model.SleepIntervalMerge
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

/** Ports of the sleep and DST guards in iOS `OvernightFindingsTests` (F3, F4, F11). */
class OvernightSleepParityTest {
    private val la = ZoneId.of("America/Los_Angeles")

    private fun at(start: Instant, minutes: Long) = start.plusSeconds(minutes * 60)

    // F4: logged sleep sums only time asleep; the 45-minute merge is for the wake time.

    @Test fun asleepTotalExcludesAwakeGaps() {
        val start = Instant.ofEpochSecond(1_790_000_000)
        // 23:00 to 07:00 with awake gaps of 5, 10 and 25 minutes: 440 minutes asleep.
        val segments = listOf(
            SleepIntervalMerge.Interval(at(start, 0), at(start, 120)),
            SleepIntervalMerge.Interval(at(start, 125), at(start, 240)),
            SleepIntervalMerge.Interval(at(start, 250), at(start, 360)),
            SleepIntervalMerge.Interval(at(start, 385), at(start, 480)),
        )
        assertEquals(440.0, SleepContext.summarize(segments).first!! * 60, 0.001)
        // Overlapping segments from two sources count once.
        val overlapping = segments + SleepIntervalMerge.Interval(at(start, 10), at(start, 100))
        assertEquals(440.0, SleepContext.summarize(overlapping).first!! * 60, 0.001)
        // The merge for the wake time still spans the whole night.
        assertEquals(at(start, 480), SleepContext.summarize(segments).second)
    }

    // F3: the backfill asks about the night that ends on the record's day (noon), not before midnight.

    @Test fun backfillQueriesTheNightThatEndsOnTheRecordsDay() {
        val noon = LocalDate.of(2026, 10, 20).atTime(LocalTime.NOON).atZone(la).toInstant()
        val (start, end) = SleepContext.window(noon, la)
        assertEquals(LocalDate.of(2026, 10, 19).atTime(18, 0).atZone(la).toInstant(), start)
        assertEquals(noon, end)
    }

    @Test fun captureWindowStillEndsAtTheEvent() {
        val event = LocalDate.of(2026, 10, 20).atTime(8, 0).atZone(la).toInstant()
        val (start, end) = SleepContext.window(event, la)
        assertEquals(LocalDate.of(2026, 10, 19).atTime(18, 0).atZone(la).toInstant(), start)
        assertEquals(event, end)
    }

    @Test fun windowsKeepTheirWallClockAcrossDstChanges() {
        // Spring forward 2026-03-08 and fall back 2026-11-01 in Los Angeles.
        for (day in listOf(LocalDate.of(2026, 3, 8), LocalDate.of(2026, 11, 1))) {
            val noon = day.atTime(LocalTime.NOON).atZone(la).toInstant()
            val (start, end) = SleepContext.window(noon, la)
            assertEquals(day.minusDays(1).atTime(18, 0).atZone(la).toInstant(), start)
            assertEquals(noon, end)
        }
    }

    // F11: day loops count every day across a midnight DST change.

    @Test fun heatmapCountsEveryDayAcrossAMidnightDstChange() {
        val zone = ZoneId.of("America/Santiago") // springs forward at 00:00 on 2026-09-06
        val first = LocalDate.of(2026, 8, 25).atTime(15, 0).atZone(zone)
        val events = (0 until 27).map { HeadacheEvent(first.plusDays(it.toLong()).toInstant(), zone) }
        val days = HeatmapData.build(events, 90, events.last().timestamp, zone)
        assertEquals(27, days.size)
        assertEquals(27, days.sumOf { it.count })
    }

    @Test fun heatmapCountsEveryDayAcrossLosAngelesChanges() {
        for (start in listOf(LocalDate.of(2026, 3, 1), LocalDate.of(2026, 10, 25))) {
            val events = (0 until 14).map { HeadacheEvent(start.plusDays(it.toLong()).atTime(9, 0).atZone(la).toInstant(), la) }
            val days = HeatmapData.build(events, 90, events.last().timestamp, la)
            assertEquals(14, days.size)
            assertEquals(14, days.sumOf { it.count })
        }
    }
}
