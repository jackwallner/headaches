package com.jackwallner.headachelogger

import com.jackwallner.headachelogger.model.AlertKind
import com.jackwallner.headachelogger.model.DailyRecord
import com.jackwallner.headachelogger.model.DailyRecords
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.HeadacheSeverity
import com.jackwallner.headachelogger.model.HeatmapData
import com.jackwallner.headachelogger.model.HourlyForecast
import com.jackwallner.headachelogger.model.InsightCategory
import com.jackwallner.headachelogger.model.InsightsEngine
import com.jackwallner.headachelogger.model.PersonalAlertProfile
import com.jackwallner.headachelogger.model.PersonalSignalProfile
import com.jackwallner.headachelogger.model.PressureTrend
import com.jackwallner.headachelogger.model.ProAlertPreferenceValues
import com.jackwallner.headachelogger.model.ProactiveAlertsEngine
import com.jackwallner.headachelogger.model.RiskLevel
import java.time.LocalDate
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Ports of the insights, alerts, daily-record, heatmap and risk tests in `HeadacheLoggerTests.swift`. */
class InsightsParityTest {
    @Before fun locale() = Locale.setDefault(Locale.US)

    private fun summarize(events: List<HeadacheEvent>, records: List<DailyRecord> = emptyList()) =
        InsightsEngine.summarize(events, records, locale = Locale.US)

    @Test fun insightsReturnsEmptyBelowMinimumSampleSize() {
        val events = (0 until InsightsEngine.MINIMUM_SAMPLE_SIZE - 1).map { makeEvent(it, 19) }
        val summary = summarize(events)
        assertEquals(events.size, summary.totalEvents)
        assertTrue(summary.insights.isEmpty())
    }

    @Test fun insightsDateRangeReflectsLoggedSpan() {
        val summary = summarize((0 until 6).map { makeEvent(it, 12) })
        assertNotNull(summary.firstDate)
        assertNotNull(summary.lastDate)
        assertEquals(6, summary.totalEvents)
    }

    @Test fun partOfDayInsightFiresOnEveningCluster() {
        val events = (0 until 7).map { makeEvent(it, 19) } + makeEvent(8, 7) + makeEvent(9, 14)
        val pod = summarize(events).insights.firstOrNull { it.id == "part-of-day" }
        assertNotNull(pod)
        assertEquals(InsightCategory.TIME, pod!!.category)
        assertTrue(pod.detail.lowercase().contains("evening"))
        assertEquals(4, pod.breakdown.buckets.size)
        assertEquals("Evening", pod.breakdown.buckets.first { it.isPeak }.label)
        assertEquals(1.0, pod.breakdown.buckets.sumOf { it.share }, 0.001)
    }

    @Test fun partOfDayInsightSuppressedWhenNoCluster() {
        val events = listOf(7, 7, 14, 14, 19, 19, 2, 2).mapIndexed { i, h -> makeEvent(i, h) }
        assertNull(summarize(events).insights.firstOrNull { it.id == "part-of-day" })
    }

    @Test fun sleepInsightFiresOnLowSleepCluster() {
        val events = listOf(4.5, 4.8, 5.2, 5.6, 7.5, 7.9, 8.1).mapIndexed { i, h -> makeEvent(i, 12).apply { sleepHoursLastNight = h } }
        val sleep = summarize(events).insights.firstOrNull { it.id == "sleep" }
        assertNotNull(sleep)
        assertTrue(sleep!!.detail.contains("under 6 hours"))
        assertTrue(sleep.strength > 0.5)
    }

    @Test fun pressureTrendInsightFiresOnFallingCluster() {
        val trends = listOf(PressureTrend.FALLING, PressureTrend.FALLING, PressureTrend.FALLING, PressureTrend.FALLING, PressureTrend.FALLING, PressureTrend.STEADY, PressureTrend.RISING)
        val events = trends.mapIndexed { i, t -> makeEvent(i, 14).apply { pressureTrendRaw = t.raw } }
        val pressure = summarize(events).insights.firstOrNull { it.id == "pressure-trend" }
        assertNotNull(pressure)
        assertEquals(InsightCategory.PRESSURE, pressure!!.category)
        assertTrue(pressure.title.lowercase().contains("falling"))
    }

    @Test fun pressureTrendIgnoresUnavailable() {
        val events = (0 until 6).map { i -> makeEvent(i, 14).apply { if (i < 4) pressureTrendRaw = PressureTrend.FALLING.raw } }
        assertNull(summarize(events).insights.firstOrNull { it.id == "pressure-trend" })
    }

    @Test fun airQualityInsightFiresOnElevatedExposure() {
        val events = listOf(80.0, 95.0, 110.0, 60.0, 40.0, 75.0).mapIndexed { i, q -> makeEvent(i, 14).apply { usAQI = q } }
        val aqi = summarize(events).insights.firstOrNull { it.id == "aqi" }
        assertNotNull(aqi)
        assertEquals(InsightCategory.AIR_QUALITY, aqi!!.category)
    }

    @Test fun insightsRankByStrength() {
        val events = (0 until 8).map { makeEvent(it, 19).apply { sleepHoursLastNight = 4.5 } }
        val insights = summarize(events).insights
        assertTrue(insights.size >= 2)
        insights.zipWithNext().forEach { (a, b) -> assertTrue(a.strength >= b.strength) }
    }

    @Test fun personalAlertProfileSupportsPressureOnlyWhenUserDataMatches() {
        val supported = testRecords(
            14, setOf(0, 1, 2, 3, 4, 7, 8),
            mapOf(0 to PressureTrend.FALLING, 1 to PressureTrend.FALLING, 2 to PressureTrend.FALLING, 3 to PressureTrend.FALLING, 4 to PressureTrend.FALLING,
                6 to PressureTrend.RISING, 8 to PressureTrend.RISING, 11 to PressureTrend.RISING, 12 to PressureTrend.RISING),
        )
        val profile = ProactiveAlertsEngine.pressureSignalProfile(supported)
        assertTrue(profile.isSupported)
        assertEquals(5, profile.conditionDays)
        assertEquals(5, profile.headacheConditionDays)
        assertTrue(profile.relativeRisk > 1.5)
        val unsupported = testRecords(14, setOf(0, 1, 6, 7, 8, 9, 10), mapOf(0 to PressureTrend.FALLING, 11 to PressureTrend.FALLING))
        assertFalse(ProactiveAlertsEngine.pressureSignalProfile(unsupported).isSupported)
    }

    private val prefs = ProAlertPreferenceValues(
        alertsEnabled = true, pressureDropThresholdHpa = 4.0, airQualityEnabled = true, airQualityThreshold = 100,
        quietHoursEnabled = false, quietHoursStart = 22, quietHoursEnd = 7, patternAlertsEnabled = false, patternAlertSensitivity = 0.0,
    )

    private fun forecast(pressure: List<Double>, aqi: List<Double?>) =
        HourlyForecast(pressure.indices.map { epoch(it * 3600L) }, pressure, aqi)

    @Test fun forecastAlertRequiresPersonalPressureSignal() {
        val f = forecast(listOf(1015.0, 1014.0, 1011.0, 1009.0, 1008.0, 1008.0), List(6) { null })
        assertNull(ProactiveAlertsEngine.evaluate(f, prefs, PersonalAlertProfile.EMPTY))
        val profile = PersonalAlertProfile(
            0,
            pressure = PersonalSignalProfile(14, 5, 5, 5.0 / 6.0, 2.0 / 8.0, 3.33, 2.33, true),
            airQuality = PersonalSignalProfile.EMPTY,
        )
        val decision = ProactiveAlertsEngine.evaluate(f, prefs, profile)
        assertEquals(AlertKind.PRESSURE_DROP, decision?.kind)
        assertTrue(decision!!.body.contains("recorded headaches on"))
        assertTrue(decision.body.contains("similar days"))
    }

    @Test fun forecastAlertCanUsePersonalAirQualitySignal() {
        val f = forecast(listOf(1012.0, 1012.0, 1012.0, 1012.0), listOf(80.0, 95.0, 120.0, 110.0))
        val profile = PersonalAlertProfile(
            0,
            pressure = PersonalSignalProfile.EMPTY,
            airQuality = PersonalSignalProfile(14, 4, 4, 4.0 / 5.0, 3.0 / 9.0, 2.4, 1.4, true),
        )
        val decision = ProactiveAlertsEngine.evaluate(f, prefs, profile)
        assertEquals(AlertKind.AIR_QUALITY, decision?.kind)
        assertTrue(decision!!.body.contains("recorded headaches on"))
        assertTrue(decision.body.contains("similar days"))
    }

    @Test fun dailyRecordMergeCountsEventsAndFillsCalendarGaps() {
        val today = LocalDate.now()
        val twoDaysAgo = today.minusDays(2)
        val first = makeEvent(2, 1)
        val second = makeEvent(2, 2)
        val records = DailyRecords.merged(emptyList(), listOf(first, second), today)
        assertEquals(listOf(twoDaysAgo, today.minusDays(1), today), records.map { it.date })
        assertEquals(listOf(2, 0, 0), records.map { it.headacheCount })
        assertEquals(listOf(true, false, false), records.map { it.hadHeadache })
    }

    @Test fun dailyRecordMergePreservesBackfilledContextAndReflectsDeletedEvents() {
        val today = LocalDate.now()
        val yesterday = today.minusDays(1)
        val existing = DailyRecord(yesterday, true, 4, PressureTrend.FALLING.raw, 91.0, true, 6.5, true)
        val restored = DailyRecords.merged(listOf(existing), emptyList(), today).first { it.date == yesterday }
        assertFalse(restored.hadHeadache)
        assertEquals(0, restored.headacheCount)
        assertEquals(PressureTrend.FALLING, restored.pressureTrend)
        assertEquals(91.0, restored.usAQI)
        assertEquals(6.5, restored.sleepHoursLastNight)
        assertTrue(restored.weatherFetched)
        assertTrue(restored.sleepFetched)
    }

    @Test fun heatmapIsEmptyWithNoEvents() {
        assertTrue(HeatmapData.build(emptyList(), 90).isEmpty())
    }

    @Test fun heatmapStartsAtFirstLoggedHeadache() {
        val days = HeatmapData.build(listOf(makeEvent(10, 9)), 90)
        assertEquals(LocalDate.now().minusDays(10), days.first().date)
        assertEquals(LocalDate.now(), days.last().date)
        assertEquals(11, days.size)
    }

    @Test fun heatmapCountsAndPeakSeverityPerDay() {
        val slight = makeEvent(1, 9).apply { severity = HeadacheSeverity.SLIGHT }
        val extreme = makeEvent(1, 18).apply { severity = HeadacheSeverity.EXTREME }
        val other = makeEvent(3, 12)
        val days = HeatmapData.build(listOf(slight, extreme, other), 90)
        val cell = days.first { it.date == LocalDate.now().minusDays(1) }
        assertEquals(2, cell.count)
        assertEquals(HeadacheSeverity.EXTREME, cell.peakSeverity)
        assertNull(days.first { it.date == LocalDate.now().minusDays(3) }.peakSeverity)
    }

    @Test fun heatmapExcludesEventsOutsideWindow() {
        assertTrue(HeatmapData.build(listOf(makeEvent(200, 9)), 90).all { it.count == 0 })
    }

    private val calm = forecast(listOf(1015.0, 1015.0, 1014.0, 1015.0, 1015.0, 1015.0), listOf(20.0, 25.0, 30.0, 20.0, 15.0, 10.0))
    private val stormy = forecast(listOf(1018.0, 1016.0, 1013.0, 1011.0, 1010.0, 1010.0), listOf(60.0, 90.0, 120.0, 160.0, 140.0, 100.0))

    @Test fun dailyRiskLowWhenNoSignals() {
        val risk = ProactiveAlertsEngine.dailyRiskForecast(calm, 8.0)
        assertEquals(RiskLevel.LOW, risk.level)
        assertTrue(risk.factors.isEmpty())
    }

    @Test fun dailyRiskHighOnPressureDropAirQualityAndShortSleep() {
        val risk = ProactiveAlertsEngine.dailyRiskForecast(stormy, 4.5)
        assertEquals(RiskLevel.HIGH, risk.level)
        listOf("pressure", "aqi-high", "sleep-very-low").forEach { id -> assertTrue(id, risk.factors.any { it.id == id }) }
    }

    @Test fun dailyRiskHandlesMissingForecast() {
        val risk = ProactiveAlertsEngine.dailyRiskForecast(null, 5.5)
        assertEquals(RiskLevel.MODERATE, risk.level)
        assertEquals(listOf("sleep-low"), risk.factors.map { it.id })
    }

    @Test fun headacheFreeDayInsightFiresOnProtectiveSleep() {
        val records = sleepRecords(10, 8.5, 1, 0) + sleepRecords(10, 4.5, 7, 10)
        val events = (0 until 8).map { makeEvent(it, 12) }
        val free = summarize(events, records).insights.firstOrNull { it.id == "headache-free-days" }
        assertNotNull(free)
        assertEquals(InsightCategory.SLEEP, free!!.category)
        assertEquals("8h+", free.breakdown.buckets.first { it.isPeak }.label)
        assertFalse(free.detail.contains("—"))
    }

    @Test fun headacheFreeDayInsightSilentWithoutBaseline() {
        val events = (0 until 8).map { makeEvent(it, 12) }
        assertNull(summarize(events).insights.firstOrNull { it.id == "headache-free-days" })
    }

    @Test fun dailyRiskRecommendationIsTailored() {
        val low = ProactiveAlertsEngine.dailyRiskForecast(calm, 8.0)
        assertTrue(low.recommendation.isNotEmpty())
        assertTrue(low.recommendation.lowercase().contains("favor"))
        val high = ProactiveAlertsEngine.dailyRiskForecast(stormy, 4.5)
        assertEquals(RiskLevel.HIGH, high.level)
        assertTrue(high.recommendation.lowercase().contains("high-risk"))
        assertFalse(high.recommendation.contains("—"))
    }

    @Test fun insightCopyNeverUsesEmDashes() {
        val events = (0 until 9).map { i ->
            makeEvent(i, 19).apply {
                sleepHoursLastNight = 4.5; usAQI = 110.0; pressureTrendRaw = PressureTrend.FALLING.raw
                severity = HeadacheSeverity.EXTREME
            }
        }
        val insights = summarize(events).insights
        assertTrue(insights.isNotEmpty())
        insights.forEach { i ->
            listOf(i.title, i.detail, i.whyItMatters, i.yourPattern, i.breakdown.axisCaption).forEach { assertFalse(it, it.contains("—")) }
        }
    }

    private fun testRecords(totalDays: Int, headacheDays: Set<Int>, trends: Map<Int, PressureTrend>): List<DailyRecord> {
        val today = LocalDate.now()
        return (0 until totalDays).map { i ->
            val had = i in headacheDays
            DailyRecord(today.minusDays(i.toLong()), had, if (had) 1 else 0, (trends[i] ?: PressureTrend.STEADY).raw, null, true, null, false)
        }.sortedBy { it.date }
    }

    private fun sleepRecords(count: Int, hours: Double, headaches: Int, startDaysAgo: Int): List<DailyRecord> {
        val today = LocalDate.now()
        return (0 until count).map { i ->
            val had = i < headaches
            DailyRecord(today.minusDays((startDaysAgo + i).toLong()), had, if (had) 1 else 0, PressureTrend.UNAVAILABLE.raw, null, false, hours, true)
        }
    }
}
