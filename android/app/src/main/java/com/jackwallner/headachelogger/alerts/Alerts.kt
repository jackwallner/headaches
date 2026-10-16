package com.jackwallner.headachelogger.alerts

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.jackwallner.headachelogger.HeadacheApplication
import com.jackwallner.headachelogger.MainActivity
import com.jackwallner.headachelogger.R
import com.jackwallner.headachelogger.capture.Http
import com.jackwallner.headachelogger.model.OpenMeteo
import com.jackwallner.headachelogger.model.PatternCluster
import com.jackwallner.headachelogger.model.PatternSchedule
import com.jackwallner.headachelogger.model.ProactiveAlertsEngine
import java.time.Duration
import java.time.Instant
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Delivery half of Proactive Alerts. WorkManager stands in for iOS
 * BGTaskScheduler (a forecast check about every three hours) and for the
 * calendar-triggered pattern notifications.
 */
object Alerts {
    const val CHANNEL_ID = "pro-alerts"
    private const val FORECAST_WORK = "forecast-check"
    private const val PATTERN_TAG = "pattern-alert"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Headache alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Pressure, air-quality and pattern alerts from Headache Pro."
            },
        )
    }

    fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun post(context: Context, id: Int, title: String, body: String) {
        if (!canNotify(context)) return
        ensureChannel(context)
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(id, notification) }
    }

    /** Matches iOS `scheduleBackgroundIfNeeded`: only Pro users with alerts on get the periodic check. */
    fun updateForecastSchedule(context: Context, enabled: Boolean) {
        val wm = WorkManager.getInstance(context)
        if (!enabled) {
            wm.cancelUniqueWork(FORECAST_WORK)
            return
        }
        val request = PeriodicWorkRequestBuilder<ForecastWorker>(3, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        wm.enqueueUniquePeriodicWork(FORECAST_WORK, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    fun reschedulePatterns(context: Context, clusters: List<PatternCluster>, now: ZonedDateTime = ZonedDateTime.now()) {
        val wm = WorkManager.getInstance(context)
        wm.cancelAllWorkByTag(PATTERN_TAG)
        for (cluster in clusters) {
            val fire = PatternSchedule.nextFire(cluster.weekdayIndex, cluster.startHour, now)
            val request = OneTimeWorkRequestBuilder<PatternAlertWorker>()
                .setInitialDelay(Duration.between(now, fire).toMillis(), TimeUnit.MILLISECONDS)
                .setInputData(workDataOf(KEY_BODY to ProactiveAlertsEngine.patternNotificationBody(cluster), KEY_ID to cluster.weekdayIndex * 100 + cluster.startHour))
                .addTag(PATTERN_TAG)
                .build()
            wm.enqueueUniqueWork("pattern-alert-${cluster.weekdayIndex}-${cluster.startHour}", ExistingWorkPolicy.REPLACE, request)
        }
    }

    fun cancelPatterns(context: Context) {
        WorkManager.getInstance(context).cancelAllWorkByTag(PATTERN_TAG)
    }

    const val KEY_BODY = "body"
    const val KEY_ID = "id"
}

class PatternAlertWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val body = inputData.getString(Alerts.KEY_BODY) ?: return Result.success()
        Alerts.post(applicationContext, 2_000 + inputData.getInt(Alerts.KEY_ID, 0), "Headache pattern ahead", body)
        // The next occurrence is scheduled the next time the app or the forecast check runs.
        (applicationContext as? HeadacheApplication)?.graph?.let { withContext(Dispatchers.Main) { it.schedulePatternAlerts() } }
        return Result.success()
    }
}

/** Port of `ProactiveAlertsEngine.runIfEligible`. */
class ForecastWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val graph = (applicationContext as? HeadacheApplication)?.graph ?: return Result.success()
        withContext(Dispatchers.Main) { graph.store.refreshCustomerInfo() }
        if (!graph.store.isPro) return Result.success()
        val prefs = graph.settings.alertPreferences
        if (!prefs.alertsEnabled) return Result.success()
        val coord = graph.settings.cachedLocation ?: return Result.success()
        val now = Instant.now()
        if (prefs.isQuietHour(now)) return Result.success()
        val last = graph.settings.alertLastFiredAt
        if (last != null && now.toEpochMilli() - last < ProactiveAlertsEngine.MIN_NOTIFICATION_GAP_MS) return Result.success()
        val weather = Http.get(OpenMeteo.forecastPressureUrl(coord.latitude, coord.longitude), 10_000) ?: return Result.success()
        val air = Http.get(OpenMeteo.forecastAirUrl(coord.latitude, coord.longitude), 10_000)
        val forecast = OpenMeteo.parseForecastWindow(weather, air, now) ?: return Result.success()
        val decision = ProactiveAlertsEngine.evaluate(forecast, prefs, graph.settings.personalAlertProfile) ?: return Result.success()
        if (!Alerts.canNotify(applicationContext)) return Result.success()
        Alerts.post(applicationContext, 1_000, decision.title, decision.body)
        graph.settings.recordAlertFired(decision.kind.raw, now.toEpochMilli())
        return Result.success()
    }
}
