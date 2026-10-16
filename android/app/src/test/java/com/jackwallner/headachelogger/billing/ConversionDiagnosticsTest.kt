package com.jackwallner.headachelogger.billing

import com.jackwallner.headachelogger.data.DAY_MS
import com.jackwallner.headachelogger.data.InMemoryStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ConversionDiagnosticsTest {
    private var now = 1_800_000_000_000L
    private val diagnostics = ConversionDiagnostics(InMemoryStore()) { now }

    @Test fun noAttributesBeforeAnyPitch() {
        diagnostics.recordAppOpen()
        assertTrue(diagnostics.subscriberAttributes.isEmpty())
    }

    @Test fun pitchViewsAndConversionMirrorIosAttributeNames() {
        diagnostics.recordAppOpen()
        diagnostics.recordAppOpen()
        now += 2 * DAY_MS
        diagnostics.recordPitchView("headache_onboarding")
        diagnostics.recordPitchView("headache_insights_sheet")
        diagnostics.record(FunnelStep.TRIAL_CTA_TAPPED)
        now += 3 * DAY_MS
        diagnostics.recordConversion("monthly", startedTrial = true, offeringId = "android")
        val attrs = diagnostics.subscriberAttributes
        assertEquals("2", attrs["pitch_views_total"])
        assertEquals("1", attrs["pitch_views_onboarding"])
        assertEquals("1", attrs["pitch_views_insights_sheet"])
        assertEquals("insights_sheet", attrs["pitch_last"])
        assertEquals("2", attrs["opens_before_first_pitch"])
        assertEquals("2", attrs["days_since_install"])
        assertEquals("insights_sheet", attrs["converted_surface"])
        assertEquals("3", attrs["days_to_convert"])
        assertEquals("monthly", attrs["converted_plan"])
        assertEquals("true", attrs["converted_with_trial"])
        assertEquals("android", attrs["converted_offering"])
        assertEquals("1", attrs["funnel_trialCTATapped"])
    }

    @Test fun firstConversionWins() {
        diagnostics.recordPitchView("headache_paywall")
        diagnostics.recordConversion("yearly", startedTrial = false)
        diagnostics.recordConversion("lifetime", startedTrial = false)
        assertEquals("yearly", diagnostics.subscriberAttributes["converted_plan"])
    }
}
