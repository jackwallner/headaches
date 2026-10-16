package com.jackwallner.headachelogger.data

import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import com.jackwallner.headachelogger.model.PersonalAlertProfile
import com.jackwallner.headachelogger.model.ProAlertPreferenceValues
import java.time.Instant
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

/** Storage keys, identical to iOS `HeadacheStorageKey` so the vocabulary matches across platforms. */
object StorageKey {
    const val HAS_COMPLETED_ONBOARDING = "hasCompletedHeadacheOnboarding"
    const val DECLINED_HEALTH_READ = "headacheDeclinedHealthRead"
    const val DECLINED_LOCATION = "headacheDeclinedLocation"
    const val USE_CELSIUS = "headacheUseCelsiusTemperature"
    const val WIDGET_LAST_LOGGED_AT = "headacheWidgetLastLoggedAt"
    const val PROMPT_FOR_SEVERITY_NOTES = "headachePromptForSeverityNotes"
    const val HAS_SEEN_PRO_INTRO = "headacheHasSeenProIntro"
    const val HAS_SEEN_TRIAL_OFFER = "headacheHasSeenTrialOffer"
    const val HAS_SEEN_INSIGHTS_TRIAL_OFFER = "headacheHasSeenInsightsTrialOffer"

    const val PRO_ALERTS_ENABLED = "headacheProAlertsEnabled"
    const val PRO_ALERT_PRESSURE_THRESHOLD = "headacheProAlertPressureDropThreshold"
    const val PRO_ALERT_AQ_ENABLED = "headacheProAlertAirQualityEnabled"
    const val PRO_ALERT_AQ_THRESHOLD = "headacheProAlertAirQualityThreshold"
    const val PRO_ALERT_QUIET_ENABLED = "headacheProAlertQuietHoursEnabled"
    const val PRO_ALERT_QUIET_START = "headacheProAlertQuietStartHour"
    const val PRO_ALERT_QUIET_END = "headacheProAlertQuietEndHour"
    const val PRO_ALERT_LAST_FIRED_AT = "headacheProAlertLastFiredAt"
    const val PRO_ALERT_LAST_FIRED_KIND = "headacheProAlertLastFiredKind"
    const val PRO_ALERT_PERSONAL_PROFILE = "headacheProAlertPersonalProfile"
    const val LAST_KNOWN_LATITUDE = "headacheLastKnownLatitude"
    const val LAST_KNOWN_LONGITUDE = "headacheLastKnownLongitude"
    const val LAST_KNOWN_LOCATION_AT = "headacheLastKnownLocationCapturedAt"

    const val PATTERN_ALERTS_ENABLED = "headachePatternAlertsEnabled"
    const val PATTERN_ALERT_SENSITIVITY = "headachePatternAlertSensitivity"

    const val MILESTONE_3 = "headacheMilestonePrompt3Shown"
    const val MILESTONE_5 = "headacheMilestonePrompt5Shown"
    const val MILESTONE_10 = "headacheMilestonePrompt10Shown"

    const val APPEARANCE = "appearance"
}

enum class Appearance(val raw: String, val label: String) {
    SYSTEM("system", "System"), LIGHT("light", "Light"), DARK("dark", "Dark");

    companion object {
        fun from(raw: String?): Appearance = entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

data class CachedLocation(val latitude: Double, val longitude: Double, val capturedAt: Instant)

/**
 * The @AppStorage values of the iOS app, each backed by Compose state so a
 * change on one screen redraws every other.
 */
class HeadacheSettings(private val defaults: KeyValueStore) {
    private inner class BoolPref(private val key: String, default: Boolean) : ReadWriteProperty<Any?, Boolean> {
        private val state: MutableState<Boolean> = mutableStateOf(defaults.getBoolean(key, default))
        override fun getValue(thisRef: Any?, property: KProperty<*>) = state.value
        override fun setValue(thisRef: Any?, property: KProperty<*>, value: Boolean) {
            state.value = value
            defaults.putBoolean(key, value)
        }
    }

    private inner class IntPref(private val key: String, default: Int) : ReadWriteProperty<Any?, Int> {
        private val state: MutableState<Int> = mutableStateOf(defaults.getInt(key, default))
        override fun getValue(thisRef: Any?, property: KProperty<*>) = state.value
        override fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
            state.value = value
            defaults.putInt(key, value)
        }
    }

    private inner class DoublePref(private val key: String, default: Double) : ReadWriteProperty<Any?, Double> {
        private val state: MutableState<Double> = mutableStateOf(defaults.getDouble(key, default))
        override fun getValue(thisRef: Any?, property: KProperty<*>) = state.value
        override fun setValue(thisRef: Any?, property: KProperty<*>, value: Double) {
            state.value = value
            defaults.putDouble(key, value)
        }
    }

    var hasCompletedOnboarding by BoolPref(StorageKey.HAS_COMPLETED_ONBOARDING, false)
    var declinedHealthRead by BoolPref(StorageKey.DECLINED_HEALTH_READ, false)
    var declinedLocation by BoolPref(StorageKey.DECLINED_LOCATION, false)
    var useCelsius by BoolPref(StorageKey.USE_CELSIUS, false)
    var promptForSeverityNotes by BoolPref(StorageKey.PROMPT_FOR_SEVERITY_NOTES, false)
    var hasSeenProIntro by BoolPref(StorageKey.HAS_SEEN_PRO_INTRO, false)
    var hasSeenTrialOffer by BoolPref(StorageKey.HAS_SEEN_TRIAL_OFFER, false)
    var hasSeenInsightsTrialOffer by BoolPref(StorageKey.HAS_SEEN_INSIGHTS_TRIAL_OFFER, false)
    var milestone3Shown by BoolPref(StorageKey.MILESTONE_3, false)
    var milestone5Shown by BoolPref(StorageKey.MILESTONE_5, false)
    var milestone10Shown by BoolPref(StorageKey.MILESTONE_10, false)

    var alertsEnabled by BoolPref(StorageKey.PRO_ALERTS_ENABLED, false)
    var pressureDropThresholdHpa by DoublePref(StorageKey.PRO_ALERT_PRESSURE_THRESHOLD, 4.0)
    var airQualityEnabled by BoolPref(StorageKey.PRO_ALERT_AQ_ENABLED, true)
    var airQualityThreshold by IntPref(StorageKey.PRO_ALERT_AQ_THRESHOLD, 100)
    var quietHoursEnabled by BoolPref(StorageKey.PRO_ALERT_QUIET_ENABLED, true)
    var quietHoursStart by IntPref(StorageKey.PRO_ALERT_QUIET_START, 22)
    var quietHoursEnd by IntPref(StorageKey.PRO_ALERT_QUIET_END, 7)
    var patternAlertsEnabled by BoolPref(StorageKey.PATTERN_ALERTS_ENABLED, false)
    var patternAlertSensitivity by DoublePref(StorageKey.PATTERN_ALERT_SENSITIVITY, 0.0)

    private val appearanceState = mutableStateOf(Appearance.from(defaults.getString(StorageKey.APPEARANCE)))
    var appearance: Appearance
        get() = appearanceState.value
        set(value) {
            appearanceState.value = value
            defaults.putString(StorageKey.APPEARANCE, value.raw)
        }

    val alertPreferences: ProAlertPreferenceValues
        get() = ProAlertPreferenceValues(
            alertsEnabled = alertsEnabled,
            pressureDropThresholdHpa = pressureDropThresholdHpa,
            airQualityEnabled = airQualityEnabled,
            airQualityThreshold = airQualityThreshold,
            quietHoursEnabled = quietHoursEnabled,
            quietHoursStart = quietHoursStart,
            quietHoursEnd = quietHoursEnd,
            patternAlertsEnabled = patternAlertsEnabled,
            patternAlertSensitivity = patternAlertSensitivity,
        )

    var widgetLastLoggedAt: Long
        get() = defaults.getLong(StorageKey.WIDGET_LAST_LOGGED_AT)
        set(value) = defaults.putLong(StorageKey.WIDGET_LAST_LOGGED_AT, value)

    var cachedLocation: CachedLocation?
        get() {
            if (!defaults.contains(StorageKey.LAST_KNOWN_LATITUDE) || !defaults.contains(StorageKey.LAST_KNOWN_LOCATION_AT)) return null
            return CachedLocation(
                defaults.getDouble(StorageKey.LAST_KNOWN_LATITUDE, 0.0),
                defaults.getDouble(StorageKey.LAST_KNOWN_LONGITUDE, 0.0),
                Instant.ofEpochMilli(defaults.getLong(StorageKey.LAST_KNOWN_LOCATION_AT)),
            )
        }
        set(value) {
            if (value == null) {
                listOf(StorageKey.LAST_KNOWN_LATITUDE, StorageKey.LAST_KNOWN_LONGITUDE, StorageKey.LAST_KNOWN_LOCATION_AT).forEach(defaults::remove)
                return
            }
            defaults.putDouble(StorageKey.LAST_KNOWN_LATITUDE, value.latitude)
            defaults.putDouble(StorageKey.LAST_KNOWN_LONGITUDE, value.longitude)
            defaults.putLong(StorageKey.LAST_KNOWN_LOCATION_AT, value.capturedAt.toEpochMilli())
        }

    var personalAlertProfile: PersonalAlertProfile
        get() = PersonalAlertProfile.fromJson(defaults.getString(StorageKey.PRO_ALERT_PERSONAL_PROFILE))
        set(value) = defaults.putString(StorageKey.PRO_ALERT_PERSONAL_PROFILE, value.toJson())

    var alertLastFiredAt: Long?
        get() = if (defaults.contains(StorageKey.PRO_ALERT_LAST_FIRED_AT)) defaults.getLong(StorageKey.PRO_ALERT_LAST_FIRED_AT) else null
        set(value) {
            if (value == null) defaults.remove(StorageKey.PRO_ALERT_LAST_FIRED_AT) else defaults.putLong(StorageKey.PRO_ALERT_LAST_FIRED_AT, value)
        }

    val alertLastFiredKind: String? get() = defaults.getString(StorageKey.PRO_ALERT_LAST_FIRED_KIND)

    fun recordAlertFired(kind: String, at: Long) {
        alertLastFiredAt = at
        defaults.putString(StorageKey.PRO_ALERT_LAST_FIRED_KIND, kind)
    }
}
