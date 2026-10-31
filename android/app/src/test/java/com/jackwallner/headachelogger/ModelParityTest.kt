package com.jackwallner.headachelogger

import com.jackwallner.headachelogger.data.EventStore
import com.jackwallner.headachelogger.data.HeadacheSettings
import com.jackwallner.headachelogger.data.InMemoryStore
import com.jackwallner.headachelogger.data.MemoryTextFile
import com.jackwallner.headachelogger.data.WidgetQuickLog
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.CaptureStatus
import com.jackwallner.headachelogger.model.EnvironmentCaptureResult
import com.jackwallner.headachelogger.model.EnvironmentSnapshot
import com.jackwallner.headachelogger.model.HealthCaptureResult
import com.jackwallner.headachelogger.model.HealthSnapshot
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.HeadacheSeverity
import com.jackwallner.headachelogger.model.OpenMeteoTime
import com.jackwallner.headachelogger.model.PartOfDay
import com.jackwallner.headachelogger.model.PressureTrend
import com.jackwallner.headachelogger.model.SleepContext
import com.jackwallner.headachelogger.model.SleepIntervalMerge
import com.jackwallner.headachelogger.model.Temperature
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ports of the model tests in `HeadacheLoggerTests.swift`. */
class ModelParityTest {
    @Test fun celsiusToFahrenheitConversion() {
        assertEquals(32.0, Temperature.celsiusToFahrenheit(0.0), 0.001)
        assertEquals(212.0, Temperature.celsiusToFahrenheit(100.0), 0.001)
        assertEquals(68.0, Temperature.celsiusToFahrenheit(20.0), 0.001)
        assertEquals(67.1, Temperature.celsiusToFahrenheit(19.5), 0.001)
    }

    @Test fun temperatureDisplayDefaultsToFahrenheit() {
        assertEquals("72°F", Temperature.displayInteger(22.0, useCelsius = false))
        assertEquals("22°C", Temperature.displayInteger(22.0, useCelsius = true))
        assertEquals("Rain, 72°F", Temperature.weatherSummaryWithTemperature("Rain", 22.0, false))
        assertEquals("Rain", Temperature.weatherSummaryWithTemperature("Rain", null, false))
        assertNull(Temperature.weatherSummaryWithTemperature("", 22.0, false))
    }

    @Test fun openMeteoParsesCommonHourStrings() {
        val tz = ZoneId.of("America/Los_Angeles")
        val a = OpenMeteoTime.hourDate("2026-04-12T14:00", tz)
        val b = OpenMeteoTime.hourDate("2026-04-12T14:00:00", tz)
        assertNotNull(a)
        assertNotNull(b)
        assertEquals(a, b)
    }

    @Test fun partOfDayMapping() {
        val zone = ZoneId.of("UTC")
        fun at(hour: Int) = LocalDateTime.of(2026, 4, 11, hour, 0).atZone(zone).toInstant()
        assertEquals(PartOfDay.OVERNIGHT, PartOfDay.from(at(2), zone))
        assertEquals(PartOfDay.MORNING, PartOfDay.from(at(8), zone))
        assertEquals(PartOfDay.AFTERNOON, PartOfDay.from(at(14), zone))
        assertEquals(PartOfDay.EVENING, PartOfDay.from(at(20), zone))
    }

    @Test fun finalizeCaptureMarksCompleteWhenBothSourcesCaptured() {
        val event = HeadacheEvent(epoch(1_744_406_400))
        event.apply(HealthCaptureResult(CaptureSourceStatus.CAPTURED, null, HealthSnapshot(sleepHoursLastNight = 7.0)))
        event.apply(
            EnvironmentCaptureResult(
                CaptureSourceStatus.CAPTURED, null,
                EnvironmentSnapshot(
                    locality = "Austin", region = "TX", weatherSummary = "Cloudy", weatherCode = 3, temperatureC = 22.0,
                    apparentTemperatureC = 24.0, humidityPercent = 52.0, pressureHpa = 1013.0, pressureTrend = PressureTrend.STEADY,
                    precipitationMm = 0.0, windSpeedKph = 8.0, windDirectionDegrees = 180.0, cloudCoverPercent = 75.0, uvIndex = 3.0,
                    usAQI = 32.0, europeanAQI = 18.0, pm25 = 4.0, pm10 = 8.0, ozone = 80.0, nitrogenDioxide = 12.0,
                    sulphurDioxide = 1.0, carbonMonoxide = 200.0,
                ),
            ),
        )
        event.finalizeCapture()
        assertEquals(CaptureStatus.COMPLETE, event.captureStatus)
        assertEquals(CaptureSourceStatus.CAPTURED, event.healthStatus)
        assertEquals(CaptureSourceStatus.CAPTURED, event.environmentStatus)
        assertEquals("Austin, TX", event.locationLabel)
    }

    @Test fun finalizeCaptureMarksPartialWhenOnlyOneSourceAvailable() {
        val event = HeadacheEvent()
        event.healthStatus = CaptureSourceStatus.CAPTURED
        event.environmentStatus = CaptureSourceStatus.UNAVAILABLE
        event.finalizeCapture()
        assertEquals(CaptureStatus.PARTIAL, event.captureStatus)
    }

    @Test fun finalizeCaptureMarksPartialWhenBothSourcesUnavailable() {
        val event = HeadacheEvent()
        event.apply(HealthCaptureResult(CaptureSourceStatus.UNAVAILABLE, null, null))
        event.apply(EnvironmentCaptureResult(CaptureSourceStatus.UNAVAILABLE, null, null))
        event.finalizeCapture()
        assertEquals(CaptureStatus.PARTIAL, event.captureStatus)
    }

    @Test fun finalizeCaptureFailsWhenBothSourcesFail() {
        val event = HeadacheEvent()
        event.healthStatus = CaptureSourceStatus.FAILED
        event.environmentStatus = CaptureSourceStatus.FAILED
        event.finalizeCapture()
        assertEquals(CaptureStatus.FAILED, event.captureStatus)
        assertNotNull(event.captureCompletedAt)
    }

    @Test fun sleepIntervalMergeCombinesCloseSegments() {
        val t0 = epoch(1_700_000_000)
        val a = SleepIntervalMerge.Interval(t0, t0.plusSeconds(3600))
        val b = SleepIntervalMerge.Interval(t0.plusSeconds(3600 + 30 * 60), t0.plusSeconds(7200))
        val merged = SleepIntervalMerge.merge(listOf(a, b), 45 * 60)
        assertEquals(1, merged.size)
        assertEquals(7200.0, merged[0].durationSeconds, 0.001)
    }

    @Test fun wakeTimeAfterLongestSleep() {
        val t0 = epoch(1_700_000_000)
        val short = SleepIntervalMerge.Interval(t0, t0.plusSeconds(1800))
        val long = SleepIntervalMerge.Interval(t0.plusSeconds(10_000), t0.plusSeconds(10_000 + 28_800))
        val merged = SleepIntervalMerge.merge(listOf(short, long), 60)
        assertEquals(long.end, SleepIntervalMerge.wakeTimeAfterLongestSleep(merged))
    }

    @Test fun emptyHealthSnapshotIsNotMeaningful() {
        assertFalse(HealthSnapshot().hasMeaningfulValue)
    }

    @Test fun healthSnapshotWithOnlyZeroSleepIsStillMeaningful() {
        // iOS pins zero steps; Android reads only sleep, so zero hours is the equivalent "a value, even if zero".
        assertTrue(HealthSnapshot(sleepHoursLastNight = 0.0).hasMeaningfulValue)
    }

    @Test fun roundingNotTruncation() {
        assertEquals(1235, 1234.9.roundToInt())
        assertEquals(1234, 1234.9.toInt())
    }

    @Test fun severityEnumCases() {
        assertEquals("slight", HeadacheSeverity.SLIGHT.raw)
        assertEquals("medium", HeadacheSeverity.MEDIUM.raw)
        assertEquals("extreme", HeadacheSeverity.EXTREME.raw)
        assertEquals(3, HeadacheSeverity.entries.size)
    }

    @Test fun eventSeverityRoundTrip() {
        val event = HeadacheEvent()
        assertNull(event.severity)
        assertNull(event.severityRaw)
        event.severity = HeadacheSeverity.EXTREME
        assertEquals(HeadacheSeverity.EXTREME, event.severity)
        assertEquals("extreme", event.severityRaw)
        event.severity = null
        assertNull(event.severity)
        assertNull(event.severityRaw)
    }

    @Test fun promptForSeverityNotesDefaultsToFalse() {
        val defaults = InMemoryStore()
        assertFalse(HeadacheSettings(defaults).promptForSeverityNotes)
        HeadacheSettings(defaults).promptForSeverityNotes = true
        assertTrue(HeadacheSettings(defaults).promptForSeverityNotes)
        assertTrue(defaults.getBoolean("headachePromptForSeverityNotes"))
    }

    @Test fun pendingCaptureMatchesOrphansAndWidgetSentinels() {
        val store = EventStore(MemoryTextFile())
        val orphan = HeadacheEvent(epoch(1_744_000_000))
        val widget = HeadacheEvent(epoch(1_744_000_100)).apply {
            apply(HealthCaptureResult(CaptureSourceStatus.UNAVAILABLE, WidgetQuickLog.HEALTH_MESSAGE_PENDING, null))
            apply(EnvironmentCaptureResult(CaptureSourceStatus.UNAVAILABLE, WidgetQuickLog.ENVIRONMENT_MESSAGE_PENDING, null))
            finalizeCapture()
        }
        val completed = HeadacheEvent(epoch(1_744_000_200)).apply {
            apply(HealthCaptureResult(CaptureSourceStatus.CAPTURED, null, HealthSnapshot(sleepHoursLastNight = 7.0)))
            apply(EnvironmentCaptureResult(CaptureSourceStatus.CAPTURED, null, null))
            finalizeCapture()
        }
        val failed = HeadacheEvent(epoch(1_744_000_300)).apply {
            apply(HealthCaptureResult(CaptureSourceStatus.FAILED, "boom", null))
            apply(EnvironmentCaptureResult(CaptureSourceStatus.FAILED, "boom", null))
            finalizeCapture()
        }
        listOf(failed, completed, widget, orphan).forEach(store::insert)
        assertEquals(listOf(orphan.id, widget.id), store.pendingCaptures().map { it.id })
    }

    @Test fun widgetSentinelsMatchIos() {
        assertEquals("Open the app to capture Health context.", WidgetQuickLog.HEALTH_MESSAGE_PENDING)
        assertEquals("Open the app to capture weather.", WidgetQuickLog.ENVIRONMENT_MESSAGE_PENDING)
    }

    @Test fun sleepWindowRunsFromPreviousEveningToNoonOrEvent() {
        val zone = ZoneId.of("America/Los_Angeles")
        val afternoon = LocalDateTime.of(2026, 10, 16, 15, 0).atZone(zone).toInstant()
        val (start, end) = SleepContext.window(afternoon, zone)
        assertEquals(LocalDateTime.of(2026, 10, 15, 18, 0).atZone(zone).toInstant(), start)
        assertEquals(LocalDateTime.of(2026, 10, 16, 12, 0).atZone(zone).toInstant(), end)
        val morning = LocalDateTime.of(2026, 10, 16, 7, 30).atZone(zone).toInstant()
        assertEquals(morning, SleepContext.window(morning, zone).second)
    }

    @Test fun sleepSnapshotMergesStagesAndMeasuresSinceWake() {
        val zone = ZoneId.of("UTC")
        val event = LocalDateTime.of(2026, 10, 16, 10, 0).atZone(zone).toInstant()
        fun t(day: Int, h: Int, m: Int = 0): Instant = LocalDateTime.of(2026, 10, day, h, m).atZone(zone).toInstant()
        val stages = listOf(
            SleepIntervalMerge.Interval(t(15, 23), t(16, 2)),
            SleepIntervalMerge.Interval(t(16, 2, 30), t(16, 6, 30)),
            SleepIntervalMerge.Interval(t(15, 19), t(15, 19, 30)),
        )
        val snapshot = SleepContext.snapshot(stages, event)
        // 3h + 4h + the 30 minute early segment; the 30 minute awake gap is merged away for the wake time only.
        assertEquals(7.5, snapshot.sleepHoursLastNight!!, 0.001)
        assertEquals(t(16, 6, 30), snapshot.lastMainSleepWakeTime)
        assertEquals(3.5, snapshot.hoursSinceMainSleepWake!!, 0.001)
        assertFalse(SleepContext.snapshot(emptyList(), event).hasMeaningfulValue)
    }
}
