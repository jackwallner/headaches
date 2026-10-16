package com.jackwallner.headachelogger.capture

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.HealthCaptureResult
import com.jackwallner.headachelogger.model.SleepContext
import com.jackwallner.headachelogger.model.SleepIntervalMerge
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlinx.coroutines.delay

/** Where the app stands with Health Connect. */
enum class HealthAccess { UNAVAILABLE, NEEDS_PERMISSION, READY }

/** The optional sleep read. A fake stands in for tests and screenshots. */
interface HealthSource {
    suspend fun access(): HealthAccess
    suspend fun capture(at: Instant): HealthCaptureResult
    suspend fun sleepHoursForNightBefore(day: LocalDate): Double?
}

object HealthPermissions {
    val sleep: String = HealthPermission.getReadPermission(SleepSessionRecord::class)
    val all: Set<String> = setOf(sleep)
}

/**
 * Port of the sleep half of `HealthKitService`. Android reads only sleep
 * sessions from Health Connect; every other HealthKit column stays empty, so
 * those insights simply never appear. Read-only and on device.
 */
class HealthConnectService(private val context: Context) : HealthSource {
    private val client: HealthConnectClient? by lazy {
        if (HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE) HealthConnectClient.getOrCreate(context) else null
    }

    override suspend fun access(): HealthAccess {
        val c = client ?: return HealthAccess.UNAVAILABLE
        val granted = runCatching { c.permissionController.getGrantedPermissions() }.getOrDefault(emptySet())
        return if (HealthPermissions.sleep in granted) HealthAccess.READY else HealthAccess.NEEDS_PERMISSION
    }

    override suspend fun capture(at: Instant): HealthCaptureResult {
        if (client == null) return HealthCaptureResult(CaptureSourceStatus.UNAVAILABLE, "Health Connect is not available on this device.", null)
        if (access() != HealthAccess.READY) return noContext()
        var snapshot = SleepContext.snapshot(asleep(at), at)
        if (!snapshot.hasMeaningfulValue) {
            delay(1_500)
            snapshot = SleepContext.snapshot(asleep(at), at)
        }
        return if (snapshot.hasMeaningfulValue) HealthCaptureResult(CaptureSourceStatus.CAPTURED, null, snapshot) else noContext()
    }

    /** The backfill asks about the night before a calendar day, using that day's noon as the event. */
    override suspend fun sleepHoursForNightBefore(day: LocalDate): Double? {
        if (access() != HealthAccess.READY) return null
        val noon = day.atTime(LocalTime.NOON).atZone(ZoneId.systemDefault()).toInstant()
        return SleepContext.summarize(asleep(noon)).first
    }

    private suspend fun asleep(at: Instant): List<SleepIntervalMerge.Interval> {
        val c = client ?: return emptyList()
        val (start, end) = SleepContext.window(at)
        val records = runCatching {
            // Sessions that began up to 12 hours earlier can still overlap the window.
            c.readRecords(ReadRecordsRequest(SleepSessionRecord::class, TimeRangeFilter.between(start.minus(Duration.ofHours(12)), end))).records
        }.getOrDefault(emptyList())
        return records.filter { it.endTime.isAfter(start) && it.startTime.isBefore(end) }.flatMap(::asleepIntervals)
    }

    /** Asleep stages when the source records them; otherwise the whole session counts as asleep. */
    private fun asleepIntervals(record: SleepSessionRecord): List<SleepIntervalMerge.Interval> {
        if (record.stages.isEmpty()) return listOf(SleepIntervalMerge.Interval(record.startTime, record.endTime))
        return record.stages.filter { it.stage in ASLEEP_STAGES }.map { SleepIntervalMerge.Interval(it.startTime, it.endTime) }
    }

    private fun noContext() = HealthCaptureResult(CaptureSourceStatus.UNAVAILABLE, "No Health context was available for this event.", null)

    private companion object {
        val ASLEEP_STAGES = setOf(
            SleepSessionRecord.STAGE_TYPE_SLEEPING,
            SleepSessionRecord.STAGE_TYPE_LIGHT,
            SleepSessionRecord.STAGE_TYPE_DEEP,
            SleepSessionRecord.STAGE_TYPE_REM,
        )
    }
}
