package com.jackwallner.headachelogger

import com.jackwallner.headachelogger.data.EventStore
import com.jackwallner.headachelogger.data.MemoryTextFile
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.CaptureStatus
import com.jackwallner.headachelogger.model.EventCsv
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.HeadacheSeverity
import com.jackwallner.headachelogger.model.ImportStrategy
import com.jackwallner.headachelogger.model.MotionActivity
import com.jackwallner.headachelogger.model.PressureTrend
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ports of the export/import tests in `HeadacheLoggerTests.swift`, plus on-device storage. */
class CsvParityTest {
    private val zone = ZoneId.of("America/Chicago")

    @Test fun csvExportIncludesImportantColumnsAndValues() {
        val event = HeadacheEvent(epoch(1_744_406_400), zone).apply {
            locality = "Austin"
            region = "TX"
            weatherSummary = "Rain"
            temperatureC = 19.5
            stepsToday = 3456
            sleepHoursLastNight = 6.75
            lastMainSleepWakeTime = epoch(1_744_400_000)
            hoursSinceMainSleepWake = 1.78
            vo2MaxMlPerKgPerMin = 44.2
            barometricPressureDeltaHpa6h = -1.2
            usAQI = 41.0
            captureStatus = CaptureStatus.PARTIAL
            healthStatus = CaptureSourceStatus.CAPTURED
            environmentStatus = CaptureSourceStatus.FAILED
            healthStatusMessage = "Heart data unavailable"
            environmentStatusMessage = "Pollen unavailable"
            userNotes = "Saw aura first"
            severity = HeadacheSeverity.MEDIUM
        }
        val csv = EventCsv.export(listOf(event))
        listOf(
            "# One Tap Headache Tracker", "# row_count: 1", "event_id,timestamp,timezone", "weekday,weekday_index,hour",
            "temperature_f", "feels_like_f", "\"67.1\"", ",severity", ",user_notes", "last_main_sleep_wake_utc",
            "barometric_pressure_delta_hpa_6h", "\"44.2\"", "\"-1.2\"", "\"Austin, TX\"", "\"Rain\"", "\"3456\"", "\"6.75\"",
            "\"Heart data unavailable\"", "\"Pollen unavailable\"", "\"Saw aura first\"", "\"medium\"",
        ).forEach { assertTrue("missing $it", csv.contains(it)) }
    }

    @Test fun exportImportRoundTripPreservesAllFields() {
        val original = fullyPopulated()
        val rows = EventCsv.parse(EventCsv.export(listOf(original)))
        assertEquals(1, rows.size)
        val existing = mutableListOf(original)
        val skip = EventCsv.importInto(existing, rows, ImportStrategy.SKIP_EXISTING, zone)
        assertEquals(0, skip.imported)
        assertEquals(1, skip.skipped)
        val over = EventCsv.importInto(existing, rows, ImportStrategy.OVERWRITE_EXISTING, zone)
        assertEquals(1, over.overwritten)
        val fresh = mutableListOf<HeadacheEvent>()
        assertEquals(1, EventCsv.importInto(fresh, rows, ImportStrategy.SKIP_EXISTING, zone).imported)
        assertEventEquals(fullyPopulated(original.id), fresh.single())
    }

    @Test fun importHandlesMultipleEventsWithDedup() {
        val e1 = HeadacheEvent(epoch(1_700_000_000), zone).apply { severity = HeadacheSeverity.SLIGHT; userNotes = "event one" }
        val e2 = HeadacheEvent(epoch(1_700_100_000), zone).apply { severity = HeadacheSeverity.EXTREME }
        val e3 = HeadacheEvent(epoch(1_700_200_000), zone).apply { temperatureC = 25.5 }
        val rows = EventCsv.parse(EventCsv.export(listOf(e1, e2, e3)))
        assertEquals(3, rows.size)
        val withFirst = mutableListOf(e1)
        assertEquals(2, EventCsv.importInto(withFirst, rows, ImportStrategy.SKIP_EXISTING, zone).imported)
        val result = EventCsv.importInto(mutableListOf(), rows, ImportStrategy.SKIP_EXISTING, zone)
        assertEquals(3, result.imported)
        assertEquals(0, result.skipped)
        assertEquals(0, result.errors)
    }

    @Test fun importSkipsInvalidRowsGracefully() {
        val valid = HeadacheEvent(epoch(1_700_000_000), zone).apply { severity = HeadacheSeverity.MEDIUM }
        val rows = EventCsv.parse(EventCsv.export(listOf(valid)))
        val tampered = rows[0].toMutableMap().apply { put("event_id", "not-a-uuid"); put("timestamp", "garbage-timestamp") }
        val result = EventCsv.importInto(mutableListOf(valid), rows + tampered, ImportStrategy.SKIP_EXISTING, zone)
        assertEquals(1, result.skipped)
        assertEquals(1, result.errors)
        assertEquals(0, result.imported)
    }

    @Test fun csvPreambleIsSkippedByParser() {
        val event = HeadacheEvent(epoch(1_700_000_000), zone)
        val rows = EventCsv.parse(EventCsv.export(listOf(event)))
        assertEquals(1, rows.size)
        assertEquals(event.id.toString().uppercase(), rows[0]["event_id"])
    }

    @Test fun exportImportHeavyDutyRoundTrip() {
        val base = epoch(1_744_000_000)
        val events = (0 until 20).map { i ->
            HeadacheEvent(base.plusSeconds(i * 7200L), zone).apply {
                temperatureC = (20 + i % 15).toDouble()
                humidityPercent = (40 + i % 40).toDouble()
                pressureHpa = (1010 + i % 20).toDouble()
                stepsToday = (5000 + i * 123) % 12000
                sleepHoursLastNight = (5 + i % 5).toDouble()
                severity = HeadacheSeverity.entries[i % 3]
                userNotes = if (i % 5 == 0) "Note for event $i" else null
                usAQI = (20 + i % 60).toDouble()
                pm25 = (i % 30).toDouble()
                alderPollen = if (i % 2 == 0) i.toDouble() else null
            }
        }
        val rows = EventCsv.parse(EventCsv.export(events))
        assertEquals(20, rows.size)
        val imported = mutableListOf<HeadacheEvent>()
        val result = EventCsv.importInto(imported, rows, ImportStrategy.SKIP_EXISTING, zone)
        assertEquals(20, result.imported)
        assertEquals(0, result.errors)
        events.sortedBy { it.timestamp }.zip(imported.sortedBy { it.timestamp }).forEach { (o, n) ->
            assertEquals(o.temperatureC, n.temperatureC)
            assertEquals(o.humidityPercent, n.humidityPercent)
            assertEquals(o.pressureHpa, n.pressureHpa)
            assertEquals(o.stepsToday, n.stepsToday)
            assertEquals(o.sleepHoursLastNight, n.sleepHoursLastNight)
            assertEquals(o.severity, n.severity)
            assertEquals(o.userNotes, n.userNotes)
            assertEquals(o.usAQI, n.usAQI)
            assertEquals(o.alderPollen, n.alderPollen)
        }
    }

    @Test fun formulaLikeNotesAreGuardedInCsvButNotInStorage() {
        val event = HeadacheEvent(epoch(1_700_000_000), zone).apply { userNotes = "=HYPERLINK(1)" }
        assertTrue(EventCsv.export(listOf(event)).contains("\"'=HYPERLINK(1)\""))
        val file = MemoryTextFile()
        EventStore(file, { zone }).insert(event)
        assertEquals("=HYPERLINK(1)", EventStore(file, { zone }).events.single().userNotes)
    }

    @Test fun eventStorePersistsEveryFieldAcrossLaunches() {
        val file = MemoryTextFile()
        val original = fullyPopulated()
        original.hoursSinceMainSleepWake = 3.14159
        original.captureCompletedAt = original.timestamp.plusSeconds(42)
        EventStore(file, { zone }).insert(original)
        val reloaded = EventStore(file, { zone }).events.single()
        assertEventEquals(original, reloaded)
        assertEquals(3.14159, reloaded.hoursSinceMainSleepWake!!, 1e-9)
        assertEquals(original.captureCompletedAt, reloaded.captureCompletedAt)
        assertEquals(original.createdAt.toEpochMilli(), reloaded.createdAt.toEpochMilli())
    }

    @Test fun eventStoreKeepsNewestFirstAndDeletes() {
        val store = EventStore(MemoryTextFile(), { zone })
        val older = HeadacheEvent(epoch(1_700_000_000), zone)
        val newer = HeadacheEvent(epoch(1_700_100_000), zone)
        store.insert(older)
        store.insert(newer)
        assertEquals(listOf(newer.id, older.id), store.events.map { it.id })
        store.delete(newer.id)
        assertEquals(listOf(older.id), store.events.map { it.id })
        assertNull(store.find(newer.id))
    }

    @Test fun eventStoreImportsCsv() {
        val store = EventStore(MemoryTextFile(), { zone })
        val csv = EventCsv.export(listOf(fullyPopulated()))
        assertEquals(1, store.importCsv(csv, ImportStrategy.SKIP_EXISTING).imported)
        assertEquals(1, store.importCsv(csv, ImportStrategy.SKIP_EXISTING).skipped)
        assertEquals(1, store.events.size)
    }

    private fun fullyPopulated(id: java.util.UUID? = null): HeadacheEvent {
        val timestamp = LocalDateTime.of(2026, 5, 10, 14, 30).atZone(zone).toInstant()
        return HeadacheEvent(timestamp, zone).apply {
            if (id != null) this.id = id
            captureStatusRaw = CaptureStatus.COMPLETE.raw
            healthStatusRaw = CaptureSourceStatus.CAPTURED.raw
            environmentStatusRaw = CaptureSourceStatus.CAPTURED.raw
            healthStatusMessage = "Heart data incomplete"
            environmentStatusMessage = "Pollen data partial"
            locality = "Portland"; region = "OR"; altitudeM = 47.0
            weatherSummary = "Partly Cloudy"; weatherCode = 2
            temperatureC = 18.75; apparentTemperatureC = 19.2; humidityPercent = 64.5; pressureHpa = 1012.3
            pressureTrendRaw = PressureTrend.FALLING.raw; precipitationMm = 0.5; windSpeedKph = 12.3
            windDirectionDegrees = 225.0; cloudCoverPercent = 60.0; uvIndex = 4.5; dewPointC = 11.3
            usAQI = 42.0; europeanAQI = 35.0; pm25 = 8.5; pm10 = 15.2; ozone = 72.0; nitrogenDioxide = 10.5
            sulphurDioxide = 2.1; carbonMonoxide = 180.0; alderPollen = 12.0; birchPollen = 8.5; grassPollen = 3.2
            mugwortPollen = null; olivePollen = null; ragweedPollen = 1.5
            stepsToday = 8765; activeEnergyKcalToday = 320.5; distanceWalkingRunningKmToday = 5.2; exerciseMinutesToday = 35.0
            sleepHoursLastNight = 7.25; lastMainSleepWakeTime = timestamp.minusSeconds(36000); hoursSinceMainSleepWake = 10.0
            restingHeartRateBpm = 62.0; recentHeartRateAverageBpm = 72.5; hrvSDNNMs = 45.2; respiratoryRateBrpm = 16.0
            workoutsLast24h = 1; workoutMinutesLast24h = 45.0; environmentalAudioExposureDbA = 55.0
            oxygenSaturationPercent = 98.5; vo2MaxMlPerKgPerMin = 44.5; walkingSpeedMetersPerSecond = 1.2
            appleStandMinutesToday = 480.0; basalEnergyKcalToday = 1800.0; flightsClimbedToday = 4.0; mindfulMinutesToday = 10.0
            barometricPressureDeltaHpa6h = -2.5; caffeineMgToday = 150.0; waterMlToday = 900.0; daysSinceLastPeriodStart = 12
            bloodPressureSystolicMmHg = 118.0; bloodPressureDiastolicMmHg = 76.0; bloodGlucoseMgPerDL = 92.0
            headphoneAudioExposureDbA = 68.0; timeInDaylightMinutesToday = 55.0; batteryLevelPercent = 73.0
            isCharging = true; isLowPowerMode = false; motionActivity = MotionActivity.WALKING
            severity = HeadacheSeverity.EXTREME; userNotes = "Started after lunch, aura present"
        }
    }

    private fun assertEventEquals(o: HeadacheEvent, n: HeadacheEvent) {
        assertEquals(o.id, n.id)
        assertEquals(o.timestamp.toEpochMilli(), n.timestamp.toEpochMilli())
        listOf<(HeadacheEvent) -> Any?>(
            { it.timezoneIdentifier }, { it.weekdayIndex }, { it.weekdayName }, { it.hourOfDay }, { it.minuteOfHour },
            { it.partOfDayRaw }, { it.captureStatusRaw }, { it.healthStatusRaw }, { it.environmentStatusRaw },
            { it.healthStatusMessage }, { it.environmentStatusMessage }, { it.locality }, { it.region }, { it.altitudeM },
            { it.weatherSummary }, { it.weatherCode }, { it.temperatureC }, { it.apparentTemperatureC }, { it.humidityPercent },
            { it.pressureHpa }, { it.pressureTrendRaw }, { it.precipitationMm }, { it.windSpeedKph }, { it.windDirectionDegrees },
            { it.cloudCoverPercent }, { it.uvIndex }, { it.dewPointC }, { it.usAQI }, { it.europeanAQI }, { it.pm25 }, { it.pm10 },
            { it.ozone }, { it.nitrogenDioxide }, { it.sulphurDioxide }, { it.carbonMonoxide }, { it.alderPollen },
            { it.birchPollen }, { it.grassPollen }, { it.mugwortPollen }, { it.olivePollen }, { it.ragweedPollen },
            { it.stepsToday }, { it.activeEnergyKcalToday }, { it.distanceWalkingRunningKmToday }, { it.exerciseMinutesToday },
            { it.sleepHoursLastNight }, { it.lastMainSleepWakeTime?.toEpochMilli() }, { it.hoursSinceMainSleepWake },
            { it.restingHeartRateBpm }, { it.recentHeartRateAverageBpm }, { it.hrvSDNNMs }, { it.respiratoryRateBrpm },
            { it.workoutsLast24h }, { it.workoutMinutesLast24h }, { it.environmentalAudioExposureDbA },
            { it.oxygenSaturationPercent }, { it.vo2MaxMlPerKgPerMin }, { it.walkingSpeedMetersPerSecond },
            { it.appleStandMinutesToday }, { it.basalEnergyKcalToday }, { it.flightsClimbedToday }, { it.mindfulMinutesToday },
            { it.barometricPressureDeltaHpa6h }, { it.caffeineMgToday }, { it.waterMlToday }, { it.daysSinceLastPeriodStart },
            { it.bloodPressureSystolicMmHg }, { it.bloodPressureDiastolicMmHg }, { it.bloodGlucoseMgPerDL },
            { it.headphoneAudioExposureDbA }, { it.timeInDaylightMinutesToday }, { it.batteryLevelPercent }, { it.isCharging },
            { it.isLowPowerMode }, { it.motionActivityRaw }, { it.severityRaw }, { it.userNotes },
        ).forEachIndexed { i, field -> assertEquals("field $i", field(o), field(n)) }
    }
}
