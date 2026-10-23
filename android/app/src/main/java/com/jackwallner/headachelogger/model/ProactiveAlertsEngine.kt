package com.jackwallner.headachelogger.model

import java.time.Instant
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.max
import org.json.JSONObject

enum class AlertKind(val raw: String) { PRESSURE_DROP("pressureDrop"), AIR_QUALITY("airQuality") }

data class AlertDecision(val kind: AlertKind, val title: String, val body: String)

/** 24-hour forward window of forecast data. */
data class HourlyForecast(val times: List<Instant>, val pressureMsl: List<Double?>, val usAqi: List<Double?>)

data class PersonalSignalProfile(
    val totalDays: Int = 0,
    val conditionDays: Int = 0,
    val headacheConditionDays: Int = 0,
    val pHeadacheGivenCondition: Double = 0.0,
    val pHeadacheGivenNoCondition: Double = 0.0,
    val relativeRisk: Double = 0.0,
    val lift: Double = 0.0,
    val isSupported: Boolean = false,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("totalDays", totalDays).put("conditionDays", conditionDays).put("headacheConditionDays", headacheConditionDays)
        .put("pHeadacheGivenCondition", pHeadacheGivenCondition).put("pHeadacheGivenNoCondition", pHeadacheGivenNoCondition)
        .put("relativeRisk", relativeRisk).put("lift", lift).put("isSupported", isSupported)

    companion object {
        val EMPTY = PersonalSignalProfile()

        fun fromJson(json: JSONObject?): PersonalSignalProfile = if (json == null) EMPTY else PersonalSignalProfile(
            json.optInt("totalDays"), json.optInt("conditionDays"), json.optInt("headacheConditionDays"),
            json.optDouble("pHeadacheGivenCondition", 0.0), json.optDouble("pHeadacheGivenNoCondition", 0.0),
            json.optDouble("relativeRisk", 0.0), json.optDouble("lift", 0.0), json.optBoolean("isSupported"),
        )
    }
}

data class PersonalAlertProfile(
    val updatedAtMillis: Long = 0,
    val pressure: PersonalSignalProfile = PersonalSignalProfile.EMPTY,
    val airQuality: PersonalSignalProfile = PersonalSignalProfile.EMPTY,
) {
    fun toJson(): String = JSONObject()
        .put("updatedAt", updatedAtMillis).put("pressure", pressure.toJson()).put("airQuality", airQuality.toJson()).toString()

    companion object {
        val EMPTY = PersonalAlertProfile()

        fun fromJson(text: String?): PersonalAlertProfile {
            if (text.isNullOrEmpty()) return EMPTY
            return runCatching {
                val json = JSONObject(text)
                PersonalAlertProfile(
                    json.optLong("updatedAt"),
                    PersonalSignalProfile.fromJson(json.optJSONObject("pressure")),
                    PersonalSignalProfile.fromJson(json.optJSONObject("airQuality")),
                )
            }.getOrDefault(EMPTY)
        }
    }
}

enum class RiskLevel(val raw: String) { LOW("low"), MODERATE("moderate"), HIGH("high") }

data class RiskFactor(val id: String, val icon: String, val title: String, val detail: String)

data class RiskForecast(val level: RiskLevel, val score: Int, val factors: List<RiskFactor>, val recommendation: String, val evaluatedAt: Instant)

data class PatternCluster(
    val weekdayIndex: Int,
    val weekdayName: String,
    val startHour: Int,
    val endHour: Int,
    val headacheCount: Int,
    val totalHeadaches: Int,
) {
    val share: Double get() = if (totalHeadaches > 0) headacheCount.toDouble() / totalHeadaches else 0.0
}

/** Port of `ProactiveAlertsEngine.swift`'s pure decisions. Delivery lives in `alerts/`. */
object ProactiveAlertsEngine {
    const val MIN_NOTIFICATION_GAP_MS = 6 * 60 * 60 * 1000L

    const val PERSONAL_MIN_SAMPLE_SIZE = 5
    const val PERSONAL_MIN_CONDITION_DAYS = 5
    const val PERSONAL_MIN_RELATIVE_RISK = 1.5
    const val PERSONAL_MIN_HEADACHE_CONDITION_DAYS = 3
    const val PATTERN_MIN_EVENTS = 7

    fun dailyRiskForecast(
        forecast: HourlyForecast?,
        sleepLastNightHours: Double?,
        profile: PersonalAlertProfile = PersonalAlertProfile.EMPTY,
        now: Instant = Instant.now(),
    ): RiskForecast? {
        // Missing inputs cannot establish a low-risk forecast, even when sleep is available.
        val aqiPeak = forecast?.usAqi?.filterNotNull()?.maxOrNull() ?: return null
        if (forecast.pressureMsl.filterNotNull().size < 2) return null
        var score = 0
        val factors = mutableListOf<RiskFactor>()
        if (forecast != null) {
            val maxDrop = maxDrop(forecast.pressureMsl).first
            if (maxDrop >= 6) {
                score += if (profile.pressure.isSupported) 3 else 2
                factors += RiskFactor(
                    "pressure", "barometer", "Pressure dropping",
                    String.format(Locale.US, "%.1f hPa drop forecast in the next 24h.", maxDrop) + personalNote(profile.pressure),
                )
            } else if (maxDrop >= 3) {
                score += 1
                factors += RiskFactor("pressure-mild", "barometer", "Mild pressure shift", String.format(Locale.US, "%.1f hPa drop forecast.", maxDrop))
            }
            if (aqiPeak >= 150) {
                score += 3
                factors += RiskFactor("aqi-high", "aqi.high", "Unhealthy air", "AQI is forecast to reach ${aqiPeak.toInt()}.")
            } else if (aqiPeak >= 100) {
                score += if (profile.airQuality.isSupported) 2 else 1
                factors += RiskFactor("aqi-moderate", "aqi.medium", "Elevated air quality", "AQI forecast peak: ${aqiPeak.toInt()}." + personalNote(profile.airQuality))
            }
        }
        if (sleepLastNightHours != null) {
            if (sleepLastNightHours < 5) {
                score += 3
                factors += RiskFactor("sleep-very-low", "bed.double.fill", "Very short sleep", String.format(Locale.US, "%.1fh last night, well under your usual window.", sleepLastNightHours))
            } else if (sleepLastNightHours < 6) {
                score += 2
                factors += RiskFactor("sleep-low", "bed.double.fill", "Short sleep", String.format(Locale.US, "%.1fh last night.", sleepLastNightHours))
            }
        }
        val level = when (score) {
            in 0..1 -> RiskLevel.LOW
            in 2..3 -> RiskLevel.MODERATE
            else -> RiskLevel.HIGH
        }
        return RiskForecast(level, score, factors, recommendationText(level, factors, sleepLastNightHours), now)
    }

    private fun personalNote(signal: PersonalSignalProfile): String {
        if (!signal.isSupported || signal.conditionDays <= 0) return ""
        return " You've logged headaches on ${signal.headacheConditionDays} of ${signal.conditionDays} similar days."
    }

    private fun recommendationText(level: RiskLevel, factors: List<RiskFactor>, sleep: Double?): String {
        val ids = factors.map { it.id }.toSet()
        val hasPressure = "pressure" in ids || "pressure-mild" in ids
        val hasAQI = "aqi-high" in ids || "aqi-moderate" in ids
        val hasSleep = "sleep-very-low" in ids || "sleep-low" in ids
        return when (level) {
            RiskLevel.LOW -> if (sleep != null && sleep >= 7) {
                "Nothing in today's forecast stands out, and last night's sleep is working in your favor. A normal day."
            } else "Nothing in today's forecast stands out. A good day to keep your usual routine."
            RiskLevel.MODERATE -> {
                val tips = mutableListOf("Hydrate early")
                if (hasPressure) tips += "keep rescue meds within reach"
                if (hasAQI) tips += "limit time outdoors and run an air filter if you have one"
                if (hasSleep) tips += "protect tonight's sleep window"
                "A moderate day. " + sentence(tips) + " and watch for your usual early signs."
            }
            RiskLevel.HIGH -> {
                val tips = mutableListOf("Pre-hydrate now", "keep rescue meds handy")
                if (hasAQI) tips += "stay indoors with filtered air when you can"
                if (hasSleep) tips += "prioritize rest and ease off screens"
                if (hasPressure && !hasAQI && !hasSleep) tips += "plan lighter commitments if you can"
                "Treat today as high-risk. " + sentence(tips) + "."
            }
        }
    }

    private fun sentence(tips: List<String>): String = when (tips.size) {
        0 -> ""
        1 -> tips[0]
        2 -> "${tips[0]} and ${tips[1]}"
        else -> tips.dropLast(1).joinToString(", ") + ", and ${tips.last()}"
    }

    /** Largest peak-to-later-trough drop and the index where it ends. */
    private fun maxDrop(pressures: List<Double?>): Pair<Double, Int> {
        var maxDrop = 0.0
        var end = 0
        for (i in pressures.indices) {
            val peak = pressures[i] ?: continue
            for (j in i + 1 until pressures.size) {
                val trough = pressures[j] ?: continue
                val delta = peak - trough
                if (delta > maxDrop) {
                    maxDrop = delta
                    end = j
                }
            }
        }
        return maxDrop to end
    }

    fun evaluate(forecast: HourlyForecast, prefs: ProAlertPreferenceValues, profile: PersonalAlertProfile): AlertDecision? {
        if (profile.pressure.isSupported) {
            pressureDecision(forecast, prefs.pressureDropThresholdHpa, profile.pressure)?.let { return it }
        }
        if (prefs.airQualityEnabled && profile.airQuality.isSupported) {
            airQualityDecision(forecast, prefs.airQualityThreshold, profile.airQuality)?.let { return it }
        }
        return null
    }

    private fun pressureDecision(forecast: HourlyForecast, threshold: Double, signal: PersonalSignalProfile): AlertDecision? {
        if (forecast.pressureMsl.size < 4) return null
        val (drop, end) = maxDrop(forecast.pressureMsl)
        if (drop < threshold) return null
        val hours = max(1, end)
        val body = "Forecast: ${String.format(Locale.US, "%.1f hPa", drop)} drop over the next ${hours}h. You've recorded headaches on ${signal.headacheConditionDays} of ${signal.conditionDays} similar days in your history."
        return AlertDecision(AlertKind.PRESSURE_DROP, "Personal pressure trigger ahead", body)
    }

    private fun airQualityDecision(forecast: HourlyForecast, threshold: Int, signal: PersonalSignalProfile): AlertDecision? {
        val peak = forecast.usAqi.filterNotNull().maxOrNull() ?: return null
        if (peak.toInt() < threshold) return null
        val body = "AQI is forecast to reach ${peak.toInt()} today. You've recorded headaches on ${signal.headacheConditionDays} of ${signal.conditionDays} similar days in your history."
        return AlertDecision(AlertKind.AIR_QUALITY, "Personal air-quality trigger ahead", body)
    }

    // Personal signal profile

    fun makePersonalAlertProfile(records: List<DailyRecord>, nowMillis: Long = System.currentTimeMillis()): PersonalAlertProfile {
        if (records.isEmpty()) return PersonalAlertProfile.EMPTY
        return PersonalAlertProfile(nowMillis, pressureSignalProfile(records), airQualitySignalProfile(records))
    }

    fun pressureSignalProfile(records: List<DailyRecord>): PersonalSignalProfile = signalProfile(DailyRecords.pressureConditionCounts(records))

    fun airQualitySignalProfile(records: List<DailyRecord>): PersonalSignalProfile = signalProfile(DailyRecords.aqiConditionCounts(records))

    private fun signalProfile(counts: ConditionCounts): PersonalSignalProfile {
        if (counts.totalDays < PERSONAL_MIN_SAMPLE_SIZE) return PersonalSignalProfile.EMPTY
        val supported = counts.conditionDays >= PERSONAL_MIN_CONDITION_DAYS &&
            counts.headacheConditionDays >= PERSONAL_MIN_HEADACHE_CONDITION_DAYS &&
            counts.relativeRisk >= PERSONAL_MIN_RELATIVE_RISK
        return PersonalSignalProfile(
            counts.totalDays, counts.conditionDays, counts.headacheConditionDays,
            counts.pHeadacheGivenCondition, counts.pHeadacheGivenNoCondition, counts.relativeRisk, counts.lift, supported,
        )
    }

    // Pattern-based predictive alerts

    /**
     * Weekday by hour clusters that clear the sensitivity threshold. Sensitivity 0 is
     * "high chance only" (30% share, 5 logs); 1 is "any chance" (15% share, 3 logs).
     */
    fun analyzeTimePatterns(events: List<HeadacheEvent>, sensitivity: Double, locale: Locale = Locale.getDefault()): List<PatternCluster> {
        if (events.size < PATTERN_MIN_EVENTS) return emptyList()
        val minShare = 0.30 - 0.15 * sensitivity
        val minCount = max(3, (5.0 - 2.0 * sensitivity).toInt())
        val total = events.size
        val buckets = HashMap<Int, HashMap<Int, Int>>()
        for (event in events) {
            val hours = buckets.getOrPut(event.weekdayIndex) { HashMap() }
            hours[event.hourOfDay] = (hours[event.hourOfDay] ?: 0) + 1
        }
        val clusters = mutableListOf<PatternCluster>()
        for (wd in 1..7) {
            val hours = buckets[wd] ?: continue
            val qualifying = hours.filter { (_, count) -> count.toDouble() / total >= minShare && count >= minCount }
            if (qualifying.isEmpty()) continue
            val name = InsightsEngine.weekdaySymbol(wd, TextStyle.FULL, locale)
            val sorted = qualifying.keys.sorted()
            var start = sorted[0]
            var end = sorted[0]
            var count = qualifying.getValue(sorted[0])
            for (h in sorted.drop(1)) {
                if (h == end + 1) {
                    end = h
                    count += qualifying.getValue(h)
                } else {
                    clusters += PatternCluster(wd, name, start, end, count, total)
                    start = h
                    end = h
                    count = qualifying.getValue(h)
                }
            }
            clusters += PatternCluster(wd, name, start, end, count, total)
        }
        return clusters.sortedByDescending { it.share }
    }

    fun patternNotificationBody(cluster: PatternCluster): String {
        val share = Math.round(cluster.share * 100)
        return "$share% of your headaches fall on ${cluster.weekdayName}s around ${formatHourRange(cluster.startHour, cluster.endHour)}."
    }

    private val hourFormat = DateTimeFormatter.ofPattern("h a", Locale.US)

    fun formatHourRange(start: Int, end: Int): String {
        fun fmt(hour: Int) = LocalTime.of(hour.coerceIn(0, 23), 0).format(hourFormat).lowercase()
        return if (start == end) fmt(start) else "${fmt(start)}–${fmt(end)}"
    }
}

/** When a pattern alert fires: one hour before the cluster starts, at the next matching weekday. */
object PatternSchedule {
    fun triggerHour(startHour: Int): Int = if (startHour > 0) startHour - 1 else 23

    /** Swift weekday (1 Sunday ... 7 Saturday) to the next strictly-future fire time, like `Calendar.nextDate`. */
    fun nextFire(weekdayIndex: Int, startHour: Int, now: java.time.ZonedDateTime): java.time.ZonedDateTime {
        val target = if (weekdayIndex == 1) java.time.DayOfWeek.SUNDAY else java.time.DayOfWeek.of(weekdayIndex - 1)
        var candidate = now.toLocalDate().atTime(triggerHour(startHour), 0).atZone(now.zone)
        while (candidate.dayOfWeek != target || !candidate.isAfter(now)) {
            candidate = candidate.toLocalDate().plusDays(1).atTime(triggerHour(startHour), 0).atZone(now.zone)
        }
        return candidate
    }
}
