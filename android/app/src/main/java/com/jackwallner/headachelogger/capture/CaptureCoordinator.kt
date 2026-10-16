package com.jackwallner.headachelogger.capture

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.headachelogger.data.EventStore
import com.jackwallner.headachelogger.data.ReviewPromptTracker
import com.jackwallner.headachelogger.model.CaptureStatus
import com.jackwallner.headachelogger.model.HeadacheEvent
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/** Device state iOS stores with each log. */
fun interface DeviceStateReader {
    fun read(event: HeadacheEvent)
}

class AndroidDeviceState(private val context: Context) : DeviceStateReader {
    override fun read(event: HeadacheEvent) {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        if (level >= 0 && scale > 0) {
            event.batteryLevelPercent = level * 100.0 / scale
            val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            event.isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        }
        event.isLowPowerMode = context.getSystemService(PowerManager::class.java)?.isPowerSaveMode
    }
}

/**
 * Port of `CaptureCoordinator`: saves the tap first, then fills Health and
 * weather context, with the same banners, undo, retry and widget enrichment.
 */
class CaptureCoordinator(
    private val store: EventStore,
    private val health: HealthSource,
    private val environment: EnvironmentSource,
    private val review: ReviewPromptTracker,
    private val device: DeviceStateReader,
    private val scope: CoroutineScope,
    private val afterCapture: suspend () -> Unit = {},
) {
    var bannerMessage by mutableStateOf<String?>(null)
    var bannerIsError by mutableStateOf(false)
    var isCapturing by mutableStateOf(false)
        private set
    var lastCapturedEventId by mutableStateOf<UUID?>(null)
        private set
    var proPromptShownThisSession by mutableStateOf(false)

    /** Bumped after a complete log so the host can schedule the rating ask. */
    var positiveMomentTick by mutableStateOf(0)
        private set

    private var isEnriching = false

    private suspend fun collect(at: Instant) = coroutineScope {
        val h = async { health.capture(at) }
        val e = async { environment.capture(at) }
        h.await() to e.await()
    }

    fun captureHeadache(at: Instant = Instant.now()): Boolean {
        val event = HeadacheEvent(at)
        runCatching { device.read(event) }
        val saved = runCatching { store.insert(event) }.isSuccess
        if (!saved) {
            bannerMessage = "Could not save event. Try again."
            bannerIsError = true
            return false
        }
        lastCapturedEventId = event.id
        isCapturing = true
        bannerMessage = "Saving and collecting context…"
        bannerIsError = false
        val id = event.id
        scope.launch {
            val (h, e) = collect(event.timestamp)
            val found = store.find(id)
            if (found == null) {
                isCapturing = false
                bannerMessage = "Could not update event."
                bannerIsError = true
                return@launch
            }
            found.apply(h)
            found.apply(e)
            found.finalizeCapture()
            store.save()
            isCapturing = false
            bannerIsError = false
            bannerMessage = when (found.captureStatus) {
                CaptureStatus.COMPLETE -> {
                    review.recordPositiveMoment()
                    positiveMomentTick += 1
                    "Context saved."
                }
                CaptureStatus.PARTIAL -> "Saved with partial context."
                CaptureStatus.FAILED -> "Saved; some context unavailable."
                CaptureStatus.PENDING -> null
            }
            afterCapture()
        }
        return true
    }

    fun retryCapture(id: UUID) {
        if (isCapturing) return
        val event = store.find(id)
        if (event == null) {
            bannerMessage = "Could not find event to retry."
            return
        }
        isCapturing = true
        bannerMessage = "Retrying context capture…"
        bannerIsError = false
        scope.launch {
            val (h, e) = collect(event.timestamp)
            val found = store.find(id)
            if (found == null) {
                isCapturing = false
                bannerMessage = "Retry failed. Event missing."
                bannerIsError = true
                return@launch
            }
            found.apply(h)
            found.apply(e)
            found.finalizeCapture()
            store.save()
            isCapturing = false
            when (found.captureStatus) {
                CaptureStatus.COMPLETE -> { bannerMessage = "Context saved."; bannerIsError = false }
                CaptureStatus.PARTIAL -> { bannerMessage = "Still partial. You can email the developer from the event card."; bannerIsError = true }
                CaptureStatus.FAILED -> { bannerMessage = "Retry still failed. Email the developer from the event card."; bannerIsError = true }
                CaptureStatus.PENDING -> { bannerMessage = null; bannerIsError = false }
            }
            afterCapture()
        }
    }

    fun undoLastCapture() {
        val id = lastCapturedEventId ?: return
        if (store.delete(id)) {
            lastCapturedEventId = null
            bannerMessage = "Last entry undone."
            bannerIsError = false
        } else {
            lastCapturedEventId = null
            bannerMessage = null
        }
    }

    /** Widget logs and interrupted captures get context when the app opens. */
    fun enrichPendingCapturesIfNeeded() {
        if (isCapturing || isEnriching) return
        val pending = store.pendingCaptures()
        if (pending.isEmpty()) return
        isEnriching = true
        scope.launch {
            var updated = 0
            try {
                for (event in pending) {
                    val (h, e) = collect(event.timestamp)
                    val found = store.find(event.id) ?: continue
                    found.apply(h)
                    found.apply(e)
                    found.finalizeCapture()
                    store.save()
                    updated++
                }
            } finally {
                isEnriching = false
            }
            if (updated > 0) {
                bannerMessage = if (updated == 1) "Updated context for a pending log." else "Updated context for $updated pending logs."
                bannerIsError = false
                afterCapture()
            }
        }
    }
}
