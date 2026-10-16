package com.jackwallner.headachelogger.model

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

enum class InsightCategory { TIME, SLEEP, PRESSURE, AIR_QUALITY, HEART, WEATHER, SEVERITY }

data class Bucket(val label: String, val share: Double, val count: Int, val isPeak: Boolean)

data class Breakdown(val buckets: List<Bucket>, val evenBaseline: Double?, val axisCaption: String)

data class Insight(
    val id: String,
    val category: InsightCategory,
    val icon: String,
    val title: String,
    val detail: String,
    val strength: Double,
    val whyItMatters: String,
    val yourPattern: String,
    val breakdown: Breakdown,
)

data class InsightSummary(val totalEvents: Int, val firstDate: Instant?, val lastDate: Instant?, val insights: List<Insight>)

/**
 * Port of `InsightsEngine.swift`: pure, on-device, descriptive analysis of logged
 * headaches. Every threshold, string and ranking rule matches iOS; output says
 * what the data shows, never what causes a headache.
 */
object InsightsEngine {
    const val MINIMUM_SAMPLE_SIZE = 5

    private data class Bin(val label: String, val lower: Double, val upper: Double) {
        operator fun contains(value: Double) = value >= lower && value < upper
    }

    fun summarize(
        events: List<HeadacheEvent>,
        dailyRecords: List<DailyRecord> = emptyList(),
        useCelsius: Boolean = false,
        locale: Locale = Locale.getDefault(),
    ): InsightSummary {
        val total = events.size
        val sorted = events.map { it.timestamp }.sorted()
        if (total < MINIMUM_SAMPLE_SIZE) return InsightSummary(total, sorted.firstOrNull(), sorted.lastOrNull(), emptyList())
        val insights = listOfNotNull(
            partOfDayInsight(events),
            weekdayInsight(events, locale),
            sleepInsight(events, dailyRecords),
            pressureTrendInsight(events),
            pressureDeltaInsight(events),
            airQualityInsight(events),
            hrvInsight(events),
            humidityInsight(events),
            severityInsight(events),
            temperatureInsight(events, useCelsius),
            precipitationInsight(events),
            windInsight(events),
            caffeineInsight(events),
            hydrationInsight(events),
            exerciseInsight(events),
            pollenInsight(events),
            bloodPressureInsight(events),
            oxygenSaturationInsight(events),
            daylightInsight(events),
            audioExposureInsight(events),
            hoursSinceWakeInsight(events),
            menstrualCycleInsight(events),
            motionActivityInsight(events),
            multivariateInsight(events),
            headacheFreeDayInsight(dailyRecords),
        ).sortedByDescending { it.strength }
        return InsightSummary(total, sorted.first(), sorted.last(), insights)
    }

    /** Swift `Dictionary.max(by:)` with a deterministic tie-break: the first key in `order` wins. */
    private fun <K> topOf(counts: Map<K, Int>, order: List<K>): Pair<K, Int>? {
        var best: Pair<K, Int>? = null
        for (key in order) {
            val c = counts[key] ?: continue
            if (best == null || c > best.second) best = key to c
        }
        return best
    }

    /** Bins values and marks the first bin with the strictly largest share as the peak, like iOS. */
    private class Binned(val buckets: List<Bucket>, val topShare: Double, val topLabel: String, val topIndex: Int)

    private fun binned(values: List<Double>, bins: List<Bin>): Binned {
        val total = values.size
        var topShare = 0.0
        var topLabel = ""
        var topIndex = 0
        val raw = bins.mapIndexed { idx, bin ->
            val c = values.count { it in bin }
            val s = c.toDouble() / total
            if (s > topShare) { topShare = s; topLabel = bin.label; topIndex = idx }
            Triple(bin.label, c, s)
        }
        return Binned(raw.map { (label, c, s) -> Bucket(label, s, c, label == topLabel) }, topShare, topLabel, topIndex)
    }

    // Individual insights

    private fun partOfDayInsight(events: List<HeadacheEvent>): Insight? {
        val order = listOf(PartOfDay.MORNING, PartOfDay.AFTERNOON, PartOfDay.EVENING, PartOfDay.OVERNIGHT)
        val counts = events.groupingBy { it.partOfDay }.eachCount()
        val (top, topCount) = topOf(counts, order) ?: return null
        if (topCount <= 0) return null
        val total = events.size
        val topShare = topCount.toDouble() / total
        if (topShare < 0.30) return null
        val buckets = order.map { part ->
            val c = counts[part] ?: 0
            Bucket(label(part), c.toDouble() / total, c, part == top)
        }
        val baseline = 1.0 / order.size
        val multiple = topShare / baseline
        val yourPattern = "${percent(topShare)} of your headaches happen in the ${label(top).lowercase()}, about ${fmt1(multiple)}x what you'd expect if they were evenly spread across the day (${percent(baseline)} per period). " +
            othersSummary(buckets, label(top)) { it.label }
        return Insight(
            id = "part-of-day",
            category = InsightCategory.TIME,
            icon = icon(top),
            title = "Most common time: ${label(top)}",
            detail = "${percent(topShare)} of your logged headaches were logged in the ${label(top).lowercase()}.",
            strength = topShare,
            whyItMatters = "Headaches that cluster at a specific time of day often point to circadian or behavioural triggers: caffeine timing, screen exposure, dehydration, posture, or letdown after stress. Knowing your peak window lets you preload water, breaks, or rescue meds before you'd normally feel it coming.",
            yourPattern = yourPattern,
            breakdown = Breakdown(buckets, baseline, "Share of your headaches by part of day"),
        )
    }

    private fun weekdayInsight(events: List<HeadacheEvent>, locale: Locale): Insight? {
        val counts = events.groupingBy { it.weekdayIndex }.eachCount()
        val (topIndex, topCount) = topOf(counts, (1..7).toList()) ?: return null
        if (topCount <= 0) return null
        val total = events.size
        val topShare = topCount.toDouble() / total
        // Uniform would be about 14%; surface only when meaningfully concentrated.
        if (topShare < 0.25) return null
        val topName = weekdaySymbol(topIndex, TextStyle.FULL, locale)
        val buckets = (1..7).map { idx ->
            val c = counts[idx] ?: 0
            Bucket(weekdaySymbol(idx, TextStyle.SHORT, locale), c.toDouble() / total, c, idx == topIndex)
        }
        val baseline = 1.0 / 7.0
        val multiple = topShare / baseline
        return Insight(
            id = "weekday",
            category = InsightCategory.TIME,
            icon = "calendar",
            title = "Headache day: $topName",
            detail = "${percent(topShare)} of your headaches were logged on $topName.",
            strength = topShare - baseline,
            whyItMatters = "Weekday clusters often signal a routine trigger: stress build-up, irregular sleep on transition days, alcohol after work, or letdown on a recurring rest day. Spotting the pattern points to behavioural changes (steady sleep windows, caffeine timing, scheduled breaks) rather than medication-only fixes.",
            yourPattern = "${percent(topShare)} of your headaches fall on $topName, about ${fmt1(multiple)}x the even baseline of ${percent(baseline)} per day.",
            breakdown = Breakdown(buckets, baseline, "Share of your headaches by weekday"),
        )
    }

    private val sleepBins = listOf(
        Bin("<5h", 0.0, 5.0), Bin("5–6h", 5.0, 6.0), Bin("6–7h", 6.0, 7.0), Bin("7–8h", 7.0, 8.0), Bin("8h+", 8.0, 48.0),
    )

    private fun sleepInsight(events: List<HeadacheEvent>, dailyRecords: List<DailyRecord>): Insight? {
        val values = events.mapNotNull { it.sleepHoursLastNight }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val med = median(values)

        val sleepRecords = dailyRecords.filter { it.sleepFetched }
        val hasBaseline = sleepRecords.size >= MINIMUM_SAMPLE_SIZE
        var headline: Triple<String, Int, Double>? = null
        var liftBuckets: List<SleepBucketCounts> = emptyList()
        var overallRate = 0.0
        if (hasBaseline) {
            val all = DailyRecords.sleepConditionCounts(dailyRecords)
            val totalSleepDays = sleepRecords.size
            val totalHeadacheDays = sleepRecords.count { it.hadHeadache }
            overallRate = if (totalSleepDays > 0) totalHeadacheDays.toDouble() / totalSleepDays else 0.0
            all.forEachIndexed { idx, bucket ->
                if (bucket.totalDays < 2) return@forEachIndexed
                val lift = if (overallRate > 0) bucket.headacheRate / overallRate else 0.0
                if (lift > (headline?.third ?: 1.0) && lift >= 1.3) headline = Triple(bucket.label, idx, lift)
            }
            liftBuckets = all
        }

        val total = values.size
        val shares = sleepBins.map { bin -> values.count { it in bin }.toDouble() / total }
        val maxShare = shares.maxOrNull() ?: 0.0
        val chartBuckets = sleepBins.mapIndexed { idx, bin ->
            val c = values.count { it in bin }
            val share = c.toDouble() / total
            val isPeak = headline?.let { idx == it.second } ?: (abs(share - maxShare) < 0.001)
            Bucket(bin.label, share, c, isPeak)
        }

        val detail: String
        val strength: Double
        val yourPattern: String
        val title: String
        val h = headline
        if (h != null && h.third >= 1.3) {
            val pct = ((h.third - 1.0) * 100).toInt()
            val bucket = liftBuckets[h.second]
            val ratePct = (bucket.headacheRate * 100).toInt()
            val overallPct = (overallRate * 100).toInt()
            val moreLikely = if (h.third >= 2.0) "${fmt1(h.third)}×" else "$pct%"
            detail = "Headaches are $moreLikely more likely after ${h.first} of sleep ($ratePct% vs $overallPct% overall). Median: ${formatHours(med)}."
            strength = 0.5 + min((h.third - 1.0) / 2.0, 0.5)
            title = "Low sleep: ${h.first}"
            yourPattern = "On days following ${h.first} of sleep, your headache rate was $ratePct%, compared to $overallPct% across all days with sleep data. Median sleep before a headache: ${formatHours(med)}."
        } else {
            val lowSleepShare = values.count { it < 6 }.toDouble() / total
            if (lowSleepShare >= 0.4) {
                detail = "${percent(lowSleepShare)} of your headaches followed a night with under 6 hours of sleep. Median: ${formatHours(med)}."
                strength = 0.5 + lowSleepShare * 0.4
            } else {
                detail = "Median sleep the night before a headache: ${formatHours(med)}."
                strength = 0.35
            }
            title = "Sleep before a headache"
            yourPattern = "Median sleep the night before a headache: ${formatHours(med)}. ${percent(lowSleepShare)} of your headaches followed a night under 6 hours."
        }
        return Insight(
            id = "sleep",
            category = InsightCategory.SLEEP,
            icon = "bed.double.fill",
            title = title,
            detail = detail,
            strength = strength,
            whyItMatters = "Sleep deprivation is one of the most consistently documented headache triggers in the migraine literature. Both too little (<6h) and too much (>9h) sleep, and especially irregular timing, can precipitate attacks. Wake-time consistency, including weekends, is the single highest-leverage behavioural change for many people.",
            yourPattern = yourPattern,
            breakdown = Breakdown(chartBuckets, null, "Sleep duration the night before each headache"),
        )
    }

    private fun pressureTrendInsight(events: List<HeadacheEvent>): Insight? {
        val trends = events.map { it.pressureTrend }.filter { it != PressureTrend.UNAVAILABLE }
        if (trends.size < MINIMUM_SAMPLE_SIZE) return null
        val order = listOf(PressureTrend.FALLING, PressureTrend.STEADY, PressureTrend.RISING)
        val total = trends.size
        val coverage = coverageQualifier(total, events.size)
        val counts = trends.groupingBy { it }.eachCount()
        val (top, topCount) = topOf(counts, order) ?: return null
        val topShare = topCount.toDouble() / total
        if (topShare < 0.45) return null
        val buckets = order.map { t ->
            val c = counts[t] ?: 0
            Bucket(label(t), c.toDouble() / total, c, t == top)
        }
        val baseline = 1.0 / 3.0
        val topLabel = label(top)
        val (title, icon) = when (top) {
            PressureTrend.FALLING -> "Falling pressure pattern" to "arrow.down.right.circle.fill"
            PressureTrend.RISING -> "Rising pressure pattern" to "arrow.up.right.circle.fill"
            else -> "Steady pressure" to "minus.circle.fill"
        }
        val why = when (top) {
            PressureTrend.FALLING -> "Falling barometric pressure is the most replicated weather trigger in the migraine literature; drops typically arrive 6–24 hours before a storm and correlate with attack onset. Because it's forecastable, this is a signal you can prepare for."
            PressureTrend.RISING -> "Pressure rises (high-pressure systems building in) trigger fewer people than drops, but a clear cluster on rises still represents a forecastable signal, meaning hydration, caffeine, or rescue meds can be timed."
            else -> "A 'steady' cluster suggests pressure isn't your dominant weather trigger. Other environmental signals (humidity, AQI) or non-weather factors are likelier drivers, worth checking those screens."
        }
        return Insight(
            id = "pressure-trend",
            category = InsightCategory.PRESSURE,
            icon = icon,
            title = title,
            detail = "${percent(topShare)} of your headaches$coverage were logged during ${topLabel.lowercase()} barometric pressure.",
            strength = topShare,
            whyItMatters = why,
            yourPattern = "${percent(topShare)} of your headaches$coverage were logged during ${topLabel.lowercase()} pressure, ${fmt1(topShare / baseline)}x the even baseline of ${percent(baseline)}.",
            breakdown = Breakdown(buckets, baseline, "Pressure trend at headache onset"),
        )
    }

    private fun pressureDeltaInsight(events: List<HeadacheEvent>): Insight? {
        val deltas = events.mapNotNull { it.barometricPressureDeltaHpa6h }
        if (deltas.size < MINIMUM_SAMPLE_SIZE) return null
        val med = median(deltas)
        // Shifts under about 3 hPa over 6h are daily noise.
        if (abs(med) < 3.0) return null
        val direction = if (med < 0) "drop" else "rise"
        val bins = listOf(
            Bin("≤−6", -100.0, -6.0), Bin("−6 to −3", -6.0, -3.0), Bin("−3 to −1", -3.0, -1.0), Bin("−1 to +1", -1.0, 1.0),
            Bin("+1 to +3", 1.0, 3.0), Bin("+3 to +6", 3.0, 6.0), Bin("≥+6", 6.0, 100.0),
        )
        val total = deltas.size
        val medBin = bins.indexOfFirst { med in it }.takeIf { it >= 0 } ?: 3
        val buckets = bins.mapIndexed { idx, bin ->
            val c = deltas.count { it in bin }
            Bucket(bin.label, c.toDouble() / total, c, idx == medBin)
        }
        val shift = String.format(Locale.US, "%+.1f hPa", med)
        return Insight(
            id = "pressure-delta",
            category = InsightCategory.PRESSURE,
            icon = "barometer",
            title = "Typical 6h pressure shift",
            detail = "Median pressure change in the 6 hours before your headaches: $shift, a typical $direction.",
            strength = min(1.0, abs(med) / 6),
            whyItMatters = "The size of pressure swings tends to matter more than the absolute level. Drops of 5+ hPa within 24 hours are commonly cited thresholds for triggering migraine in sensitive people. The bigger your typical pre-headache shift, the more useful Proactive Alerts will be at giving you a heads-up.",
            yourPattern = "Median 6-hour pressure change before your headaches: $shift. The histogram on the right shows the full distribution.",
            breakdown = Breakdown(buckets, null, "6-hour pressure change (hPa) before each headache"),
        )
    }

    private fun airQualityInsight(events: List<HeadacheEvent>): Insight? {
        val aqi = events.mapNotNull { it.usAQI }
        if (aqi.size < MINIMUM_SAMPLE_SIZE) return null
        val elevated = aqi.count { it >= 75 }.toDouble() / aqi.size
        if (elevated < 0.30) return null
        val coverage = coverageQualifier(aqi.size, events.size)
        val b = binned(
            aqi,
            listOf(
                Bin("Good\n0–50", 0.0, 51.0), Bin("Moderate\n51–100", 51.0, 101.0), Bin("USG\n101–150", 101.0, 151.0),
                Bin("Unhealthy\n151–200", 151.0, 201.0), Bin("Worse\n201+", 201.0, 10000.0),
            ),
        )
        return Insight(
            id = "aqi",
            category = InsightCategory.AIR_QUALITY,
            icon = "aqi.medium",
            title = "Elevated air quality",
            detail = "${percent(elevated)} of your headaches$coverage happened with US AQI ≥ 75.",
            strength = elevated,
            whyItMatters = "Particulate matter and ozone can trigger or amplify headaches via inflammatory pathways. AQI of 75–100 is where sensitive groups typically start to feel effects; 150+ is unhealthy for everyone. On bad-air days, indoor mitigations (HEPA filters, closed windows, masks outdoors) can meaningfully reduce exposure.",
            yourPattern = "${percent(elevated)} of your headaches$coverage occurred with US AQI at or above 75, the threshold where sensitive groups commonly start to feel effects.",
            breakdown = Breakdown(b.buckets, null, "Air quality at headache onset (US AQI)"),
        )
    }

    private fun hrvInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.hrvSDNNMs }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val med = median(values)
        if (!(med < 35 || med > 80)) return null
        val bins = listOf(Bin("<30", 0.0, 30.0), Bin("30–50", 30.0, 50.0), Bin("50–80", 50.0, 80.0), Bin("80+", 80.0, 10000.0))
        val total = values.size
        val medBin = bins.indexOfFirst { med in it }.takeIf { it >= 0 } ?: 1
        val buckets = bins.mapIndexed { idx, bin ->
            val c = values.count { it in bin }
            Bucket(bin.label, c.toDouble() / total, c, idx == medBin)
        }
        val ms = String.format(Locale.US, "%.0f ms", med)
        return Insight(
            id = "hrv",
            category = InsightCategory.HEART,
            icon = "waveform.path.ecg",
            title = "HRV around your headaches",
            detail = "Median HRV (SDNN) when you've logged a headache: $ms.",
            strength = 0.30,
            whyItMatters = "Heart-rate variability tracks autonomic nervous-system balance. Lower HRV is associated with stress, poor recovery, and, for many migraine sufferers, the prodrome window 12–24 hours before an attack. Watching multi-day HRV trends can give an early warning that your threshold is dropping.",
            yourPattern = "Your median pre-headache HRV (SDNN) is $ms. The chart shows where your HRV typically sat at the moment you logged.",
            breakdown = Breakdown(buckets, null, "HRV (SDNN, ms) at headache onset"),
        )
    }

    private fun humidityInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.humidityPercent }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val high = values.count { it >= 70 }.toDouble() / values.size
        if (high < 0.40) return null
        val b = binned(values, listOf(Bin("<40%", 0.0, 40.0), Bin("40–60%", 40.0, 60.0), Bin("60–80%", 60.0, 80.0), Bin("80%+", 80.0, 101.0)))
        return Insight(
            id = "humidity",
            category = InsightCategory.WEATHER,
            icon = "humidity.fill",
            title = "High humidity pattern",
            detail = "${percent(high)} of your headaches happened with humidity at or above 70%.",
            strength = high * 0.7,
            whyItMatters = "High humidity reduces evaporative cooling and often co-occurs with the pressure drops that precede storms, a one-two punch flagged in many migraine-trigger studies. Air conditioning, hydration, and electrolyte salts are commonly suggested mitigations on muggy days.",
            yourPattern = "${percent(high)} of your headaches occurred with humidity ≥ 70%. The chart shows the full breakdown.",
            breakdown = Breakdown(b.buckets, null, "Relative humidity at headache onset"),
        )
    }

    private fun severityInsight(events: List<HeadacheEvent>): Insight? {
        val order = HeadacheSeverity.entries
        val rated = events.mapNotNull { it.severity }
        val total = rated.size
        if (total < MINIMUM_SAMPLE_SIZE) return null
        val counts = rated.groupingBy { it }.eachCount()
        val (top, topCount) = topOf(counts, order) ?: return null
        val topShare = topCount.toDouble() / total
        if (topShare < 0.50) return null
        val buckets = order.map { sev ->
            val c = counts[sev] ?: 0
            Bucket(sev.title, c.toDouble() / total, c, sev == top)
        }
        val baseline = 1.0 / 3.0
        return Insight(
            id = "severity",
            category = InsightCategory.SEVERITY,
            icon = "exclamationmark.triangle.fill",
            title = "Most often: ${top.title}",
            detail = "${percent(topShare)} of headaches you've rated were ${top.title.lowercase()}.",
            strength = topShare - baseline,
            whyItMatters = "Knowing your typical severity distribution helps frame conversations with a clinician. Frequent extreme attacks, even if they're not your most common bucket, often justify a preventive treatment plan rather than rescue meds alone.",
            yourPattern = "${percent(topShare)} of your rated headaches were ${top.title.lowercase()}, ${fmt1(topShare / baseline)}x the even baseline of ${percent(baseline)}.",
            breakdown = Breakdown(buckets, baseline, "Severity distribution across rated headaches"),
        )
    }

    private fun temperatureBins(useCelsius: Boolean): List<Bin> = if (useCelsius) {
        listOf(
            Bin("Very cold\n<0°C", -100.0, 0.0), Bin("Cold\n0–10°C", 0.0, 10.0), Bin("Cool\n10–18°C", 10.0, 18.0),
            Bin("Mild\n18–25°C", 18.0, 25.0), Bin("Warm\n25–32°C", 25.0, 32.0), Bin("Hot\n32°C+", 32.0, 100.0),
        )
    } else {
        listOf(
            Bin("Very cold\n<32°F", -100.0, 0.0), Bin("Cold\n32–50°F", 0.0, 10.0), Bin("Cool\n50–65°F", 10.0, 18.0),
            Bin("Mild\n65–77°F", 18.0, 25.0), Bin("Warm\n77–90°F", 25.0, 32.0), Bin("Hot\n90°F+", 32.0, 100.0),
        )
    }

    private fun temperatureInsight(events: List<HeadacheEvent>, useCelsius: Boolean): Insight? {
        val values = events.mapNotNull { it.apparentTemperatureC }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val bins = temperatureBins(useCelsius)
        val coverage = coverageQualifier(values.size, events.size)
        val b = binned(values, bins)
        if (b.topShare < 0.35) return null
        val baseline = 1.0 / bins.size
        if (b.topShare / baseline < 1.5) return null
        val isExtreme = b.topLabel.startsWith("Very cold") || b.topLabel.startsWith("Hot")
        val icon = if (b.topLabel.startsWith("Very cold") || b.topLabel.startsWith("Cold")) "thermometer.snowflake" else "thermometer.sun.fill"
        val inlineTop = b.topLabel.replace("\n", " ")
        return Insight(
            id = "temperature",
            category = InsightCategory.WEATHER,
            icon = icon,
            title = if (isExtreme) "$inlineTop weather cluster" else "Temperature cluster: $inlineTop",
            detail = "${percent(b.topShare)} of your headaches$coverage happened when it felt ${inlineTop.lowercase()}.",
            strength = b.topShare,
            whyItMatters = "Extreme temperatures, both hot and cold, are well-documented migraine triggers. Heat causes vasodilation and dehydration; cold triggers vasoconstriction and muscle tension. The apparent temperature (feels-like) accounts for wind chill and humidity, making it more relevant than raw air temperature.",
            yourPattern = "${percent(b.topShare)} of your headaches$coverage occurred in ${inlineTop.lowercase()} conditions, ${fmt1(b.topShare / baseline)}x the even baseline of ${percent(baseline)}. " +
                othersSummary(b.buckets, b.topLabel) { it.label.replace("\n", " ") },
            breakdown = Breakdown(b.buckets, baseline, "Apparent temperature at headache onset"),
        )
    }

    private fun precipitationInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.precipitationMm }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val dry = values.count { it == 0.0 }
        val light = values.count { it > 0 && it < 2.5 }
        val moderate = values.count { it >= 2.5 && it < 10 }
        val heavy = values.count { it >= 10 }
        val total = values.size.toDouble()
        val dryShare = dry / total
        val rainShare = 1.0 - dryShare
        if (rainShare < 0.35 || dryShare <= 0) return null
        val coverage = coverageQualifier(values.size, events.size)
        val buckets = listOf(
            Bucket("Dry", dry / total, dry, false),
            Bucket("Light\n<2.5mm", light / total, light, false),
            Bucket("Moderate\n2.5–10mm", moderate / total, moderate, false),
            Bucket("Heavy\n10mm+", heavy / total, heavy, false),
        )
        // Swift `max(by:)` returns the last of equal maxima.
        val topBucket = buckets.drop(1).reduce { best, b -> if (b.share >= best.share) b else best }
        val peaked = buckets.map { it.copy(isPeak = it.label == topBucket.label) }
        return Insight(
            id = "precipitation",
            category = InsightCategory.WEATHER,
            icon = "cloud.rain.fill",
            title = "Rainy-day cluster",
            detail = "${percent(rainShare)} of your headaches$coverage happened during rain (${percent(topBucket.share)} in the ${topBucket.label.lowercase()} band).",
            strength = rainShare,
            whyItMatters = "Rainy weather often co-occurs with falling barometric pressure, high humidity, and reduced light, a multi-factor trigger cocktail. The relationship may be indirect: people tend to stay indoors, sleep differently, or alter caffeine habits on rainy days.",
            yourPattern = "${percent(rainShare)} of your headaches$coverage occurred during active precipitation, with the most common intensity being ${topBucket.label.lowercase()}.",
            breakdown = Breakdown(peaked, null, "Precipitation at headache onset"),
        )
    }

    private fun windInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.windSpeedKph }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val coverage = coverageQualifier(values.size, events.size)
        val b = binned(values, listOf(Bin("Calm\n<5", 0.0, 5.0), Bin("Light\n5–15", 5.0, 15.0), Bin("Moderate\n15–30", 15.0, 30.0), Bin("Windy\n30+", 30.0, 500.0)))
        val isWindyPeak = b.topLabel == "Windy\n30+" || b.topLabel == "Moderate\n15–30"
        if (!isWindyPeak || b.topShare < 0.30) return null
        val inline = b.topLabel.lowercase().replace("\n", " ")
        return Insight(
            id = "wind",
            category = InsightCategory.WEATHER,
            icon = "wind",
            title = "Windy conditions",
            detail = "${percent(b.topShare)} of your headaches$coverage happened with $inline wind speeds.",
            strength = b.topShare,
            whyItMatters = "Strong winds can trigger headaches through several mechanisms: drying of mucous membranes, airborne pollen and particulate matter, barometric pressure fluctuations, and even the physical strain of bracing against gusts. Chinook and Santa Ana winds have documented associations with migraine onset.",
            yourPattern = "${percent(b.topShare)} of your headaches$coverage occurred during $inline conditions.",
            breakdown = Breakdown(b.buckets, null, "Wind speed at headache onset (km/h)"),
        )
    }

    private fun caffeineInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.caffeineMgToday }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val total = values.size.toDouble()
        val med = median(values)
        val coverage = coverageQualifier(values.size, events.size)
        val noneShare = values.count { it == 0.0 } / total
        val highShare = values.count { it >= 200 } / total
        val veryHighShare = values.count { it >= 400 } / total
        val hasVariation = values.any { it > 0 }
        val isHigh = highShare >= 0.30
        val isNone = noneShare >= 0.40 && hasVariation
        if (!isHigh && !isNone) return null
        val b = binned(
            values,
            listOf(
                Bin("None", 0.0, 0.5), Bin("Low\n1–100mg", 0.5, 100.0), Bin("Moderate\n100–200mg", 100.0, 200.0),
                Bin("High\n200–400mg", 200.0, 400.0), Bin("Very High\n400mg+", 400.0, 10000.0),
            ),
        )
        val mg = String.format(Locale.US, "%.0f mg", med)
        return if (isNone && noneShare >= highShare) {
            Insight(
                id = "caffeine-none",
                category = InsightCategory.HEART,
                icon = "cup.and.saucer.fill",
                title = "Low-caffeine days",
                detail = "${percent(noneShare)} of your headaches$coverage happened on days with zero caffeine (${percent(highShare)} high-caffeine days). Median: $mg.",
                strength = noneShare,
                whyItMatters = "Caffeine withdrawal is a well-recognized headache trigger; even skipping your usual morning coffee can precipitate a headache within hours. The relationship is U-shaped: both zero and excess caffeine can trigger attacks. Tracking your individual threshold is key.",
                yourPattern = "${percent(noneShare)} of your headaches occurred on zero-caffeine days, with only ${percent(highShare)} on high-caffeine days (≥200mg).",
                breakdown = Breakdown(b.buckets, null, "Daily caffeine consumption before headaches"),
            )
        } else {
            Insight(
                id = "caffeine-high",
                category = InsightCategory.HEART,
                icon = "cup.and.saucer.fill",
                title = "High-caffeine days",
                detail = "${percent(highShare)} of your headaches$coverage happened on days with 200mg+ caffeine (${percent(veryHighShare)} above 400mg). Median: $mg.",
                strength = highShare,
                whyItMatters = "Caffeine is a double-edged sword for headache sufferers: it can provide acute relief (it's in many rescue medications), but daily high intake can lead to medication-overuse headache and withdrawal cycles. The U-shaped risk curve means both too much and too little can trigger attacks.",
                yourPattern = "${percent(highShare)} of your headaches occurred on high-caffeine days (≥200mg), including ${percent(veryHighShare)} on very high days (≥400mg).",
                breakdown = Breakdown(b.buckets, null, "Daily caffeine consumption before headaches"),
            )
        }
    }

    private fun hydrationInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.waterMlToday }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val total = values.size.toDouble()
        val med = median(values)
        val coverage = coverageQualifier(values.size, events.size)
        val lowShare = values.count { it < 1000 } / total
        val veryLowShare = values.count { it < 500 } / total
        if (lowShare < 0.40) return null
        val b = binned(
            values,
            listOf(
                Bin("Very Low\n<500mL", 0.0, 500.0), Bin("Low\n500–1000mL", 500.0, 1000.0),
                Bin("Moderate\n1000–2000mL", 1000.0, 2000.0), Bin("Adequate\n2000mL+", 2000.0, 20000.0),
            ),
        )
        val ml = String.format(Locale.US, "%.0f mL", med)
        return Insight(
            id = "hydration",
            category = InsightCategory.WEATHER,
            icon = "drop.fill",
            title = "Low hydration pattern",
            detail = "${percent(lowShare)} of your headaches$coverage happened with under 1L of water that day (${percent(veryLowShare)} under 500mL). Median: $ml.",
            strength = lowShare,
            whyItMatters = "Even mild dehydration (1–2% body water loss) can trigger headaches and impair concentration, one of the most easily preventable triggers. The brain is highly sensitive to fluid balance; reduced blood volume can lower oxygen delivery and trigger pain pathways.",
            yourPattern = "${percent(lowShare)} of your headaches occurred on days with below 1,000 mL water intake, including ${percent(veryLowShare)} under 500 mL. Your median intake on headache days was $ml.",
            breakdown = Breakdown(b.buckets, null, "Daily water intake before headaches"),
        )
    }

    private fun exerciseInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.exerciseMinutesToday }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val coverage = coverageQualifier(values.size, events.size)
        val moderateShare = values.count { it >= 15 }.toDouble() / values.size
        if (moderateShare < 0.20) return null
        val b = binned(values, listOf(Bin("None", 0.0, 0.5), Bin("Light\n1–15m", 0.5, 15.0), Bin("Moderate\n15–45m", 15.0, 45.0), Bin("Active\n45m+", 45.0, 1000.0)))
        return Insight(
            id = "exercise-exertion",
            category = InsightCategory.HEART,
            icon = "figure.run",
            title = "Exertion-linked",
            detail = "${percent(moderateShare)} of your headaches$coverage followed 15+ minutes of exercise.",
            strength = moderateShare,
            whyItMatters = "Exercise-induced headaches can occur during or after strenuous activity, likely from venous pressure spikes and cranial vasodilation. The distinction from 'protective' exercise effects depends on individual conditioning and hydration status before activity.",
            yourPattern = "${percent(moderateShare)} of your headaches occurred on days with 15+ minutes of exercise.",
            breakdown = Breakdown(b.buckets, null, "Exercise minutes on headache days"),
        )
    }

    private fun pollenInsight(events: List<HeadacheEvent>): Insight? {
        val getters: List<(HeadacheEvent) -> Double?> = listOf(
            { it.grassPollen }, { it.birchPollen }, { it.alderPollen }, { it.mugwortPollen }, { it.olivePollen }, { it.ragweedPollen },
        )
        val names = listOf("Grass", "Birch", "Alder", "Mugwort", "Olive", "Ragweed")
        val thresholds = listOf(20.0, 30.0, 20.0, 10.0, 30.0, 10.0)
        var elevatedCount = 0
        val typeElevated = LinkedHashMap<String, Int>()
        var totalWithData = 0
        for (event in events) {
            var hasData = false
            var hasElevated = false
            getters.forEachIndexed { i, get ->
                val v = get(event) ?: return@forEachIndexed
                hasData = true
                if (v >= thresholds[i]) {
                    hasElevated = true
                    typeElevated[names[i]] = (typeElevated[names[i]] ?: 0) + 1
                }
            }
            if (hasData) {
                totalWithData++
                if (hasElevated) elevatedCount++
            }
        }
        if (totalWithData < MINIMUM_SAMPLE_SIZE) return null
        val elevatedShare = elevatedCount.toDouble() / totalWithData
        if (elevatedShare < 0.30) return null
        val coverage = coverageQualifier(totalWithData, events.size)
        val topType = typeElevated.entries.fold(null as Map.Entry<String, Int>?) { best, e -> if (best == null || e.value > best.value) e else best }
        val topTypePhrase = topType?.let { "${it.key} (${percent(it.value.toDouble() / elevatedCount)})" } ?: "various types"
        val title = if (typeElevated.size >= 3) "Multi-pollen elevation" else "Elevated ${topType?.key ?: "pollen"}"
        return Insight(
            id = "pollen",
            category = InsightCategory.WEATHER,
            icon = "leaf.fill",
            title = title,
            detail = "${percent(elevatedShare)} of your headaches$coverage occurred when at least one pollen type was elevated. Most common: $topTypePhrase.",
            strength = elevatedShare,
            whyItMatters = "Pollen triggers allergic rhinitis, which causes sinus congestion and inflammation, a known headache precipitant. The relationship may be seasonal: tree pollen in spring, grass in summer, ragweed in autumn. Indoor air filtration can help during high-pollen periods.",
            yourPattern = "${percent(elevatedShare)} of your headaches with pollen data occurred on days with elevated pollen levels, most commonly $topTypePhrase.",
            breakdown = Breakdown(
                listOf(
                    Bucket("No elevation", 1.0 - elevatedShare, totalWithData - elevatedCount, false),
                    Bucket("Elevated", elevatedShare, elevatedCount, true),
                ),
                null,
                "Pollen elevation at headache onset",
            ),
        )
    }

    private fun bloodPressureInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.bloodPressureSystolicMmHg }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val total = values.size.toDouble()
        val med = median(values)
        val coverage = coverageQualifier(values.size, events.size)
        val elevatedShare = values.count { it >= 130 } / total
        val highShare = values.count { it >= 140 } / total
        if (elevatedShare < 0.30) return null
        val b = binned(
            values,
            listOf(Bin("Normal\n<120", 0.0, 120.0), Bin("Elevated\n120–129", 120.0, 130.0), Bin("High\n130–140", 130.0, 140.0), Bin("Very High\n140+", 140.0, 500.0)),
        )
        return Insight(
            id = "blood-pressure",
            category = InsightCategory.HEART,
            icon = "heart.text.square.fill",
            title = "Elevated blood pressure",
            detail = "${percent(elevatedShare)} of your headaches$coverage showed systolic BP ≥130 (${percent(highShare)} ≥140). Median: ${String.format(Locale.US, "%.0f mmHg", med)}.",
            strength = elevatedShare,
            whyItMatters = "Hypertension is a known headache risk factor, particularly for morning headaches and posterior-head pain. The relationship may be bidirectional: pain elevates BP, and elevated BP can trigger headache. Sustained readings ≥130/80 warrant clinical evaluation.",
            yourPattern = "${percent(elevatedShare)} of your headaches with BP data occurred with elevated systolic readings (≥130), including ${percent(highShare)} at hypertensive levels (≥140).",
            breakdown = Breakdown(b.buckets, null, "Systolic BP at headache onset (mmHg)"),
        )
    }

    private fun oxygenSaturationInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.oxygenSaturationPercent }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val total = values.size
        val coverage = coverageQualifier(total, events.size)
        val low = values.count { it < 95 }
        val lowShare = low.toDouble() / total
        if (lowShare < 0.30) return null
        return Insight(
            id = "oxygen-saturation",
            category = InsightCategory.HEART,
            icon = "lungs.fill",
            title = "Lower oxygen saturation",
            detail = "${percent(lowShare)} of your headaches$coverage showed SpO₂ below 95%.",
            strength = lowShare * 0.8,
            whyItMatters = "Low blood oxygen can trigger headaches through cerebral vasodilation, as the brain increases blood flow to compensate for reduced oxygen delivery. Sustained readings below 92% are clinically significant and may warrant discussing sleep apnea screening with a doctor.",
            yourPattern = "${percent(lowShare)} of your headaches with oxygen data occurred with SpO₂ below 95%.",
            breakdown = Breakdown(
                listOf(Bucket("Normal\n95–100%", 1.0 - lowShare, total - low, false), Bucket("Low\n<95%", lowShare, low, true)),
                null,
                "Oxygen saturation at headache onset",
            ),
        )
    }

    private fun daylightInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.timeInDaylightMinutesToday }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val total = values.size.toDouble()
        val med = median(values)
        val coverage = coverageQualifier(values.size, events.size)
        val veryLowShare = values.count { it < 15 } / total
        val highShare = values.count { it >= 120 } / total
        if (veryLowShare < 0.35 && highShare < 0.30) return null
        val b = binned(
            values,
            listOf(Bin("Very Low\n<15m", 0.0, 15.0), Bin("Low\n15–60m", 15.0, 60.0), Bin("Moderate\n60–120m", 60.0, 120.0), Bin("High\n120m+", 120.0, 10000.0)),
        )
        return if (veryLowShare >= highShare) {
            Insight(
                id = "daylight-low",
                category = InsightCategory.WEATHER,
                icon = "moon.fill",
                title = "Low daylight exposure",
                detail = "${percent(veryLowShare)} of your headaches$coverage happened on days with under 15 minutes of daylight exposure.",
                strength = veryLowShare,
                whyItMatters = "Low daylight exposure may reflect more time indoors, which correlates with screen use, artificial lighting, reduced movement, and irregular sleep-wake cycles, all potential headache contributors. It can also disrupt circadian rhythm via reduced morning light.",
                yourPattern = "${percent(veryLowShare)} of your headaches occurred on days with under 15 minutes of daylight, median ${String.format(Locale.US, "%.0f min", med)}.",
                breakdown = Breakdown(b.buckets, null, "Daylight exposure on headache days"),
            )
        } else {
            Insight(
                id = "daylight-high",
                category = InsightCategory.WEATHER,
                icon = "sun.max.fill",
                title = "High daylight exposure",
                detail = "${percent(highShare)} of your headaches$coverage happened on days with 2+ hours of daylight exposure.",
                strength = highShare,
                whyItMatters = "Bright sunlight is a well-known migraine trigger, likely through the trigeminal-autonomic reflex and glare sensitivity. Photophobia is one of the diagnostic criteria for migraine; many sufferers are more sensitive to light between attacks, not just during them.",
                yourPattern = "${percent(highShare)} of your headaches occurred on days with 2+ hours of daylight exposure.",
                breakdown = Breakdown(b.buckets, null, "Daylight exposure on headache days"),
            )
        }
    }

    private fun audioExposureInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.environmentalAudioExposureDbA }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val coverage = coverageQualifier(values.size, events.size)
        val elevatedShare = values.count { it >= 70 }.toDouble() / values.size
        if (elevatedShare < 0.30) return null
        val b = binned(
            values,
            listOf(Bin("Quiet\n<55dBA", 0.0, 55.0), Bin("Moderate\n55–70dBA", 55.0, 70.0), Bin("Loud\n70–80dBA", 70.0, 80.0), Bin("Very Loud\n80dBA+", 80.0, 200.0)),
        )
        return Insight(
            id = "audio-exposure",
            category = InsightCategory.WEATHER,
            icon = "ear.fill",
            title = "Elevated noise environment",
            detail = "${percent(elevatedShare)} of your headaches$coverage happened in noisy environments (≥70 dBA).",
            strength = elevatedShare * 0.7,
            whyItMatters = "Sustained noise exposure is both a trigger (sensory overload) and a consequence (phonophobia during prodrome) of migraine. Levels above 70 dBA are comparable to busy street traffic, enough to raise stress hormones and muscle tension even if you're not consciously aware of it.",
            yourPattern = "${percent(elevatedShare)} of your headaches with audio data occurred in environments at or above 70 decibels.",
            breakdown = Breakdown(b.buckets, null, "Environmental audio level at headache onset"),
        )
    }

    private fun hoursSinceWakeInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.hoursSinceMainSleepWake }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val med = median(values)
        val coverage = coverageQualifier(values.size, events.size)
        val bins = listOf(Bin("0–2h", 0.0, 2.0), Bin("2–4h", 2.0, 4.0), Bin("4–8h", 4.0, 8.0), Bin("8–12h", 8.0, 12.0), Bin("12h+", 12.0, 48.0))
        val b = binned(values, bins)
        val baseline = 1.0 / bins.size
        val multiple = b.topShare / baseline
        if (multiple < 1.5) return null
        val early = b.topIndex <= 1
        return Insight(
            id = "hours-since-wake",
            category = InsightCategory.TIME,
            icon = if (early) "sunrise.fill" else "clock.fill",
            title = if (early) "Early post-wake cluster" else "Hours since waking",
            detail = "${percent(b.topShare)} of your headaches$coverage hit ${b.topLabel.lowercase()} after waking (median: ${formatHours(med)}).",
            strength = b.topShare,
            whyItMatters = "The time between waking and headache onset can help identify specific triggers: early-morning headaches may relate to sleep quality, caffeine withdrawal, or blood pressure morning surge; late-day headaches often track accumulated triggers: screen time, skipped meals, stress build-up, or eye strain.",
            yourPattern = "${percent(b.topShare)} of your headaches occur ${b.topLabel.lowercase()} after waking, ${fmt1(multiple)}x the even baseline. Median: ${formatHours(med)}.",
            breakdown = Breakdown(b.buckets, baseline, "Hours since waking at headache onset"),
        )
    }

    private fun menstrualCycleInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.daysSinceLastPeriodStart }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val total = values.size.toDouble()
        val coverage = coverageQualifier(values.size, events.size)
        val follicular = values.count { it in 0..13 }
        val luteal = values.count { it in 14..27 }
        val extended = values.count { it >= 28 }
        val follicularShare = follicular / total
        val lutealShare = luteal / total
        val extendedShare = extended / total
        if (lutealShare < 0.35 || lutealShare < follicularShare * 1.3) return null
        return Insight(
            id = "menstrual-cycle",
            category = InsightCategory.SEVERITY,
            icon = "facemask.fill",
            title = "Luteal phase link",
            detail = "${percent(lutealShare)} of logged headaches$coverage landed in the luteal phase (days 14–28).",
            strength = lutealShare - follicularShare,
            whyItMatters = "Menstrual migraine is a well-characterized subtype linked to the natural drop in estrogen during the late luteal phase. These headaches tend to be longer, more severe, and less responsive to standard rescue meds. Tracking across cycles can help time preventive treatment.",
            yourPattern = "${percent(lutealShare)} of your headaches with cycle data occurred in the luteal phase, compared to ${percent(follicularShare)} in the follicular phase.",
            breakdown = Breakdown(
                listOf(
                    Bucket("Follicular\nDays 0–13", follicularShare, follicular, false),
                    Bucket("Luteal\nDays 14–28", lutealShare, luteal, true),
                    Bucket("Extended\n28+ days", extendedShare, extended, false),
                ),
                null,
                "Cycle phase at headache onset",
            ),
        )
    }

    private fun motionActivityInsight(events: List<HeadacheEvent>): Insight? {
        val values = events.mapNotNull { it.motionActivity }
        if (values.size < MINIMUM_SAMPLE_SIZE) return null
        val total = values.size
        val coverage = coverageQualifier(total, events.size)
        val order = MotionActivity.entries
        val counts = values.groupingBy { it }.eachCount()
        val (top, topCount) = topOf(counts, order) ?: return null
        // People sit to log; only a non-stationary activity is a pattern.
        if (topCount <= 0 || top == MotionActivity.STATIONARY || top == MotionActivity.UNKNOWN) return null
        val topShare = topCount.toDouble() / total
        if (topShare < 0.50) return null
        val buckets = order.map { act ->
            val c = counts[act] ?: 0
            Bucket(label(act), c.toDouble() / total, c, act == top)
        }
        return Insight(
            id = "motion-activity",
            category = InsightCategory.TIME,
            icon = "figure.walk",
            title = "Active when headaches hit",
            detail = "${percent(topShare)} of your headaches$coverage were logged while ${label(top).lowercase()}.",
            strength = topShare,
            whyItMatters = "Some people experience exertion-triggered headaches from increased cranial pressure during activity. If this pattern is strong, consider whether onset consistently follows specific movements or postures.",
            yourPattern = "${percent(topShare)} of your headaches were logged while ${label(top).lowercase()}.",
            breakdown = Breakdown(buckets, null, "Activity at headache onset"),
        )
    }

    private fun multivariateInsight(events: List<HeadacheEvent>): Insight? {
        if (events.size < MINIMUM_SAMPLE_SIZE * 2) return null
        data class Condition(val id: String, val label: String, val test: (HeadacheEvent) -> Boolean)
        val conditions = listOf(
            Condition("low-sleep", "Less than 6h sleep") { (it.sleepHoursLastNight ?: 8.0) < 6 },
            Condition("falling-pressure", "Falling pressure") { it.pressureTrend == PressureTrend.FALLING },
            Condition("high-aqi", "US AQI ≥ 75") { (it.usAQI ?: 0.0) >= 75 },
            Condition("high-humidity", "Humidity ≥ 70%") { (it.humidityPercent ?: 0.0) >= 70 },
            Condition("high-caffeine", "Caffeine ≥ 200 mg") { (it.caffeineMgToday ?: 0.0) >= 200 },
            Condition("low-water", "Water < 1 L") { (it.waterMlToday ?: 2000.0) < 1000 },
            Condition("no-exercise", "Zero exercise") { (it.exerciseMinutesToday ?: 1.0) == 0.0 },
        )
        val total = events.size
        val pairs = mutableListOf<Triple<Condition, Condition, Int>>()
        for (i in conditions.indices) {
            for (j in i + 1 until conditions.size) {
                val c1 = conditions[i]
                val c2 = conditions[j]
                val co = events.count { c1.test(it) && c2.test(it) }
                if (co < min(3, total / 10)) continue
                pairs += Triple(c1, c2, co)
            }
        }
        if (pairs.isEmpty()) return null
        // Swift `max(by:)` keeps the last of equal maxima.
        val (cond1, cond2, coCount) = pairs.reduce { best, p -> if (p.third >= best.third) p else best }
        val coShare = coCount.toDouble() / total
        if (coShare < 0.15) return null
        val c1Count = events.count(cond1.test)
        val c2Count = events.count(cond2.test)
        val expected = (c1Count.toDouble() / total) * (c2Count.toDouble() / total)
        val lift = if (expected > 0) coShare / expected else 0.0
        if (lift < 1.5) return null
        return Insight(
            id = "multivariate-${cond1.id}-${cond2.id}",
            category = InsightCategory.SEVERITY,
            icon = "link.circle.fill",
            title = "Trigger combination: ${cond1.label} & ${cond2.label.lowercase()}",
            detail = "${percent(coShare)} of your headaches hit when both occurred together, ${fmt1(lift)}x more often than if they were independent.",
            strength = min(1.0, coShare * (1.0 + lift / 3.0)),
            whyItMatters = "Migraine triggers rarely act in isolation; most attacks result from a cumulative threshold being crossed ('bucket theory'). Identifying the specific combinations that precede your worst headache days is more actionable than looking at single factors alone, because it points to which protective measures matter most on a given day.",
            yourPattern = "${percent(coShare)} of your headaches occurred when ${cond1.label.lowercase()} and ${cond2.label.lowercase()} coincided, ${fmt1(lift)}x the rate expected by chance (${percent(expected)}).",
            breakdown = Breakdown(
                listOf(
                    Bucket("Neither", 1.0 - (c1Count + c2Count - coCount).toDouble() / total, total - c1Count - c2Count + coCount, false),
                    Bucket(cond1.label.split(" ").first(), (c1Count - coCount).toDouble() / total, c1Count - coCount, false),
                    Bucket(cond2.label.split(" ").first(), (c2Count - coCount).toDouble() / total, c2Count - coCount, false),
                    Bucket("Both", coShare, coCount, true),
                ),
                null,
                "Co-occurrence pattern",
            ),
        )
    }

    // Headache-free days (protective patterns)

    private class ProtectiveCandidate(
        val category: InsightCategory,
        val icon: String,
        val conditionLabel: String,
        val conditionRate: Double,
        val overallRate: Double,
        val conditionDays: Int,
        val conditionHeadacheDays: Int,
        val buckets: List<Bucket>,
        val axisCaption: String,
    ) {
        val gap: Double get() = overallRate - conditionRate
    }

    private const val PROTECTIVE_MIN_TOTAL_DAYS = 10
    private const val PROTECTIVE_RATE_CEILING = 0.6
    private const val PROTECTIVE_MIN_GAP = 0.15

    private fun headacheFreeDayInsight(records: List<DailyRecord>): Insight? {
        if (records.isEmpty()) return null
        val candidates = listOfNotNull(protectiveSleep(records), protectivePressure(records), protectiveAir(records))
        val best = candidates.reduceOrNull { a, b -> if (b.gap >= a.gap) b else a } ?: return null
        val freePct = percent(1 - best.conditionRate)
        val conditionPct = percent(best.conditionRate)
        val overallPct = percent(best.overallRate)
        return Insight(
            id = "headache-free-days",
            category = best.category,
            icon = best.icon,
            title = "Your headache-free days",
            detail = "You stay headache-free on $freePct of days with ${best.conditionLabel}, the best of any condition tracked. Overall you log a headache on $overallPct of days.",
            strength = min(0.85, 0.4 + best.gap),
            whyItMatters = "Knowing what your clear days have in common is as useful as knowing your triggers. It points to the habits and conditions worth protecting on a high-risk day. This is the flip side of your trigger patterns, not medical advice.",
            yourPattern = "On the ${best.conditionDays} days with ${best.conditionLabel}, you logged a headache ${best.conditionHeadacheDays} time${if (best.conditionHeadacheDays == 1) "" else "s"} ($conditionPct), well below your overall rate of $overallPct. The chart shows how headache-free each band tends to be.",
            breakdown = Breakdown(best.buckets, null, best.axisCaption),
        )
    }

    private fun protectiveSleep(records: List<DailyRecord>): ProtectiveCandidate? {
        val counts = DailyRecords.sleepConditionCounts(records).filter { it.totalDays > 0 }
        val totalDays = counts.sumOf { it.totalDays }
        val headacheDays = counts.sumOf { it.headacheDays }
        if (totalDays < PROTECTIVE_MIN_TOTAL_DAYS || headacheDays < 3 || totalDays - headacheDays < 3) return null
        val overall = headacheDays.toDouble() / totalDays
        val best = counts.filter { it.totalDays >= 4 }.minByOrNull { it.headacheRate } ?: return null
        if (best.headacheRate > overall * PROTECTIVE_RATE_CEILING || overall - best.headacheRate < PROTECTIVE_MIN_GAP) return null
        val buckets = counts.map { Bucket(it.label, max(0.0, 1 - it.headacheRate), it.totalDays - it.headacheDays, it.label == best.label) }
        return ProtectiveCandidate(
            InsightCategory.SLEEP, "bed.double.fill", "${best.label} of sleep", best.headacheRate, overall,
            best.totalDays, best.headacheDays, buckets, "Share of days that stayed headache-free, by sleep duration",
        )
    }

    private fun protectivePressure(records: List<DailyRecord>): ProtectiveCandidate? {
        val known = records.filter { it.weatherFetched && it.pressureTrend != PressureTrend.UNAVAILABLE }
        if (known.size < PROTECTIVE_MIN_TOTAL_DAYS) return null
        val headacheDays = known.count { it.hadHeadache }
        if (headacheDays < 3 || known.size - headacheDays < 3) return null
        val overall = headacheDays.toDouble() / known.size
        val order = listOf("Falling" to PressureTrend.FALLING, "Steady" to PressureTrend.STEADY, "Rising" to PressureTrend.RISING)
        val bins = order.map { (label, trend) ->
            val inBin = known.filter { it.pressureTrend == trend }
            Triple(label, inBin.size, inBin.count { it.hadHeadache })
        }
        fun rate(headache: Int, total: Int) = if (total > 0) headache.toDouble() / total else 1.0
        val best = bins.filter { it.second >= 4 }.minByOrNull { rate(it.third, it.second) } ?: return null
        val bestRate = rate(best.third, best.second)
        if (bestRate > overall * PROTECTIVE_RATE_CEILING || overall - bestRate < PROTECTIVE_MIN_GAP) return null
        val buckets = bins.map { (label, total, headache) ->
            Bucket(label, if (total > 0) max(0.0, 1 - headache.toDouble() / total) else 0.0, total - headache, label == best.first)
        }
        return ProtectiveCandidate(
            InsightCategory.PRESSURE, "barometer", "${best.first.lowercase()} pressure", bestRate, overall,
            best.second, best.third, buckets, "Share of days that stayed headache-free, by pressure trend",
        )
    }

    private fun protectiveAir(records: List<DailyRecord>): ProtectiveCandidate? {
        val withAQI = records.filter { it.weatherFetched && it.usAQI != null }
        if (withAQI.size < PROTECTIVE_MIN_TOTAL_DAYS) return null
        val headacheDays = withAQI.count { it.hadHeadache }
        if (headacheDays < 3 || withAQI.size - headacheDays < 3) return null
        val overall = headacheDays.toDouble() / withAQI.size
        val good = withAQI.filter { !it.isElevatedAQI }
        val elevated = withAQI.filter { it.isElevatedAQI }
        if (good.size < 4) return null
        val goodHeadache = good.count { it.hadHeadache }
        val goodRate = goodHeadache.toDouble() / good.size
        if (goodRate > overall * PROTECTIVE_RATE_CEILING || overall - goodRate < PROTECTIVE_MIN_GAP) return null
        val elevatedHeadache = elevated.count { it.hadHeadache }
        val buckets = listOf(
            Bucket("Clean\n<75", max(0.0, 1 - goodRate), good.size - goodHeadache, true),
            Bucket(
                "Elevated\n75+",
                if (elevated.isEmpty()) 0.0 else max(0.0, 1 - elevatedHeadache.toDouble() / elevated.size),
                elevated.size - elevatedHeadache,
                false,
            ),
        )
        return ProtectiveCandidate(
            InsightCategory.AIR_QUALITY, "aqi.low", "clean air (US AQI under 75)", goodRate, overall,
            good.size, goodHeadache, buckets, "Share of days that stayed headache-free, by air quality",
        )
    }

    // Helpers

    fun median(values: List<Double>): Double {
        val sorted = values.sorted()
        if (sorted.isEmpty()) return 0.0
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2 else sorted[mid]
    }

    /** Swift rounds half away from zero. */
    fun percent(value: Double): String = "${Math.round(value * 100)}%"

    private fun fmt1(value: Double): String = String.format(Locale.US, "%.1f", value)

    private fun coverageQualifier(subset: Int, total: Int): String =
        if (subset in 1 until total) " (of the $subset with available data)" else ""

    fun formatHours(hours: Double): String {
        val total = max(0.0, hours)
        val h = total.toInt()
        val m = ((total - h) * 60).toInt()
        return if (m == 0) "${h}h" else "${h}h ${m}m"
    }

    private fun othersSummary(buckets: List<Bucket>, peakLabel: String, label: (Bucket) -> String): String =
        "Others: " + buckets.filter { it.label != peakLabel }.joinToString(", ") { "${label(it)} ${Math.round(it.share * 100)}%" } + "."

    fun label(part: PartOfDay): String = part.title

    private fun icon(part: PartOfDay): String = when (part) {
        PartOfDay.OVERNIGHT -> "moon.stars.fill"
        PartOfDay.MORNING -> "sunrise.fill"
        PartOfDay.AFTERNOON -> "sun.max.fill"
        PartOfDay.EVENING -> "sunset.fill"
    }

    private fun label(trend: PressureTrend): String = when (trend) {
        PressureTrend.FALLING -> "Falling"
        PressureTrend.RISING -> "Rising"
        PressureTrend.STEADY -> "Steady"
        PressureTrend.UNAVAILABLE -> "Unknown"
    }

    private fun label(activity: MotionActivity): String = when (activity) {
        MotionActivity.STATIONARY -> "Stationary"
        MotionActivity.WALKING -> "Walking"
        MotionActivity.RUNNING -> "Running"
        MotionActivity.AUTOMOTIVE -> "In a vehicle"
        MotionActivity.CYCLING -> "Cycling"
        MotionActivity.UNKNOWN -> "Unknown"
    }

    /** Swift weekday index (1 is Sunday) to a localized symbol. */
    fun weekdaySymbol(index: Int, style: TextStyle, locale: Locale = Locale.getDefault()): String {
        if (index !in 1..7) return if (style == TextStyle.FULL) "a weekday" else "?"
        val day = if (index == 1) DayOfWeek.SUNDAY else DayOfWeek.of(index - 1)
        return day.getDisplayName(style, locale)
    }
}

// Calendar heatmap

data class HeatmapDay(val date: LocalDate, val count: Int, val peakSeverity: HeadacheSeverity?)

object HeatmapData {
    /** Starts at the first logged headache so the grid never implies data the app doesn't have. */
    fun build(events: List<HeadacheEvent>, days: Int = 90, endingAt: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<HeatmapDay> {
        val today = endingAt.atZone(zone).toLocalDate()
        val windowStart = today.minusDays((days - 1).toLong())
        val firstEvent = events.minOfOrNull { it.timestamp } ?: return emptyList()
        val firstDay = firstEvent.atZone(zone).toLocalDate()
        val start = maxOf(windowStart, minOf(firstDay, today))
        val byDay = HashMap<LocalDate, Pair<Int, HeadacheSeverity?>>()
        for (event in events) {
            val day = event.timestamp.atZone(zone).toLocalDate()
            if (day.isBefore(start) || day.isAfter(today)) continue
            val (count, peak) = byDay[day] ?: (0 to null)
            byDay[day] = (count + 1) to (event.severity?.let { peak(peak, it) } ?: peak)
        }
        val out = mutableListOf<HeatmapDay>()
        var cursor = start
        while (!cursor.isAfter(today)) {
            val entry = byDay[cursor]
            out += HeatmapDay(cursor, entry?.first ?: 0, entry?.second)
            cursor = cursor.plusDays(1)
        }
        return out
    }

    val HeadacheSeverity.rank: Int get() = ordinal + 1

    fun peak(a: HeadacheSeverity?, b: HeadacheSeverity): HeadacheSeverity = if (a == null) b else if (a.rank >= b.rank) a else b
}
