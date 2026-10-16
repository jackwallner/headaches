package com.jackwallner.headachelogger.model

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

enum class ImportStrategy { SKIP_EXISTING, OVERWRITE_EXISTING }

data class ImportResult(val imported: Int, val skipped: Int, val overwritten: Int, val errors: Int)

class ImportException(message: String) : Exception(message) {
    companion object {
        val emptyFile = ImportException("The file is empty or contains no valid data rows.")
        val invalidHeader = ImportException("The file doesn't appear to be a valid headache event export.")
    }
}

/**
 * Port of `ExportService.exportCSV` and `ImportService`: the same columns in the
 * same order, the same `#` preamble, quoting, formula guard and number format,
 * so a file exported on iPhone imports on Android and back.
 */
object EventCsv {
    private val timestampFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSXXX").withZone(ZoneOffset.UTC)

    private class Column(val name: String, val value: (HeadacheEvent) -> String?)

    /** Storage keeps every digit; the CSV rounds to two places like iOS. */
    @Volatile private var fullPrecision = false

    private fun num(value: Double?): String? = value?.let { if (fullPrecision) it.toString() else decimal(it) }
    private fun bool(value: Boolean?): String? = value?.let { if (it) "true" else "false" }

    private val columns: List<Column> = listOf(
        Column("event_id") { it.id.toString().uppercase() },
        Column("timestamp") { formatTimestamp(it.timestamp) },
        Column("timezone") { it.timezoneIdentifier },
        Column("weekday") { it.weekdayName },
        Column("weekday_index") { it.weekdayIndex.toString() },
        Column("hour") { it.hourOfDay.toString() },
        Column("minute") { it.minuteOfHour.toString() },
        Column("part_of_day") { it.partOfDay.raw },
        Column("capture_status") { it.captureStatus.raw },
        Column("health_status") { it.healthStatus.raw },
        Column("environment_status") { it.environmentStatus.raw },
        Column("location") { it.locationLabel },
        Column("locality") { it.locality },
        Column("region") { it.region },
        Column("altitude_m") { num(it.altitudeM) },
        Column("weather_summary") { it.weatherSummary },
        Column("weather_code") { it.weatherCode?.toString() },
        Column("temperature_c") { num(it.temperatureC) },
        Column("feels_like_c") { num(it.apparentTemperatureC) },
        Column("temperature_f") { num(it.temperatureC?.let(Temperature::celsiusToFahrenheit)) },
        Column("feels_like_f") { num(it.apparentTemperatureC?.let(Temperature::celsiusToFahrenheit)) },
        Column("humidity_percent") { num(it.humidityPercent) },
        Column("pressure_hpa") { num(it.pressureHpa) },
        Column("pressure_trend") { it.pressureTrend.raw },
        Column("precipitation_mm") { num(it.precipitationMm) },
        Column("wind_speed_kph") { num(it.windSpeedKph) },
        Column("wind_direction_deg") { num(it.windDirectionDegrees) },
        Column("cloud_cover_percent") { num(it.cloudCoverPercent) },
        Column("uv_index") { num(it.uvIndex) },
        Column("dew_point_c") { num(it.dewPointC) },
        Column("us_aqi") { num(it.usAQI) },
        Column("european_aqi") { num(it.europeanAQI) },
        Column("pm2_5") { num(it.pm25) },
        Column("pm10") { num(it.pm10) },
        Column("ozone") { num(it.ozone) },
        Column("nitrogen_dioxide") { num(it.nitrogenDioxide) },
        Column("sulphur_dioxide") { num(it.sulphurDioxide) },
        Column("carbon_monoxide") { num(it.carbonMonoxide) },
        Column("alder_pollen") { num(it.alderPollen) },
        Column("birch_pollen") { num(it.birchPollen) },
        Column("grass_pollen") { num(it.grassPollen) },
        Column("mugwort_pollen") { num(it.mugwortPollen) },
        Column("olive_pollen") { num(it.olivePollen) },
        Column("ragweed_pollen") { num(it.ragweedPollen) },
        Column("steps_today") { it.stepsToday?.toString() },
        Column("active_energy_kcal_today") { num(it.activeEnergyKcalToday) },
        Column("distance_walking_running_km_today") { num(it.distanceWalkingRunningKmToday) },
        Column("exercise_minutes_today") { num(it.exerciseMinutesToday) },
        Column("sleep_hours_last_night") { num(it.sleepHoursLastNight) },
        Column("last_main_sleep_wake_utc") { it.lastMainSleepWakeTime?.let(::formatTimestamp) },
        Column("hours_since_main_sleep_wake") { num(it.hoursSinceMainSleepWake) },
        Column("resting_heart_rate_bpm") { num(it.restingHeartRateBpm) },
        Column("recent_heart_rate_avg_bpm") { num(it.recentHeartRateAverageBpm) },
        Column("hrv_sdnn_ms") { num(it.hrvSDNNMs) },
        Column("respiratory_rate_brpm") { num(it.respiratoryRateBrpm) },
        Column("workouts_last_24h") { it.workoutsLast24h?.toString() },
        Column("workout_minutes_last_24h") { num(it.workoutMinutesLast24h) },
        Column("environmental_audio_db_a") { num(it.environmentalAudioExposureDbA) },
        Column("oxygen_saturation_percent") { num(it.oxygenSaturationPercent) },
        Column("vo2_max_ml_kg_min") { num(it.vo2MaxMlPerKgPerMin) },
        Column("walking_speed_m_s") { num(it.walkingSpeedMetersPerSecond) },
        Column("apple_stand_minutes_today") { num(it.appleStandMinutesToday) },
        Column("basal_energy_kcal_today") { num(it.basalEnergyKcalToday) },
        Column("flights_climbed_today") { num(it.flightsClimbedToday) },
        Column("mindful_minutes_today") { num(it.mindfulMinutesToday) },
        Column("barometric_pressure_delta_hpa_6h") { num(it.barometricPressureDeltaHpa6h) },
        Column("caffeine_mg_today") { num(it.caffeineMgToday) },
        Column("water_ml_today") { num(it.waterMlToday) },
        Column("days_since_last_period_start") { it.daysSinceLastPeriodStart?.toString() },
        Column("blood_pressure_systolic_mmhg") { num(it.bloodPressureSystolicMmHg) },
        Column("blood_pressure_diastolic_mmhg") { num(it.bloodPressureDiastolicMmHg) },
        Column("blood_glucose_mg_dl") { num(it.bloodGlucoseMgPerDL) },
        Column("headphone_audio_db_a") { num(it.headphoneAudioExposureDbA) },
        Column("time_in_daylight_minutes_today") { num(it.timeInDaylightMinutesToday) },
        Column("battery_level_percent") { num(it.batteryLevelPercent) },
        Column("is_charging") { bool(it.isCharging) },
        Column("is_low_power_mode") { bool(it.isLowPowerMode) },
        Column("motion_activity") { it.motionActivity?.raw },
        Column("health_message") { it.healthStatusMessage },
        Column("environment_message") { it.environmentStatusMessage },
        Column("severity") { it.severity?.raw },
        Column("user_notes") { it.userNotes },
    )

    val header: List<String> get() = columns.map { it.name }

    fun fileName(now: Instant = Instant.now()): String = "headache-events-${now.epochSecond}.csv"

    fun export(events: List<HeadacheEvent>, now: Instant = Instant.now()): String {
        val generatedAt = DateTimeFormatter.ISO_INSTANT.format(now.truncatedTo(java.time.temporal.ChronoUnit.SECONDS))
        val rows = synchronized(this) { events.map { event -> columns.joinToString(",") { cell(it.value(event)) } } }
        // CRLF row separator per RFC 4180, like iOS.
        return (preamble(events.size, generatedAt) + header.joinToString(",") + rows).joinToString("\r\n")
    }

    /** `#` lines so spreadsheet tools and simple parsers treat them as comments. */
    private fun preamble(count: Int, generatedAt: String): List<String> = listOf(
        "# One Tap Headache Tracker: exported headache event log",
        "# What this file is: one row per time you tapped Headache in the app; each row is a timestamped snapshot of optional context (not a diagnosis).",
        "# Time: timestamp (UTC ISO8601 with fractional seconds), timezone ID, weekday name, hour/minute, part_of_day (overnight/morning/afternoon/evening).",
        "# Health (Health Connect when permitted on Android, Apple Health on iPhone): sleep (hours in window, inferred main-sleep wake time, hours since wake). Columns for other Apple Health signals stay empty on Android.",
        "# Environment (when location/weather services work): human-readable location plus separate locality/region and altitude, weather summary and code, temperature (°C and °F columns), humidity, pressure and trend, precipitation, wind, cloud cover, UV, dew point, air quality indices and pollutants, pollen-style counts when exposed by the data provider.",
        "# Device (captured on-device at tap time): battery level percent, charging flag, low-power-mode flag, motion activity (stationary/walking/running/automotive/cycling/unknown).",
        "# Status columns: capture_status plus health_status / environment_status reflect whether those bundles were captured; health_message and environment_message explain gaps or errors when present.",
        "# severity: optional rating (slight/medium/extreme) captured at tap time when the prompt is enabled.",
        "# user_notes: optional text you can add at tap time or later in History.",
        "# Empty quoted cells mean the value was unavailable or not recorded for that event.",
        "# This export is for personal tracking and sharing with a clinician or researcher; it does not establish medical facts by itself.",
        "#",
        "# export_generated_at_utc: $generatedAt",
        "# row_count: $count",
        "#",
    )

    private fun cell(value: String?): String {
        val escaped = (value ?: "").replace("\"", "\"\"")
        val first = escaped.firstOrNull()
        val needsGuard = first != null && first in "=+-@" && escaped.toDoubleOrNull() == null
        return "\"${if (needsGuard) "'$escaped" else escaped}\""
    }

    /** At most two fraction digits, no grouping, POSIX dot (`NumberFormatter` en_US_POSIX on iOS). */
    fun decimal(value: Double): String {
        if (value.isNaN() || value.isInfinite()) return value.toString()
        val text = BigDecimal.valueOf(value).setScale(2, RoundingMode.HALF_EVEN).stripTrailingZeros().toPlainString()
        return if (text == "-0") "0" else text
    }

    fun formatTimestamp(instant: Instant): String = timestampFormatter.format(instant)

    fun parseTimestamp(text: String?): Instant? {
        if (text.isNullOrEmpty()) return null
        return runCatching { Instant.parse(text) }.getOrNull()
            ?: runCatching { java.time.OffsetDateTime.parse(text).toInstant() }.getOrNull()
    }

    // Import

    /** Rows keyed by header; rows with the wrong field count are dropped, like iOS. */
    fun parse(contents: String): List<Map<String, String>> {
        val lines = splitLines(contents)
        val headerLine = lines.firstOrNull() ?: throw ImportException.emptyFile
        val head = parseRow(headerLine)
        if (head.isEmpty()) throw ImportException.invalidHeader
        return lines.drop(1).mapNotNull { line ->
            val fields = parseRow(line)
            if (fields.size == head.size) head.zip(fields).toMap() else null
        }
    }

    private fun splitLines(contents: String): List<String> {
        val normalized = contents.replace("\r\n", "\n")
        val lines = mutableListOf<String>()
        val current = StringBuilder()
        var inQuotes = false
        fun flush() {
            val trimmed = current.toString().trim('\n', '\r')
            if (trimmed.isNotEmpty() && !trimmed.startsWith("#")) lines += trimmed
            current.clear()
        }
        for (char in normalized) {
            when {
                char == '"' -> { inQuotes = !inQuotes; current.append(char) }
                char == '\n' && !inQuotes -> flush()
                else -> current.append(char)
            }
        }
        flush()
        return lines
    }

    private fun parseRow(line: String): List<String> {
        val fields = mutableListOf<String>()
        val current = StringBuilder()
        var inQuotes = false
        for (char in line) {
            when {
                char == '"' -> inQuotes = !inQuotes
                char == ',' && !inQuotes -> {
                    fields += current.toString().replace("\"\"", "\"").trim(' ', '\t')
                    current.clear()
                }
                else -> current.append(char)
            }
        }
        fields += current.toString().replace("\"\"", "\"").trim(' ', '\t')
        return fields
    }

    /** Storage row: every CSV column plus the two timestamps the CSV leaves out. Null cells are omitted. */
    fun storageRow(event: HeadacheEvent): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        synchronized(this) {
            fullPrecision = true
            try {
                for (c in columns) c.value(event)?.let { out[c.name] = it }
            } finally {
                fullPrecision = false
            }
        }
        out["created_at"] = formatTimestamp(event.createdAt)
        event.captureCompletedAt?.let { out["capture_completed_at"] = formatTimestamp(it) }
        return out
    }

    /** Rebuilds one stored event; null when the id or timestamp is unreadable. */
    fun fromStorageRow(row: Map<String, String>, zone: ZoneId = ZoneId.systemDefault()): HeadacheEvent? {
        val id = row["event_id"]?.let { runCatching { UUID.fromString(it) }.getOrNull() } ?: return null
        val timestamp = parseTimestamp(row["timestamp"]) ?: return null
        val event = HeadacheEvent(timestamp, zone).also { it.id = id }
        applyRow(row, event, zone)
        parseTimestamp(row["created_at"])?.let { event.createdAt = it }
        event.captureCompletedAt = parseTimestamp(row["capture_completed_at"])
        return event
    }

    /** Merges rows into `events` in place and reports what happened. */
    fun importInto(
        events: MutableList<HeadacheEvent>,
        rows: List<Map<String, String>>,
        strategy: ImportStrategy,
        zone: ZoneId = ZoneId.systemDefault(),
    ): ImportResult {
        var imported = 0
        var skipped = 0
        var overwritten = 0
        var errors = 0
        for (row in rows) {
            val id = row["event_id"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
            if (id == null) {
                errors++
                continue
            }
            val existing = events.firstOrNull { it.id == id }
            if (existing != null) {
                if (strategy == ImportStrategy.SKIP_EXISTING) {
                    skipped++
                } else {
                    applyRow(row, existing, zone)
                    overwritten++
                }
                continue
            }
            val timestamp = parseTimestamp(row["timestamp"])
            if (timestamp == null) {
                errors++
                continue
            }
            val event = HeadacheEvent(timestamp, zone).also { it.id = id }
            applyRow(row, event, zone)
            events += event
            imported++
        }
        return ImportResult(imported, skipped, overwritten, errors)
    }

    private fun applyRow(row: Map<String, String>, event: HeadacheEvent, zone: ZoneId) {
        parseTimestamp(row["timestamp"])?.let { event.timestamp = it }
        val local = event.timestamp.atZone(zone)
        event.timezoneIdentifier = row["timezone"] ?: zone.id
        event.weekdayIndex = row["weekday_index"]?.toIntOrNull() ?: HeadacheEvent.weekdayIndexOf(local)
        event.weekdayName = row["weekday"] ?: ""
        event.hourOfDay = row["hour"]?.toIntOrNull() ?: local.hour
        event.minuteOfHour = row["minute"]?.toIntOrNull() ?: local.minute
        event.partOfDayRaw = row["part_of_day"] ?: PartOfDay.fromHour(local.hour).raw

        event.captureStatusRaw = row["capture_status"] ?: CaptureStatus.COMPLETE.raw
        event.healthStatusRaw = row["health_status"] ?: CaptureSourceStatus.CAPTURED.raw
        event.environmentStatusRaw = row["environment_status"] ?: CaptureSourceStatus.CAPTURED.raw
        event.healthStatusMessage = text(row["health_message"])
        event.environmentStatusMessage = text(row["environment_message"])

        // Prefer locality/region; older exports only had the combined `location` column.
        event.locality = text(row["locality"]) ?: text(row["location"])
        event.region = text(row["region"])
        event.altitudeM = double(row["altitude_m"])
        event.weatherSummary = text(row["weather_summary"])
        event.weatherCode = row["weather_code"]?.toIntOrNull()
        event.temperatureC = double(row["temperature_c"])
        event.apparentTemperatureC = double(row["feels_like_c"])
        event.humidityPercent = double(row["humidity_percent"])
        event.pressureHpa = double(row["pressure_hpa"])
        event.pressureTrendRaw = row["pressure_trend"] ?: PressureTrend.UNAVAILABLE.raw
        event.precipitationMm = double(row["precipitation_mm"])
        event.windSpeedKph = double(row["wind_speed_kph"])
        event.windDirectionDegrees = double(row["wind_direction_deg"])
        event.cloudCoverPercent = double(row["cloud_cover_percent"])
        event.uvIndex = double(row["uv_index"])
        event.dewPointC = double(row["dew_point_c"])
        event.usAQI = double(row["us_aqi"])
        event.europeanAQI = double(row["european_aqi"])
        event.pm25 = double(row["pm2_5"])
        event.pm10 = double(row["pm10"])
        event.ozone = double(row["ozone"])
        event.nitrogenDioxide = double(row["nitrogen_dioxide"])
        event.sulphurDioxide = double(row["sulphur_dioxide"])
        event.carbonMonoxide = double(row["carbon_monoxide"])
        event.alderPollen = double(row["alder_pollen"])
        event.birchPollen = double(row["birch_pollen"])
        event.grassPollen = double(row["grass_pollen"])
        event.mugwortPollen = double(row["mugwort_pollen"])
        event.olivePollen = double(row["olive_pollen"])
        event.ragweedPollen = double(row["ragweed_pollen"])

        event.stepsToday = row["steps_today"]?.toIntOrNull()
        event.activeEnergyKcalToday = double(row["active_energy_kcal_today"])
        event.distanceWalkingRunningKmToday = double(row["distance_walking_running_km_today"])
        event.exerciseMinutesToday = double(row["exercise_minutes_today"])
        event.sleepHoursLastNight = double(row["sleep_hours_last_night"])
        event.lastMainSleepWakeTime = parseTimestamp(row["last_main_sleep_wake_utc"])
        event.hoursSinceMainSleepWake = double(row["hours_since_main_sleep_wake"])
        event.restingHeartRateBpm = double(row["resting_heart_rate_bpm"])
        event.recentHeartRateAverageBpm = double(row["recent_heart_rate_avg_bpm"])
        event.hrvSDNNMs = double(row["hrv_sdnn_ms"])
        event.respiratoryRateBrpm = double(row["respiratory_rate_brpm"])
        event.workoutsLast24h = row["workouts_last_24h"]?.toIntOrNull()
        event.workoutMinutesLast24h = double(row["workout_minutes_last_24h"])
        event.environmentalAudioExposureDbA = double(row["environmental_audio_db_a"])
        event.oxygenSaturationPercent = double(row["oxygen_saturation_percent"])
        event.vo2MaxMlPerKgPerMin = double(row["vo2_max_ml_kg_min"])
        event.walkingSpeedMetersPerSecond = double(row["walking_speed_m_s"])
        event.appleStandMinutesToday = double(row["apple_stand_minutes_today"])
        event.basalEnergyKcalToday = double(row["basal_energy_kcal_today"])
        event.flightsClimbedToday = double(row["flights_climbed_today"])
        event.mindfulMinutesToday = double(row["mindful_minutes_today"])
        event.barometricPressureDeltaHpa6h = double(row["barometric_pressure_delta_hpa_6h"])
        event.caffeineMgToday = double(row["caffeine_mg_today"])
        event.waterMlToday = double(row["water_ml_today"])
        event.daysSinceLastPeriodStart = row["days_since_last_period_start"]?.toIntOrNull()
        event.bloodPressureSystolicMmHg = double(row["blood_pressure_systolic_mmhg"])
        event.bloodPressureDiastolicMmHg = double(row["blood_pressure_diastolic_mmhg"])
        event.bloodGlucoseMgPerDL = double(row["blood_glucose_mg_dl"])
        event.headphoneAudioExposureDbA = double(row["headphone_audio_db_a"])
        event.timeInDaylightMinutesToday = double(row["time_in_daylight_minutes_today"])
        event.batteryLevelPercent = double(row["battery_level_percent"])
        event.isCharging = boolean(row["is_charging"])
        event.isLowPowerMode = boolean(row["is_low_power_mode"])
        event.motionActivityRaw = text(row["motion_activity"])

        event.severityRaw = text(row["severity"])
        event.userNotes = text(row["user_notes"])
        event.captureCompletedAt = event.captureCompletedAt ?: event.timestamp
    }

    private fun text(value: String?): String? = value?.takeIf { it.isNotEmpty() }
    private fun double(value: String?): Double? = value?.takeIf { it.isNotEmpty() }?.toDoubleOrNull()

    private fun boolean(value: String?): Boolean? = when (value?.lowercase()) {
        "true", "1", "yes" -> true
        "false", "0", "no" -> false
        else -> null
    }
}
