package com.jackwallner.headachelogger.billing

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The iOS purchase copy, worded for Google Play. */
class ConversionCopyTest {
    private val trial = "7-day free trial"

    @Test fun onboardingCtaMatchesIos() {
        assertEquals("Start 7-day free trial", ConversionCopy.onboardingCtaLabel(trial, "\$7.99", true))
        assertEquals("Unlock Headache Pro for \$7.99", ConversionCopy.onboardingCtaLabel(trial, "\$7.99", false))
        assertEquals("Unlock Headache Pro", ConversionCopy.onboardingCtaLabel(trial, null, true))
    }

    @Test fun disclosureLeadsWithTheTrialOnlyWhenEligible() {
        val eligible = ConversionCopy.disclosure(trial, "\$7.99 / month", true)
        assertTrue(eligible.startsWith("7-Day Free Trial, then \$7.99 / month."))
        val paid = ConversionCopy.disclosure(trial, "\$7.99 / month", false)
        assertTrue(paid.startsWith("\$7.99 / month."))
        assertFalse(paid.lowercase().contains("free trial"))
    }

    @Test fun sheetDisclosureNamesGooglePlay() {
        val text = ConversionCopy.sheetDisclosure(7, "\$7.99 / month", true)!!
        assertTrue(text.startsWith("Free for 7 days, then \$7.99 / month."))
        assertTrue(text.contains("Google Play"))
        assertFalse(ConversionCopy.sheetDisclosure(7, "\$7.99 / month", false)!!.contains("Free for"))
        assertNull(ConversionCopy.sheetDisclosure(7, null, true))
    }

    @Test fun paywallCtaWaitsUntilEligibilityResolves() {
        assertNull(ConversionCopy.paywallCtaTitle(false, true, false, false))
        assertEquals("Start My Free Trial", ConversionCopy.paywallCtaTitle(false, true, true, true))
        assertEquals("Subscribe", ConversionCopy.paywallCtaTitle(false, true, true, false))
        assertEquals("Unlock Lifetime", ConversionCopy.paywallCtaTitle(true, false, false, false))
    }

    @Test fun copyHasNoEmDashesAndNoAppleWording() {
        val all = listOf(
            ConversionCopy.RENEW_CLAUSE, ConversionCopy.UNAVAILABLE, ConversionCopy.NO_PURCHASE_FOUND,
            ConversionCopy.PURCHASE_CANCELLED, ConversionCopy.PURCHASE_FAILED, ConversionCopy.PURCHASE_PENDING,
            ConversionCopy.disclosure(trial, "\$7.99 / month", true), ConversionCopy.sheetDisclosure(7, "x", true)!!,
        )
        all.forEach {
            assertFalse(it.contains("—"), it)
            assertFalse(it.contains("App Store") || it.contains("Apple"), it)
        }
    }
}
