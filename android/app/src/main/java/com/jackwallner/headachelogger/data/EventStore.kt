package com.jackwallner.headachelogger.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.neverEqualPolicy
import androidx.compose.runtime.setValue
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.EventCsv
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.ImportResult
import com.jackwallner.headachelogger.model.ImportStrategy
import java.time.ZoneId
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Sentinels the widget writes, identical to iOS `HeadacheWidgetQuickLog`. */
object WidgetQuickLog {
    const val HEALTH_MESSAGE_PENDING = "Open the app to capture Health context."
    const val ENVIRONMENT_MESSAGE_PENDING = "Open the app to capture weather."
}

/**
 * The SwiftData store of this port: every headache event, newest first, saved
 * as one JSON document on device. Each mutation writes through and publishes a
 * new list so Compose recomposes.
 */
class EventStore(
    private val file: TextFile,
    private val zone: () -> ZoneId = ZoneId::systemDefault,
) {
    var events: List<HeadacheEvent> by mutableStateOf(emptyList(), neverEqualPolicy())
        private set

    /** Called after every change, for the daily records and pattern alerts. */
    var onChange: (() -> Unit)? = null

    init {
        events = decode(file.read())
    }

    fun find(id: UUID): HeadacheEvent? = events.firstOrNull { it.id == id }

    fun insert(event: HeadacheEvent) {
        commit(events + event)
    }

    fun delete(id: UUID): Boolean {
        val next = events.filterNot { it.id == id }
        if (next.size == events.size) return false
        commit(next)
        return true
    }

    /** Persists in-place edits to an event already in the store. */
    fun save() = commit(events)

    fun replaceAll(next: List<HeadacheEvent>) = commit(next)

    /** Widget logs and interrupted captures, oldest first, as iOS `pendingCaptureFetchDescriptor`. */
    fun pendingCaptures(): List<HeadacheEvent> = events.filter(::isPendingCapture).sortedBy { it.timestamp }

    fun importCsv(contents: String, strategy: ImportStrategy): ImportResult = importRows(EventCsv.parse(contents), strategy)

    fun importRows(rows: List<Map<String, String>>, strategy: ImportStrategy): ImportResult {
        val working = events.toMutableList()
        val result = EventCsv.importInto(working, rows, strategy, zone())
        if (result.imported > 0 || result.overwritten > 0) commit(working)
        return result
    }

    private fun commit(next: List<HeadacheEvent>) {
        events = next.sortedByDescending { it.timestamp }
        file.write(encode(events))
        onChange?.invoke()
    }

    private fun encode(list: List<HeadacheEvent>): String {
        val array = JSONArray()
        for (event in list) array.put(JSONObject(EventCsv.storageRow(event) as Map<*, *>))
        return JSONObject().put("version", 1).put("events", array).toString()
    }

    private fun decode(text: String?): List<HeadacheEvent> {
        if (text.isNullOrBlank()) return emptyList()
        val array = runCatching { JSONObject(text).getJSONArray("events") }.getOrNull() ?: return emptyList()
        val out = ArrayList<HeadacheEvent>(array.length())
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            val row = obj.keys().asSequence().associateWith { obj.optString(it) }
            EventCsv.fromStorageRow(row, zone())?.let(out::add)
        }
        return out.sortedByDescending { it.timestamp }
    }

    companion object {
        fun isPendingCapture(event: HeadacheEvent): Boolean {
            val bothPending = event.healthStatus == CaptureSourceStatus.PENDING &&
                event.environmentStatus == CaptureSourceStatus.PENDING
            val widgetLog = event.healthStatusMessage == WidgetQuickLog.HEALTH_MESSAGE_PENDING &&
                event.environmentStatusMessage == WidgetQuickLog.ENVIRONMENT_MESSAGE_PENDING
            return bothPending || widgetLog
        }
    }
}
