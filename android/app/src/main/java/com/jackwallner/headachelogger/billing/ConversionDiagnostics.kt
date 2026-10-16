package com.jackwallner.headachelogger.billing

import com.jackwallner.headachelogger.data.DAY_MS
import com.jackwallner.headachelogger.data.KeyValueStore
import java.time.Instant
import java.time.temporal.ChronoUnit

/** The trial funnel steps, same raw names as iOS so RevenueCat attributes line up. */
enum class FunnelStep(val raw: String) {
    TRIAL_OFFER_REACHED("trialOfferReached"),
    TRIAL_CTA_TAPPED("trialCTATapped"),
    FREE_VERSION_CHOSEN("freeVersionChosen"),
    PURCHASE_CANCELLED("purchaseCancelled"),
    PURCHASE_FAILED("purchaseFailed"),
    PURCHASE_SUCCEEDED("purchaseSucceeded"),
}

/**
 * Port of `ConversionDiagnostics.swift`: how someone met the Headache Pro pitch
 * before buying, mirrored onto the RevenueCat customer as attributes. Counts,
 * dates and surface names only; never a headache log or any health data.
 */
class ConversionDiagnostics(
    private val defaults: KeyValueStore,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    fun record(step: FunnelStep) {
        val key = "conv.funnel.${step.raw}"
        defaults.putInt(key, defaults.getInt(key) + 1)
    }

    fun recordAppOpen() {
        if (!defaults.contains(INSTALLED_AT)) defaults.putLong(INSTALLED_AT, nowMillis())
        defaults.putInt(APP_OPENS, defaults.getInt(APP_OPENS) + 1)
    }

    val totalPitchViews: Int get() = defaults.getInt(TOTAL_VIEWS)
    val lastSurface: String? get() = defaults.getString(LAST_SURFACE)
    val appOpens: Int get() = defaults.getInt(APP_OPENS)
    val installedAtMillis: Long? get() = if (defaults.contains(INSTALLED_AT)) defaults.getLong(INSTALLED_AT) else null
    val viewsBySurface: Map<String, Int>
        get() = defaults.keys().filter { it.startsWith(VIEWS_PREFIX) && it != TOTAL_VIEWS }
            .associate { it.removePrefix(VIEWS_PREFIX) to defaults.getInt(it) }

    fun recordPitchView(impressionId: String) {
        val surface = surface(impressionId)
        defaults.putInt(TOTAL_VIEWS, defaults.getInt(TOTAL_VIEWS) + 1)
        defaults.putInt(views(surface), defaults.getInt(views(surface)) + 1)
        defaults.putString(LAST_SURFACE, surface)
        if (!defaults.contains(FIRST_SEEN)) {
            defaults.putLong(FIRST_SEEN, nowMillis())
            defaults.putInt(OPENS_BEFORE_FIRST_PITCH, defaults.getInt(APP_OPENS))
            if (defaults.contains(INSTALLED_AT)) defaults.putInt(DAYS_TO_FIRST_PITCH, daysSince(defaults.getLong(INSTALLED_AT)))
        }
    }

    fun recordConversion(plan: String, startedTrial: Boolean, offeringId: String? = null) {
        if (defaults.contains(CONVERTED_ON)) return
        defaults.putString(CONVERTED_ON, defaults.getString(LAST_SURFACE) ?: "unknown")
        defaults.putInt(VIEWS_AT_CONVERT, defaults.getInt(TOTAL_VIEWS))
        defaults.putString(CONVERTED_PLAN, plan)
        defaults.putBoolean(CONVERTED_WITH_TRIAL, startedTrial)
        defaults.putLong(CONVERTED_AT, nowMillis())
        offeringId?.let { defaults.putString(CONVERTED_OFFERING, it) }
        if (defaults.contains(FIRST_SEEN)) defaults.putInt(DAYS_TO_CONVERT, daysSince(defaults.getLong(FIRST_SEEN)))
    }

    val subscriberAttributes: Map<String, String>
        get() {
            val total = defaults.getInt(TOTAL_VIEWS)
            if (total <= 0) return emptyMap()
            val out = mutableMapOf("pitch_views_total" to total.toString())
            defaults.keys().filter { it.startsWith(VIEWS_PREFIX) && it != TOTAL_VIEWS }.forEach { key ->
                val count = defaults.getInt(key)
                if (count > 0) out["pitch_views_${key.removePrefix(VIEWS_PREFIX)}".take(40)] = count.toString()
            }
            defaults.getString(LAST_SURFACE)?.let { out["pitch_last"] = it }
            if (defaults.contains(FIRST_SEEN)) {
                out["pitch_first_seen"] = iso(defaults.getLong(FIRST_SEEN))
                out["days_since_first_pitch"] = daysSince(defaults.getLong(FIRST_SEEN)).toString()
            }
            if (defaults.contains(DAYS_TO_FIRST_PITCH)) out["days_since_install"] = defaults.getInt(DAYS_TO_FIRST_PITCH).toString()
            if (defaults.contains(OPENS_BEFORE_FIRST_PITCH)) out["opens_before_first_pitch"] = defaults.getInt(OPENS_BEFORE_FIRST_PITCH).toString()
            defaults.getString(CONVERTED_ON)?.let { surface ->
                out["converted_surface"] = surface
                if (defaults.contains(CONVERTED_AT)) out["converted_at"] = iso(defaults.getLong(CONVERTED_AT))
                out["pitch_views_at_convert"] = defaults.getInt(VIEWS_AT_CONVERT).toString()
                out["days_to_convert"] = defaults.getInt(DAYS_TO_CONVERT).toString()
                out["converted_plan"] = defaults.getString(CONVERTED_PLAN) ?: "unknown"
                out["converted_with_trial"] = if (defaults.getBoolean(CONVERTED_WITH_TRIAL)) "true" else "false"
                defaults.getString(CONVERTED_OFFERING)?.let { out["converted_offering"] = it }
            }
            FunnelStep.entries.forEach { step ->
                val count = defaults.getInt("conv.funnel.${step.raw}")
                if (count > 0) out["funnel_${step.raw}"] = count.toString()
            }
            return out
        }

    private fun daysSince(millis: Long): Int = maxOf(0, ((nowMillis() - millis) / DAY_MS).toInt())
    private fun views(surface: String) = "$VIEWS_PREFIX$surface"
    private fun iso(millis: Long): String = Instant.ofEpochMilli(millis).truncatedTo(ChronoUnit.SECONDS).toString()

    companion object {
        /** `headache_insights_sheet` is reported as `insights_sheet`. */
        fun surface(impressionId: String): String = impressionId.removePrefix(PREFIX)

        private const val PREFIX = "headache_"
        private const val VIEWS_PREFIX = "conv.pitchViews."
        private const val TOTAL_VIEWS = "conv.pitchViews.total"
        private const val FIRST_SEEN = "conv.pitchFirstSeen"
        private const val LAST_SURFACE = "conv.pitchLastSurface"
        private const val INSTALLED_AT = "conv.installedAt"
        private const val APP_OPENS = "conv.appOpens"
        private const val OPENS_BEFORE_FIRST_PITCH = "conv.opensBeforeFirstPitch"
        private const val DAYS_TO_FIRST_PITCH = "conv.daysToFirstPitch"
        private const val CONVERTED_ON = "conv.convertedOn"
        private const val CONVERTED_AT = "conv.convertedAt"
        private const val VIEWS_AT_CONVERT = "conv.viewsAtConvert"
        private const val DAYS_TO_CONVERT = "conv.daysToConvert"
        private const val CONVERTED_PLAN = "conv.convertedPlan"
        private const val CONVERTED_WITH_TRIAL = "conv.convertedWithTrial"
        private const val CONVERTED_OFFERING = "conv.convertedOffering"
    }
}
