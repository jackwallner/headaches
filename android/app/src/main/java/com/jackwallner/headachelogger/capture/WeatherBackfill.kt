package com.jackwallner.headachelogger.capture

import com.jackwallner.headachelogger.model.DailyRecord
import com.jackwallner.headachelogger.model.OpenMeteo
import java.time.LocalDate
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** Port of `DailyWeatherBackfillService`: archive pressure and AQI for days the app never saw. */
object WeatherBackfill {
    private const val TIMEOUT_MS = 15_000

    /** Inclusive batches of at most `maxDays` days. */
    fun batches(start: LocalDate, end: LocalDate, maxDays: Int = 30): List<Pair<LocalDate, LocalDate>> {
        val out = mutableListOf<Pair<LocalDate, LocalDate>>()
        var cursor = start
        while (!cursor.isAfter(end)) {
            val batchEnd = minOf(cursor.plusDays((maxDays - 1).toLong()), end)
            out += cursor to batchEnd
            cursor = batchEnd.plusDays(1)
        }
        return out
    }

    suspend fun backfill(records: List<DailyRecord>, latitude: Double, longitude: Double): List<DailyRecord> {
        val missing = records.filter { !it.weatherFetched }
        if (missing.isEmpty()) return records
        val updated = records.toMutableList()
        for ((start, end) in batches(missing.first().date, missing.last().date)) {
            if (missing.none { !it.date.isBefore(start) && !it.date.isAfter(end) }) continue
            val (weather, aqi) = coroutineScope {
                val w = async { Http.get(OpenMeteo.archivePressureUrl(latitude, longitude, start, end), TIMEOUT_MS)?.let(OpenMeteo::parseDailyPressureTrends) }
                val a = async { Http.get(OpenMeteo.archiveAirUrl(latitude, longitude, start, end), TIMEOUT_MS)?.let(OpenMeteo::parseDailyAqiPeaks) }
                w.await() to a.await()
            }
            for (i in updated.indices) {
                val r = updated[i]
                if (r.date.isBefore(start) || r.date.isAfter(end)) continue
                val key = r.date.toString()
                var next = r
                weather?.get(key)?.let { (trend, fetched) ->
                    next = next.copy(pressureTrendRaw = trend.raw, weatherFetched = next.weatherFetched || fetched)
                }
                aqi?.get(key)?.let { next = next.copy(usAQI = it, weatherFetched = true) }
                updated[i] = next
            }
        }
        return updated
    }
}
