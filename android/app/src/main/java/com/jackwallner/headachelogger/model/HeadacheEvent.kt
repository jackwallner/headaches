package com.jackwallner.headachelogger.model

import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID

enum class CaptureStatus(val raw: String) {
    PENDING("pending"), COMPLETE("complete"), PARTIAL("partial"), FAILED("failed");

    companion object {
        fun from(raw: String?): CaptureStatus? = entries.firstOrNull { it.raw == raw }
    }
}

enum class CaptureSourceStatus(val raw: String) {
    PENDING("pending"), CAPTURED("captured"), UNAVAILABLE("unavailable"), FAILED("failed");

    companion object {
        fun from(raw: String?): CaptureSourceStatus? = entries.firstOrNull { it.raw == raw }
    }
}

enum class PartOfDay(val raw: String) {
    OVERNIGHT("overnight"), MORNING("morning"), AFTERNOON("afternoon"), EVENING("evening");

    val title: String get() = raw.replaceFirstChar(Char::uppercaseChar)

    companion object {
        fun from(raw: String?): PartOfDay? = entries.firstOrNull { it.raw == raw }

        fun fromHour(hour: Int): PartOfDay = when (hour) {
            in 0..5 -> OVERNIGHT
            in 6..11 -> MORNING
            in 12..16 -> AFTERNOON
            else -> EVENING
        }

        fun from(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): PartOfDay =
            fromHour(instant.atZone(zone).hour)
    }
}

enum class PressureTrend(val raw: String) {
    RISING("rising"), FALLING("falling"), STEADY("steady"), UNAVAILABLE("unavailable");

    companion object {
        fun from(raw: String?): PressureTrend? = entries.firstOrNull { it.raw == raw }
    }
}

enum class HeadacheSeverity(val raw: String) {
    SLIGHT("slight"), MEDIUM("medium"), EXTREME("extreme");

    val title: String get() = raw.replaceFirstChar(Char::uppercaseChar)

    companion object {
        fun from(raw: String?): HeadacheSeverity? = entries.firstOrNull { it.raw == raw }
    }
}

enum class MotionActivity(val raw: String) {
    STATIONARY("stationary"), WALKING("walking"), RUNNING("running"),
    AUTOMOTIVE("automotive"), CYCLING("cycling"), UNKNOWN("unknown");

    companion object {
        fun from(raw: String?): MotionActivity? = entries.firstOrNull { it.raw == raw }
    }
}

/** What Health Connect gave for one log. On Android only sleep is read; every other field stays null. */
data class HealthSnapshot(
    val sleepHoursLastNight: Double? = null,
    val lastMainSleepWakeTime: Instant? = null,
    val hoursSinceMainSleepWake: Double? = null,
) {
    val hasMeaningfulValue: Boolean
        get() = sleepHoursLastNight != null || lastMainSleepWakeTime != null || hoursSinceMainSleepWake != null
}

data class HealthCaptureResult(val status: CaptureSourceStatus, val message: String?, val snapshot: HealthSnapshot?)

data class EnvironmentSnapshot(
    val locality: String? = null,
    val region: String? = null,
    val altitudeM: Double? = null,
    val weatherSummary: String? = null,
    val weatherCode: Int? = null,
    val temperatureC: Double? = null,
    val apparentTemperatureC: Double? = null,
    val humidityPercent: Double? = null,
    val pressureHpa: Double? = null,
    val pressureTrend: PressureTrend = PressureTrend.UNAVAILABLE,
    val precipitationMm: Double? = null,
    val windSpeedKph: Double? = null,
    val windDirectionDegrees: Double? = null,
    val cloudCoverPercent: Double? = null,
    val uvIndex: Double? = null,
    val dewPointC: Double? = null,
    val usAQI: Double? = null,
    val europeanAQI: Double? = null,
    val pm25: Double? = null,
    val pm10: Double? = null,
    val ozone: Double? = null,
    val nitrogenDioxide: Double? = null,
    val sulphurDioxide: Double? = null,
    val carbonMonoxide: Double? = null,
    val alderPollen: Double? = null,
    val birchPollen: Double? = null,
    val grassPollen: Double? = null,
    val mugwortPollen: Double? = null,
    val olivePollen: Double? = null,
    val ragweedPollen: Double? = null,
)

data class EnvironmentCaptureResult(val status: CaptureSourceStatus, val message: String?, val snapshot: EnvironmentSnapshot?)

/**
 * Port of the SwiftData `HeadacheEvent` model: one tap, one row. Every column of
 * the iOS model is kept so CSV files move between platforms without loss, even
 * though Android only fills sleep from Health Connect.
 */
class HeadacheEvent(timestamp: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()) {
    var id: UUID = UUID.randomUUID()
    var timestamp: Instant = timestamp
    var createdAt: Instant = Instant.now()
    var captureCompletedAt: Instant? = null

    var timezoneIdentifier: String = zone.id
    var weekdayIndex: Int = weekdayIndexOf(timestamp.atZone(zone))
    var weekdayName: String = weekdayNameOf(timestamp.atZone(zone))
    var hourOfDay: Int = timestamp.atZone(zone).hour
    var minuteOfHour: Int = timestamp.atZone(zone).minute
    var partOfDayRaw: String = PartOfDay.from(timestamp, zone).raw
    var captureStatusRaw: String = CaptureStatus.PENDING.raw

    var healthStatusRaw: String = CaptureSourceStatus.PENDING.raw
    var environmentStatusRaw: String = CaptureSourceStatus.PENDING.raw
    var healthStatusMessage: String? = null
    var environmentStatusMessage: String? = null

    var locality: String? = null
    var region: String? = null
    var altitudeM: Double? = null
    var weatherSummary: String? = null
    var weatherCode: Int? = null
    var temperatureC: Double? = null
    var apparentTemperatureC: Double? = null
    var humidityPercent: Double? = null
    var pressureHpa: Double? = null
    var pressureTrendRaw: String = PressureTrend.UNAVAILABLE.raw
    var precipitationMm: Double? = null
    var windSpeedKph: Double? = null
    var windDirectionDegrees: Double? = null
    var cloudCoverPercent: Double? = null
    var uvIndex: Double? = null
    var dewPointC: Double? = null
    var usAQI: Double? = null
    var europeanAQI: Double? = null
    var pm25: Double? = null
    var pm10: Double? = null
    var ozone: Double? = null
    var nitrogenDioxide: Double? = null
    var sulphurDioxide: Double? = null
    var carbonMonoxide: Double? = null
    var alderPollen: Double? = null
    var birchPollen: Double? = null
    var grassPollen: Double? = null
    var mugwortPollen: Double? = null
    var olivePollen: Double? = null
    var ragweedPollen: Double? = null

    var stepsToday: Int? = null
    var activeEnergyKcalToday: Double? = null
    var distanceWalkingRunningKmToday: Double? = null
    var exerciseMinutesToday: Double? = null
    var sleepHoursLastNight: Double? = null
    var restingHeartRateBpm: Double? = null
    var recentHeartRateAverageBpm: Double? = null
    var hrvSDNNMs: Double? = null
    var respiratoryRateBrpm: Double? = null
    var workoutsLast24h: Int? = null
    var workoutMinutesLast24h: Double? = null

    var lastMainSleepWakeTime: Instant? = null
    var hoursSinceMainSleepWake: Double? = null
    var environmentalAudioExposureDbA: Double? = null
    var oxygenSaturationPercent: Double? = null
    var vo2MaxMlPerKgPerMin: Double? = null
    var walkingSpeedMetersPerSecond: Double? = null
    var appleStandMinutesToday: Double? = null
    var basalEnergyKcalToday: Double? = null
    var flightsClimbedToday: Double? = null
    var mindfulMinutesToday: Double? = null
    var barometricPressureDeltaHpa6h: Double? = null
    var caffeineMgToday: Double? = null
    var waterMlToday: Double? = null
    var daysSinceLastPeriodStart: Int? = null
    var bloodPressureSystolicMmHg: Double? = null
    var bloodPressureDiastolicMmHg: Double? = null
    var bloodGlucoseMgPerDL: Double? = null
    var headphoneAudioExposureDbA: Double? = null
    var timeInDaylightMinutesToday: Double? = null

    var batteryLevelPercent: Double? = null
    var isCharging: Boolean? = null
    var isLowPowerMode: Boolean? = null
    var motionActivityRaw: String? = null

    var userNotes: String? = null
    var severityRaw: String? = null

    var partOfDay: PartOfDay
        get() = PartOfDay.from(partOfDayRaw) ?: PartOfDay.AFTERNOON
        set(value) { partOfDayRaw = value.raw }

    var captureStatus: CaptureStatus
        get() = CaptureStatus.from(captureStatusRaw) ?: CaptureStatus.PENDING
        set(value) { captureStatusRaw = value.raw }

    var healthStatus: CaptureSourceStatus
        get() = CaptureSourceStatus.from(healthStatusRaw) ?: CaptureSourceStatus.PENDING
        set(value) { healthStatusRaw = value.raw }

    var environmentStatus: CaptureSourceStatus
        get() = CaptureSourceStatus.from(environmentStatusRaw) ?: CaptureSourceStatus.PENDING
        set(value) { environmentStatusRaw = value.raw }

    var pressureTrend: PressureTrend
        get() = PressureTrend.from(pressureTrendRaw) ?: PressureTrend.UNAVAILABLE
        set(value) { pressureTrendRaw = value.raw }

    var severity: HeadacheSeverity?
        get() = HeadacheSeverity.from(severityRaw)
        set(value) { severityRaw = value?.raw }

    var motionActivity: MotionActivity?
        get() = MotionActivity.from(motionActivityRaw)
        set(value) { motionActivityRaw = value?.raw }

    val locationLabel: String
        get() = listOfNotNull(locality, region).filter { it.isNotEmpty() }.joinToString(", ")

    /** Moves the event to a new time and recomputes every derived calendar field, like the iOS edit sheet. */
    fun reschedule(to: Instant, zone: ZoneId = ZoneId.systemDefault()) {
        timestamp = to
        val local = to.atZone(zone)
        timezoneIdentifier = zone.id
        weekdayIndex = weekdayIndexOf(local)
        weekdayName = weekdayNameOf(local)
        hourOfDay = local.hour
        minuteOfHour = local.minute
        partOfDay = PartOfDay.fromHour(local.hour)
    }

    fun apply(result: HealthCaptureResult) {
        healthStatus = result.status
        healthStatusMessage = result.message
        val snapshot = result.snapshot ?: return
        sleepHoursLastNight = snapshot.sleepHoursLastNight
        lastMainSleepWakeTime = snapshot.lastMainSleepWakeTime
        hoursSinceMainSleepWake = snapshot.hoursSinceMainSleepWake
    }

    fun apply(result: EnvironmentCaptureResult) {
        environmentStatus = result.status
        environmentStatusMessage = result.message
        val s = result.snapshot ?: return
        locality = s.locality
        region = s.region
        altitudeM = s.altitudeM
        weatherSummary = s.weatherSummary
        weatherCode = s.weatherCode
        temperatureC = s.temperatureC
        apparentTemperatureC = s.apparentTemperatureC
        humidityPercent = s.humidityPercent
        pressureHpa = s.pressureHpa
        pressureTrend = s.pressureTrend
        precipitationMm = s.precipitationMm
        windSpeedKph = s.windSpeedKph
        windDirectionDegrees = s.windDirectionDegrees
        cloudCoverPercent = s.cloudCoverPercent
        uvIndex = s.uvIndex
        dewPointC = s.dewPointC
        usAQI = s.usAQI
        europeanAQI = s.europeanAQI
        pm25 = s.pm25
        pm10 = s.pm10
        ozone = s.ozone
        nitrogenDioxide = s.nitrogenDioxide
        sulphurDioxide = s.sulphurDioxide
        carbonMonoxide = s.carbonMonoxide
        alderPollen = s.alderPollen
        birchPollen = s.birchPollen
        grassPollen = s.grassPollen
        mugwortPollen = s.mugwortPollen
        olivePollen = s.olivePollen
        ragweedPollen = s.ragweedPollen
    }

    fun finalizeCapture(now: Instant = Instant.now()) {
        captureCompletedAt = now
        captureStatus = finalStatus(healthStatus, environmentStatus)
    }

    companion object {
        /** Swift's Calendar weekday: 1 is Sunday through 7 Saturday. */
        fun weekdayIndexOf(date: ZonedDateTime): Int = date.dayOfWeek.value % 7 + 1

        /** Fixed English so the CSV column is stable across device locales (iOS uses en_US_POSIX "EEEE"). */
        fun weekdayNameOf(date: ZonedDateTime): String = date.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.US)

        fun weekdayName(index: Int): String {
            val day = if (index == 1) DayOfWeek.SUNDAY else DayOfWeek.of(index - 1)
            return day.getDisplayName(TextStyle.FULL, Locale.US)
        }

        fun finalStatus(health: CaptureSourceStatus, environment: CaptureSourceStatus): CaptureStatus = when {
            health == CaptureSourceStatus.CAPTURED && environment == CaptureSourceStatus.CAPTURED -> CaptureStatus.COMPLETE
            health == CaptureSourceStatus.FAILED && environment == CaptureSourceStatus.FAILED -> CaptureStatus.FAILED
            health == CaptureSourceStatus.FAILED && environment == CaptureSourceStatus.UNAVAILABLE -> CaptureStatus.FAILED
            health == CaptureSourceStatus.UNAVAILABLE && environment == CaptureSourceStatus.FAILED -> CaptureStatus.FAILED
            // A widget or offline log with no Health or weather in that process.
            health == CaptureSourceStatus.UNAVAILABLE && environment == CaptureSourceStatus.UNAVAILABLE -> CaptureStatus.PARTIAL
            health == CaptureSourceStatus.PENDING || environment == CaptureSourceStatus.PENDING -> CaptureStatus.PENDING
            else -> CaptureStatus.PARTIAL
        }
    }
}
