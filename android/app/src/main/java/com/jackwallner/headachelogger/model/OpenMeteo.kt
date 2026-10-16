package com.jackwallner.headachelogger.model

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

/**
 * Open-Meteo request URLs and response parsing, kept pure so the rules are unit
 * tested. Port of `OpenMeteoClient`, `ForecastClient` and the backfill batches.
 * Only coordinates and dates leave the device; there is no API key.
 */
object OpenMeteo {
    const val FORECAST = "https://api.open-meteo.com/v1/forecast"
    const val ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
    const val AIR_QUALITY = "https://air-quality-api.open-meteo.com/v1/air-quality"

    private const val HOURLY_WEATHER =
        "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,uv_index,dew_point_2m"
    private const val HOURLY_AIR =
        "us_aqi,european_aqi,pm2_5,pm10,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"

    data class Weather(
        val conditionSummary: String?,
        val weatherCode: Int?,
        val temperatureC: Double?,
        val apparentTemperatureC: Double?,
        val relativeHumidityPercent: Double?,
        val pressureHpa: Double?,
        val pressureTrend: PressureTrend,
        val precipitationMm: Double?,
        val windSpeedKph: Double?,
        val windDirectionDegrees: Double?,
        val cloudCoverPercent: Double?,
        val uvIndex: Double?,
        val dewPointC: Double?,
    )

    data class AirQuality(
        val usAQI: Double?, val europeanAQI: Double?, val pm25: Double?, val pm10: Double?, val ozone: Double?,
        val nitrogenDioxide: Double?, val sulphurDioxide: Double?, val carbonMonoxide: Double?,
        val alderPollen: Double?, val birchPollen: Double?, val grassPollen: Double?,
        val mugwortPollen: Double?, val olivePollen: Double?, val ragweedPollen: Double?,
    )

    // URLs

    private fun coord(value: Double) = value.toString()

    /** Hourly weather for the event day plus the prior day, so the 3-hour-prior pressure index always exists. */
    fun hourlySlotUrl(base: String, latitude: Double, longitude: Double, eventDay: LocalDate): String =
        "$base?latitude=${coord(latitude)}&longitude=${coord(longitude)}&timezone=auto" +
            "&start_date=${eventDay.minusDays(1)}&end_date=$eventDay&hourly=$HOURLY_WEATHER&wind_speed_unit=kmh"

    fun currentUrl(latitude: Double, longitude: Double): String =
        "$FORECAST?latitude=${coord(latitude)}&longitude=${coord(longitude)}&timezone=auto" +
            "&current=$HOURLY_WEATHER&hourly=pressure_msl&past_hours=6&wind_speed_unit=kmh"

    fun airQualityUrl(latitude: Double, longitude: Double, eventDay: LocalDate): String =
        "$AIR_QUALITY?latitude=${coord(latitude)}&longitude=${coord(longitude)}&timezone=auto" +
            "&start_date=$eventDay&end_date=$eventDay&hourly=$HOURLY_AIR"

    fun forecastPressureUrl(latitude: Double, longitude: Double): String =
        "$FORECAST?latitude=${coord(latitude)}&longitude=${coord(longitude)}&timezone=auto&hourly=pressure_msl&forecast_days=2"

    fun forecastAirUrl(latitude: Double, longitude: Double): String =
        "$AIR_QUALITY?latitude=${coord(latitude)}&longitude=${coord(longitude)}&timezone=auto&hourly=us_aqi&forecast_days=2"

    fun archivePressureUrl(latitude: Double, longitude: Double, start: LocalDate, end: LocalDate): String =
        "$ARCHIVE?latitude=${coord(latitude)}&longitude=${coord(longitude)}&timezone=auto&start_date=$start&end_date=$end&hourly=pressure_msl"

    fun archiveAirUrl(latitude: Double, longitude: Double, start: LocalDate, end: LocalDate): String =
        "$AIR_QUALITY?latitude=${coord(latitude)}&longitude=${coord(longitude)}&timezone=auto&start_date=$start&end_date=$end&hourly=us_aqi"

    // Parsing helpers

    private fun JSONArray?.doubleAt(i: Int): Double? {
        if (this == null || i < 0 || i >= length() || isNull(i)) return null
        return optDouble(i).takeUnless { it.isNaN() }
    }

    private fun JSONObject.doubleOrNull(key: String): Double? =
        if (!has(key) || isNull(key)) null else optDouble(key).takeUnless { it.isNaN() }

    private fun JSONArray.strings(): List<String> = (0 until length()).map { optString(it) }

    private fun zone(json: JSONObject): ZoneId? = runCatching { ZoneId.of(json.getString("timezone")) }.getOrNull()

    /** Index of the hourly slot nearest `target`. */
    private fun nearestIndex(times: List<String>, zone: ZoneId, target: Instant): Int? {
        var best: Int? = null
        var bestDelta = Long.MAX_VALUE
        times.forEachIndexed { i, raw ->
            val t = OpenMeteoTime.hourDate(raw, zone) ?: return@forEachIndexed
            val d = abs(Duration.between(target, t).toMillis())
            if (d < bestDelta) {
                bestDelta = d
                best = i
            }
        }
        return best
    }

    /** Pressure 3 hours before versus the slot: over 1 hPa either way is a trend. */
    fun trend(pressures: JSONArray?, index: Int): PressureTrend {
        val current = pressures.doubleAt(index) ?: return PressureTrend.UNAVAILABLE
        val prior = pressures.doubleAt(index - 3) ?: return PressureTrend.UNAVAILABLE
        val delta = current - prior
        return when {
            delta > 1.0 -> PressureTrend.RISING
            delta < -1.0 -> PressureTrend.FALLING
            else -> PressureTrend.STEADY
        }
    }

    /** Weather at event time from an hourly forecast or archive payload; null when unusable. */
    fun parseHourlySlot(body: String, eventDate: Instant): Weather? = runCatching {
        val json = JSONObject(body)
        val h = json.getJSONObject("hourly")
        val times = h.getJSONArray("time").strings()
        if (times.isEmpty()) return null
        val zone = zone(json) ?: return null
        val idx = nearestIndex(times, zone, eventDate) ?: return null
        val code = h.optJSONArray("weather_code").doubleAt(idx)?.roundToInt()
        Weather(
            conditionSummary = code?.let(::wmoSummary),
            weatherCode = code,
            temperatureC = h.optJSONArray("temperature_2m").doubleAt(idx),
            apparentTemperatureC = h.optJSONArray("apparent_temperature").doubleAt(idx),
            relativeHumidityPercent = h.optJSONArray("relative_humidity_2m").doubleAt(idx),
            pressureHpa = h.optJSONArray("pressure_msl").doubleAt(idx),
            pressureTrend = trend(h.optJSONArray("pressure_msl"), idx),
            precipitationMm = h.optJSONArray("precipitation").doubleAt(idx),
            windSpeedKph = h.optJSONArray("wind_speed_10m").doubleAt(idx),
            windDirectionDegrees = h.optJSONArray("wind_direction_10m").doubleAt(idx),
            cloudCoverPercent = h.optJSONArray("cloud_cover").doubleAt(idx),
            uvIndex = h.optJSONArray("uv_index").doubleAt(idx),
            dewPointC = h.optJSONArray("dew_point_2m").doubleAt(idx),
        )
    }.getOrNull()

    /** Current conditions with the trend from the last six hours of `pressure_msl`. */
    fun parseCurrent(body: String, now: Instant): Weather? = runCatching {
        val json = JSONObject(body)
        val c = json.getJSONObject("current")
        val h = json.optJSONObject("hourly")
        val zone = zone(json)
        val trend = if (zone == null || h == null) PressureTrend.UNAVAILABLE else {
            nearestIndex(h.getJSONArray("time").strings(), zone, now)?.let { trend(h.optJSONArray("pressure_msl"), it) }
                ?: PressureTrend.UNAVAILABLE
        }
        val code = c.doubleOrNull("weather_code")?.roundToInt()
        Weather(
            conditionSummary = code?.let(::wmoSummary),
            weatherCode = code,
            temperatureC = c.doubleOrNull("temperature_2m"),
            apparentTemperatureC = c.doubleOrNull("apparent_temperature"),
            relativeHumidityPercent = c.doubleOrNull("relative_humidity_2m"),
            pressureHpa = c.doubleOrNull("pressure_msl"),
            pressureTrend = trend,
            precipitationMm = c.doubleOrNull("precipitation"),
            windSpeedKph = c.doubleOrNull("wind_speed_10m"),
            windDirectionDegrees = c.doubleOrNull("wind_direction_10m"),
            cloudCoverPercent = c.doubleOrNull("cloud_cover"),
            uvIndex = c.doubleOrNull("uv_index"),
            dewPointC = c.doubleOrNull("dew_point_2m"),
        )
    }.getOrNull()

    fun parseAirQuality(body: String, eventDate: Instant): AirQuality? = runCatching {
        val json = JSONObject(body)
        val h = json.getJSONObject("hourly")
        val times = h.getJSONArray("time").strings()
        if (times.isEmpty()) return null
        val zone = zone(json) ?: return null
        val idx = nearestIndex(times, zone, eventDate) ?: return null
        fun at(key: String) = h.optJSONArray(key).doubleAt(idx)
        AirQuality(
            at("us_aqi"), at("european_aqi"), at("pm2_5"), at("pm10"), at("ozone"),
            at("nitrogen_dioxide"), at("sulphur_dioxide"), at("carbon_monoxide"),
            at("alder_pollen"), at("birch_pollen"), at("grass_pollen"), at("mugwort_pollen"), at("olive_pollen"), at("ragweed_pollen"),
        )
    }.getOrNull()

    /** The next 24 hours of `pressure_msl`, with AQI aligned by the raw time string. */
    fun parseForecastWindow(weatherBody: String, airBody: String?, now: Instant): HourlyForecast? = runCatching {
        val json = JSONObject(weatherBody)
        val zone = zone(json) ?: return null
        val h = json.getJSONObject("hourly")
        val rawTimes = h.getJSONArray("time").strings()
        val pressures = h.optJSONArray("pressure_msl")
        val horizon = now.plus(Duration.ofHours(24))
        val times = mutableListOf<Instant>()
        val timeStrings = mutableListOf<String>()
        val pressureWindow = mutableListOf<Double?>()
        for ((i, raw) in rawTimes.withIndex()) {
            val parsed = OpenMeteoTime.hourDate(raw, zone) ?: continue
            if (parsed.isBefore(now.minus(Duration.ofMinutes(30)))) continue
            if (parsed.isAfter(horizon)) break
            times += parsed
            timeStrings += raw
            pressureWindow += pressures.doubleAt(i)
        }
        val aqiByTime = airBody?.let { body ->
            runCatching {
                val air = JSONObject(body).getJSONObject("hourly")
                val airTimes = air.getJSONArray("time").strings()
                val values = air.optJSONArray("us_aqi")
                airTimes.withIndex().associate { (i, t) -> t to values.doubleAt(i) }
            }.getOrNull()
        }
        HourlyForecast(times, pressureWindow, timeStrings.map { aqiByTime?.get(it) })
    }.getOrNull()

    /**
     * Per-day pressure trend from an archive payload: mean of the last three hourly
     * values minus the first three, at 1.5 hPa either way. Days with under two
     * readings are unavailable and not marked fetched.
     */
    fun parseDailyPressureTrends(body: String): Map<String, Pair<PressureTrend, Boolean>>? = runCatching {
        val h = JSONObject(body).getJSONObject("hourly")
        val times = h.getJSONArray("time").strings()
        val pressures = h.optJSONArray("pressure_msl")
        val byDay = LinkedHashMap<String, MutableList<Double>>()
        times.forEachIndexed { i, t ->
            val p = pressures.doubleAt(i) ?: return@forEachIndexed
            byDay.getOrPut(t.take(10)) { mutableListOf() } += p
        }
        byDay.mapValues { (_, values) ->
            if (values.size < 2) return@mapValues PressureTrend.UNAVAILABLE to false
            val first = values.take(3).average()
            val last = values.takeLast(3).average()
            val delta = last - first
            val trend = when {
                delta <= -1.5 -> PressureTrend.FALLING
                delta >= 1.5 -> PressureTrend.RISING
                else -> PressureTrend.STEADY
            }
            trend to true
        }
    }.getOrNull()

    /** Per-day peak US AQI from an air-quality archive payload. */
    fun parseDailyAqiPeaks(body: String): Map<String, Double>? = runCatching {
        val h = JSONObject(body).getJSONObject("hourly")
        val times = h.getJSONArray("time").strings()
        val values = h.optJSONArray("us_aqi")
        val out = HashMap<String, Double>()
        times.forEachIndexed { i, t ->
            val v = values.doubleAt(i) ?: return@forEachIndexed
            val day = t.take(10)
            out[day] = maxOf(out[day] ?: 0.0, v)
        }
        out
    }.getOrNull()

    /** WMO weather interpretation codes, as Open-Meteo reports them. */
    fun wmoSummary(code: Int): String = when (code) {
        0 -> "Clear"
        1, 2, 3 -> "Mainly clear to overcast"
        45, 48 -> "Fog"
        51, 53, 55 -> "Drizzle"
        56, 57 -> "Freezing drizzle"
        61, 63, 65 -> "Rain"
        66, 67 -> "Freezing rain"
        71, 73, 75 -> "Snow"
        77 -> "Snow grains"
        80, 81, 82 -> "Rain showers"
        85, 86 -> "Snow showers"
        95 -> "Thunderstorm"
        96, 99 -> "Thunderstorm with hail"
        else -> "Weather code $code"
    }

    /** Builds the event snapshot; captured only when it has a place, a summary, a temperature or a pressure. */
    fun snapshot(locality: String?, region: String?, altitude: Double?, weather: Weather, air: AirQuality?): EnvironmentCaptureResult {
        val s = EnvironmentSnapshot(
            locality = locality, region = region, altitudeM = altitude,
            weatherSummary = weather.conditionSummary, weatherCode = weather.weatherCode,
            temperatureC = weather.temperatureC, apparentTemperatureC = weather.apparentTemperatureC,
            humidityPercent = weather.relativeHumidityPercent, pressureHpa = weather.pressureHpa,
            pressureTrend = weather.pressureTrend, precipitationMm = weather.precipitationMm,
            windSpeedKph = weather.windSpeedKph, windDirectionDegrees = weather.windDirectionDegrees,
            cloudCoverPercent = weather.cloudCoverPercent, uvIndex = weather.uvIndex, dewPointC = weather.dewPointC,
            usAQI = air?.usAQI, europeanAQI = air?.europeanAQI, pm25 = air?.pm25, pm10 = air?.pm10, ozone = air?.ozone,
            nitrogenDioxide = air?.nitrogenDioxide, sulphurDioxide = air?.sulphurDioxide, carbonMonoxide = air?.carbonMonoxide,
            alderPollen = air?.alderPollen, birchPollen = air?.birchPollen, grassPollen = air?.grassPollen,
            mugwortPollen = air?.mugwortPollen, olivePollen = air?.olivePollen, ragweedPollen = air?.ragweedPollen,
        )
        val meaningful = s.locality != null || s.weatherSummary != null || s.temperatureC != null || s.pressureHpa != null
        return if (meaningful) EnvironmentCaptureResult(CaptureSourceStatus.CAPTURED, null, s)
        else EnvironmentCaptureResult(CaptureSourceStatus.UNAVAILABLE, "No environment context was available for this event.", s)
    }
}
