package com.jackwallner.headachelogger.data

import com.jackwallner.headachelogger.model.DailyRecord
import com.jackwallner.headachelogger.model.DailyRecords
import com.jackwallner.headachelogger.model.HeadacheEvent
import java.time.LocalDate
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject

/** Persistence half of iOS `DailyRecordStore`: `daily_records.json` on device. */
class DailyRecordFile(private val file: TextFile) {
    fun load(): List<DailyRecord> {
        val text = file.read() ?: return emptyList()
        val array = runCatching { JSONArray(text) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { i -> array.optJSONObject(i)?.let(::decode) }.sortedBy { it.date }
    }

    fun save(records: List<DailyRecord>) {
        val array = JSONArray()
        records.sortedBy { it.date }.forEach { array.put(encode(it)) }
        file.write(array.toString())
    }

    /** Merges the events into what is on disk and saves the result. */
    fun sync(events: List<HeadacheEvent>, today: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault()): List<DailyRecord> {
        val merged = DailyRecords.merged(load(), events, today, zone)
        save(merged)
        return merged
    }

    private fun encode(r: DailyRecord): JSONObject = JSONObject()
        .put("date", r.date.toString())
        .put("hadHeadache", r.hadHeadache)
        .put("headacheCount", r.headacheCount)
        .put("pressureTrendRaw", r.pressureTrendRaw)
        .put("weatherFetched", r.weatherFetched)
        .put("sleepFetched", r.sleepFetched)
        .apply {
            r.usAQI?.let { put("usAQI", it) }
            r.sleepHoursLastNight?.let { put("sleepHoursLastNight", it) }
        }

    private fun decode(o: JSONObject): DailyRecord? {
        val date = runCatching { LocalDate.parse(o.getString("date")) }.getOrNull() ?: return null
        return DailyRecord(
            date = date,
            hadHeadache = o.optBoolean("hadHeadache"),
            headacheCount = o.optInt("headacheCount"),
            pressureTrendRaw = o.optString("pressureTrendRaw", "unavailable"),
            usAQI = if (o.has("usAQI")) o.optDouble("usAQI") else null,
            weatherFetched = o.optBoolean("weatherFetched"),
            sleepHoursLastNight = if (o.has("sleepHoursLastNight")) o.optDouble("sleepHoursLastNight") else null,
            sleepFetched = o.optBoolean("sleepFetched"),
        )
    }
}
