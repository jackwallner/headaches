package com.jackwallner.headachelogger

import android.content.Intent
import com.jackwallner.headachelogger.billing.PackageKind
import com.jackwallner.headachelogger.billing.PeriodUnit
import com.jackwallner.headachelogger.billing.Plan
import com.jackwallner.headachelogger.billing.PlanPeriod
import com.jackwallner.headachelogger.capture.EnvironmentSource
import com.jackwallner.headachelogger.capture.HealthAccess
import com.jackwallner.headachelogger.capture.HealthSource
import com.jackwallner.headachelogger.data.Appearance
import com.jackwallner.headachelogger.data.CachedLocation
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.CaptureStatus
import com.jackwallner.headachelogger.model.EnvironmentCaptureResult
import com.jackwallner.headachelogger.model.EnvironmentSnapshot
import com.jackwallner.headachelogger.model.HealthCaptureResult
import com.jackwallner.headachelogger.model.HealthSnapshot
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.HeadacheSeverity
import com.jackwallner.headachelogger.model.PressureTrend
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/**
 * Debug builds only. Launch extras for screenshots and UI tests:
 * `resetAll`, `completeSetup`, `seedDemo` (the iOS screenshot seed), `demoPro`,
 * `previewStore`, `fakeContext` (offline Health and weather), `appearance`
 * (light|dark), `tab` (home|history|patterns|settings), `sheet`
 * (paywall|trial|prointro|details|alerts), `onboardingStep` (0-3), `noPromos`.
 */
object DebugLaunchOptions {
    var tab: String? = null
    var sheet: String? = null
    var onboardingStep: Int? = null
    var suppressPromos: Boolean = false

    fun prepare(app: HeadacheApplication, intent: Intent?) {
        if (intent?.getBooleanExtra("resetAll", false) != true) return
        val graph = app.graph
        graph.defaults.keys().toList().forEach { graph.defaults.remove(it) }
        graph.events.replaceAll(emptyList())
        graph.dailyRecords.save(emptyList())
        app.rebuildGraph()
    }

    fun apply(graph: AppGraph, intent: Intent?) {
        intent ?: return
        tab = intent.getStringExtra("tab")
        sheet = intent.getStringExtra("sheet")
        onboardingStep = intent.getStringExtra("onboardingStep")?.toIntOrNull()
        suppressPromos = intent.getBooleanExtra("noPromos", false)
        when (intent.getStringExtra("appearance")) {
            "light" -> graph.settings.appearance = Appearance.LIGHT
            "dark" -> graph.settings.appearance = Appearance.DARK
        }
        if (intent.getBooleanExtra("fakeContext", false)) {
            graph.health = FakeHealth
            graph.environment = FakeEnvironment
        }
        if (intent.getBooleanExtra("completeSetup", false)) graph.settings.hasCompletedOnboarding = true
        if (intent.hasExtra("demoPro")) graph.store.setLocalOverride(intent.getBooleanExtra("demoPro", false))
        if (intent.getBooleanExtra("previewStore", false)) graph.store.loadPreviewPlans(previewPlans())
        if (intent.getBooleanExtra("seedDemo", false)) seed(graph)
    }

    private fun previewPlans(): List<Plan> = listOf(
        Plan("\$rc_annual", "com.jackwallner.headachelogger.pro.yearly", PackageKind.YEARLY, 31_990_000, "$31.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), PlanPeriod(7, PeriodUnit.DAY), "Yearly"),
        Plan("\$rc_monthly", "com.jackwallner.headachelogger.pro.monthly", PackageKind.MONTHLY, 7_990_000, "$7.99", "USD", PlanPeriod(1, PeriodUnit.MONTH), PlanPeriod(7, PeriodUnit.DAY), "Monthly"),
        Plan("\$rc_lifetime", "com.jackwallner.headachelogger", PackageKind.LIFETIME, 71_990_000, "$71.99", "USD", null, null, "Lifetime"),
    )

    private data class Seed(
        val daysAgo: Long, val hour: Int, val severity: HeadacheSeverity, val steps: Int,
        val sleep: Double, val pressure: Double, val weather: String, val note: String,
    )

    /** `HeadacheScreenshotSeed` from iOS, minus steps (Android reads sleep only) and with AQI filled in. */
    private fun seed(graph: AppGraph) {
        val entries = listOf(
            Seed(0, 8, HeadacheSeverity.SLIGHT, 7_420, 7.4, 1016.0, "Partly cloudy", "Started after a screen-heavy morning. Added context for my private record."),
            Seed(1, 18, HeadacheSeverity.MEDIUM, 9_180, 6.8, 1013.0, "Clear", "After a long workday"),
            Seed(3, 12, HeadacheSeverity.SLIGHT, 6_540, 7.1, 1018.0, "Clear", "Logged from the desk"),
            Seed(5, 21, HeadacheSeverity.MEDIUM, 8_230, 6.5, 1014.0, "Cloudy", "Evening check-in"),
            Seed(7, 9, HeadacheSeverity.SLIGHT, 5_980, 8.0, 1017.0, "Partly cloudy", "Quick note"),
            Seed(10, 16, HeadacheSeverity.MEDIUM, 10_240, 6.2, 1011.0, "Light rain", "Afternoon check-in"),
            Seed(13, 11, HeadacheSeverity.SLIGHT, 7_860, 7.7, 1019.0, "Clear", "Logged from the park"),
            Seed(16, 20, HeadacheSeverity.MEDIUM, 6_710, 6.9, 1015.0, "Cloudy", "Evening check-in"),
            Seed(20, 14, HeadacheSeverity.SLIGHT, 8_640, 7.3, 1016.0, "Clear", "Afternoon note"),
            Seed(24, 10, HeadacheSeverity.MEDIUM, 7_110, 6.6, 1012.0, "Partly cloudy", "Morning check-in"),
            Seed(28, 19, HeadacheSeverity.SLIGHT, 9_520, 7.9, 1018.0, "Clear", "Evening check-in"),
        )
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now()
        val trends = listOf(PressureTrend.STEADY, PressureTrend.RISING, PressureTrend.FALLING)
        val events = entries.mapIndexed { index, e ->
            val ts = today.minusDays(e.daysAgo).atTime(LocalTime.of(e.hour, 12)).atZone(zone).toInstant()
            HeadacheEvent(ts, zone).apply {
                captureStatus = CaptureStatus.COMPLETE
                captureCompletedAt = ts.plusSeconds(42)
                healthStatus = CaptureSourceStatus.CAPTURED
                environmentStatus = CaptureSourceStatus.CAPTURED
                locality = "Seattle"
                region = "WA"
                weatherSummary = e.weather
                temperatureC = 15.0
                pressureHpa = e.pressure
                pressureTrend = trends[index % 3]
                usAQI = 24.0 + (index * 7) % 30
                sleepHoursLastNight = e.sleep
                severity = e.severity
                userNotes = e.note
            }
        }
        graph.settings.cachedLocation = CachedLocation(47.6062, -122.3321, Instant.now())
        graph.events.replaceAll(events)
        graph.dailyRecords.sync(graph.events.events)
    }

    private object FakeHealth : HealthSource {
        override suspend fun access() = HealthAccess.READY
        override suspend fun capture(at: Instant) = HealthCaptureResult(
            CaptureSourceStatus.CAPTURED, null,
            HealthSnapshot(7.2, at.minus(Duration.ofHours(3)), 3.0),
        )
        override suspend fun sleepHoursForNightBefore(day: LocalDate): Double = 7.0
    }

    private object FakeEnvironment : EnvironmentSource {
        override suspend fun capture(at: Instant) = EnvironmentCaptureResult(
            CaptureSourceStatus.CAPTURED, null,
            EnvironmentSnapshot(
                locality = "Seattle", region = "WA", weatherSummary = "Partly cloudy", weatherCode = 2,
                temperatureC = 15.0, apparentTemperatureC = 14.0, humidityPercent = 71.0, pressureHpa = 1012.0,
                pressureTrend = PressureTrend.FALLING, usAQI = 38.0,
            ),
        )
        override fun hasPermission() = true
        override fun authorizationSummary() = "Allowed"
    }
}
