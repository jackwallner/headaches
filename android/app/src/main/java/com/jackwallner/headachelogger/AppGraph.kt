package com.jackwallner.headachelogger

import android.content.Context
import androidx.glance.appwidget.updateAll
import com.jackwallner.headachelogger.alerts.Alerts
import com.jackwallner.headachelogger.billing.ConversionDiagnostics
import com.jackwallner.headachelogger.billing.StoreService
import com.jackwallner.headachelogger.capture.AndroidDeviceState
import com.jackwallner.headachelogger.capture.CaptureCoordinator
import com.jackwallner.headachelogger.capture.EnvironmentService
import com.jackwallner.headachelogger.capture.EnvironmentSource
import com.jackwallner.headachelogger.capture.HealthConnectService
import com.jackwallner.headachelogger.capture.HealthSource
import com.jackwallner.headachelogger.capture.WeatherBackfill
import com.jackwallner.headachelogger.data.DailyRecordFile
import com.jackwallner.headachelogger.data.DiskTextFile
import com.jackwallner.headachelogger.data.EventStore
import com.jackwallner.headachelogger.data.HeadacheSettings
import com.jackwallner.headachelogger.data.HealthPermissionBridge
import com.jackwallner.headachelogger.data.QuizStore
import com.jackwallner.headachelogger.data.ReviewPromptTracker
import com.jackwallner.headachelogger.data.SharedPreferencesStore
import com.jackwallner.headachelogger.model.ProactiveAlertsEngine
import com.jackwallner.headachelogger.widget.HeadacheWidget
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Every long-lived object the screens share, built once per process. */
class AppGraph(context: Context) {
    val appContext: Context = context.applicationContext
    val scope = MainScope()
    val defaults = SharedPreferencesStore(appContext)
    val settings = HeadacheSettings(defaults)
    val review = ReviewPromptTracker(defaults)
    val diagnostics = ConversionDiagnostics(defaults)
    val store = StoreService(appContext, defaults, diagnostics)
    val quiz = QuizStore(defaults)
    val events = EventStore(DiskTextFile(File(appContext.filesDir, "headache_events.json")))
    val dailyRecords = DailyRecordFile(DiskTextFile(File(appContext.filesDir, "daily_records.json")))
    var health: HealthSource = HealthConnectService(appContext)
    var environment: EnvironmentSource = EnvironmentService(appContext, settings)
    val permissions = HealthPermissionBridge()
    val capture = CaptureCoordinator(
        store = events,
        health = object : HealthSource {
            override suspend fun access() = health.access()
            override suspend fun capture(at: java.time.Instant) = health.capture(at)
            override suspend fun sleepHoursForNightBefore(day: java.time.LocalDate) = health.sleepHoursForNightBefore(day)
        },
        environment = object : EnvironmentSource {
            override suspend fun capture(at: java.time.Instant) = environment.capture(at)
            override fun hasPermission() = environment.hasPermission()
            override fun authorizationSummary() = environment.authorizationSummary()
        },
        review = review,
        device = AndroidDeviceState(appContext),
        scope = scope,
        afterCapture = { schedulePatternAlerts() },
    )

    init {
        events.onChange = {
            if (settings.hasCompletedOnboarding) dailyRecords.sync(events.events)
            refreshWidgets()
        }
    }

    fun refreshWidgets() {
        scope.launch { runCatching { HeadacheWidget().updateAll(appContext) } }
    }

    /** Port of `schedulePatternAlertsIfEnabled`, which also refreshes the personal alert profile. */
    fun schedulePatternAlerts() {
        val records = dailyRecords.load()
        settings.personalAlertProfile = ProactiveAlertsEngine.makePersonalAlertProfile(records)
        if (!settings.patternAlertsEnabled || !store.isPro) {
            Alerts.cancelPatterns(appContext)
            return
        }
        val clusters = ProactiveAlertsEngine.analyzeTimePatterns(events.events.sortedBy { it.timestamp }.take(2000), settings.patternAlertSensitivity)
        Alerts.reschedulePatterns(appContext, clusters)
    }

    fun updateForecastSchedule() {
        Alerts.updateForecastSchedule(appContext, store.isPro && settings.alertsEnabled)
    }

    /** Onboarding's `initializeDailyRecords`: seed today, or rebuild from imported events, then backfill weather. */
    fun initializeDailyRecords() {
        if (events.events.isEmpty()) {
            dailyRecords.save(listOf(com.jackwallner.headachelogger.model.DailyRecord(java.time.LocalDate.now())))
        } else {
            dailyRecords.sync(events.events)
        }
        maintainDailyRecords()
    }

    /** `DailyRecordStore.backfillSleep`: fill last-night sleep from Health Connect for days that have none yet. */
    suspend fun backfillSleep(): List<com.jackwallner.headachelogger.model.DailyRecord> {
        val records = dailyRecords.load()
        if (records.none { !it.sleepFetched && it.weatherFetched }) return records
        val updated = records.map { record ->
            if (record.sleepFetched) record
            else health.sleepHoursForNightBefore(record.date)?.let { record.copy(sleepHoursLastNight = it, sleepFetched = true) } ?: record
        }
        dailyRecords.save(updated)
        return updated
    }

    /** Port of `maintainDailyRecordsIfNeeded`: archive weather for days with no log. */
    fun maintainDailyRecords() {
        if (!settings.hasCompletedOnboarding) return
        val records = dailyRecords.sync(events.events)
        val coord = settings.cachedLocation ?: return
        if (records.count { !it.weatherFetched } < 2) return
        scope.launch {
            val updated = withContext(Dispatchers.IO) { WeatherBackfill.backfill(records, coord.latitude, coord.longitude) }
            dailyRecords.save(com.jackwallner.headachelogger.model.DailyRecords.merged(updated, events.events))
        }
    }
}
