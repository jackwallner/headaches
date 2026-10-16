package com.jackwallner.headachelogger.model

import java.time.LocalDate
import java.time.ZoneId

/** One calendar day of the baseline behind every lift number. Port of `DailyRecord`. */
data class DailyRecord(
    val date: LocalDate,
    val hadHeadache: Boolean = false,
    val headacheCount: Int = 0,
    val pressureTrendRaw: String = PressureTrend.UNAVAILABLE.raw,
    val usAQI: Double? = null,
    val weatherFetched: Boolean = false,
    val sleepHoursLastNight: Double? = null,
    val sleepFetched: Boolean = false,
) {
    val pressureTrend: PressureTrend get() = PressureTrend.from(pressureTrendRaw) ?: PressureTrend.UNAVAILABLE
    val isFallingPressure: Boolean get() = pressureTrend == PressureTrend.FALLING
    val isElevatedAQI: Boolean get() = (usAQI ?: 0.0) >= 75
}

data class ConditionCounts(
    val totalDays: Int,
    val headacheDays: Int,
    val conditionDays: Int,
    val headacheConditionDays: Int,
) {
    val pHeadacheGivenCondition: Double
        get() = if (conditionDays > 0) headacheConditionDays.toDouble() / conditionDays else 0.0

    val pHeadacheGivenNoCondition: Double
        get() {
            val noCondition = totalDays - conditionDays
            val headacheNoCondition = headacheDays - headacheConditionDays
            return if (noCondition > 0) headacheNoCondition.toDouble() / noCondition else 0.0
        }

    val relativeRisk: Double
        get() {
            val bg = pHeadacheGivenNoCondition
            return if (bg > 0) pHeadacheGivenCondition / bg else 0.0
        }

    val lift: Double get() = relativeRisk - 1.0
}

data class SleepBucketCounts(
    val label: String,
    val range: ClosedOpenRange,
    val totalDays: Int,
    val headacheDays: Int,
) {
    val headacheRate: Double get() = if (totalDays > 0) headacheDays.toDouble() / totalDays else 0.0
}

data class ClosedOpenRange(val lower: Double, val upper: Double) {
    operator fun contains(value: Double): Boolean = value >= lower && value < upper
}

/** Port of `DailyRecordStore`'s pure parts; persistence lives in `data/DailyRecordFile`. */
object DailyRecords {
    fun day(event: HeadacheEvent, zone: ZoneId = ZoneId.systemDefault()): LocalDate = event.timestamp.atZone(zone).toLocalDate()

    /**
     * Events win on `hadHeadache` and `headacheCount`; fetched weather and sleep on an
     * existing record are never discarded. Every day from the earliest known one through
     * `today` is present so the denominator stays honest.
     */
    fun merged(
        existing: List<DailyRecord>,
        events: List<HeadacheEvent>,
        today: LocalDate = LocalDate.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<DailyRecord> {
        val byDate = HashMap<LocalDate, DailyRecord>()
        // Events are authoritative for the headache columns: a deleted event turns a day back.
        for (record in existing) byDate[record.date] = record.copy(hadHeadache = false, headacheCount = 0)

        for (event in events) {
            val day = day(event, zone)
            if (day.isAfter(today)) continue
            var record = byDate[day] ?: DailyRecord(day)
            record = record.copy(hadHeadache = true, headacheCount = record.headacheCount + 1)
            // An event covers one moment; a day-wide archive backfill wins when present.
            if (!record.weatherFetched && event.environmentStatus == CaptureSourceStatus.CAPTURED) {
                record = record.copy(
                    pressureTrendRaw = if (event.pressureTrend != PressureTrend.UNAVAILABLE) event.pressureTrend.raw else record.pressureTrendRaw,
                    usAQI = event.usAQI?.let { maxOf(record.usAQI ?: 0.0, it) } ?: record.usAQI,
                    weatherFetched = true,
                )
            }
            val sleep = event.sleepHoursLastNight
            if (!record.sleepFetched && sleep != null) record = record.copy(sleepHoursLastNight = sleep, sleepFetched = true)
            byDate[day] = record
        }

        val earliest = byDate.keys.minOrNull() ?: return emptyList()
        var cursor = earliest
        while (!cursor.isAfter(today)) {
            byDate.getOrPut(cursor) { DailyRecord(cursor) }
            cursor = cursor.plusDays(1)
        }
        return byDate.values.sortedBy { it.date }
    }

    fun pressureConditionCounts(records: List<DailyRecord>): ConditionCounts {
        val days = records.filter { it.weatherFetched }
        return ConditionCounts(
            totalDays = days.size,
            headacheDays = days.count { it.hadHeadache },
            conditionDays = days.count { it.isFallingPressure },
            headacheConditionDays = days.count { it.hadHeadache && it.isFallingPressure },
        )
    }

    fun aqiConditionCounts(records: List<DailyRecord>): ConditionCounts {
        val days = records.filter { it.weatherFetched }
        return ConditionCounts(
            totalDays = days.size,
            headacheDays = days.count { it.hadHeadache },
            conditionDays = days.count { it.isElevatedAQI },
            headacheConditionDays = days.count { it.hadHeadache && it.isElevatedAQI },
        )
    }

    private val sleepBins = listOf(
        "<5h" to ClosedOpenRange(0.0, 5.0),
        "5–6h" to ClosedOpenRange(5.0, 6.0),
        "6–7h" to ClosedOpenRange(6.0, 7.0),
        "7–8h" to ClosedOpenRange(7.0, 8.0),
        "8h+" to ClosedOpenRange(8.0, 48.0),
    )

    fun sleepConditionCounts(records: List<DailyRecord>): List<SleepBucketCounts> {
        val sleepRecords = records.filter { it.sleepFetched }
        return sleepBins.map { (label, range) ->
            val inBucket = sleepRecords.filter { rec -> rec.sleepHoursLastNight?.let { it in range } == true }
            SleepBucketCounts(label, range, inBucket.size, inBucket.count { it.hadHeadache })
        }
    }
}
