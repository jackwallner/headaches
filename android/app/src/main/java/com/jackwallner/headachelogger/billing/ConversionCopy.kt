package com.jackwallner.headachelogger.billing

/** Purchase copy shared by onboarding, the trial sheet and the paywall, worded for Google Play. */
object ConversionCopy {
    const val TRIAL_CTA_TITLE = "Start My Free Trial"
    const val RENEW_CLAUSE =
        "Auto-renews unless cancelled at least 24 hours before the end of the current period. " +
            "Manage or cancel in Google Play under Payments & subscriptions."
    const val UNAVAILABLE = "Couldn't reach Google Play. Check your connection and try again."
    const val NO_PURCHASE_FOUND = "No previous Headache Pro purchase was found on this Google account."

    /** iOS `onboardingCTALabel`: "Start 7-day free trial" or "Unlock Headache Pro for $X". */
    fun onboardingCtaLabel(trialLabel: String?, priceFormatted: String?, eligibleForTrial: Boolean): String = when {
        priceFormatted == null -> "Unlock Headache Pro"
        eligibleForTrial && !trialLabel.isNullOrEmpty() -> "Start $trialLabel"
        else -> "Unlock Headache Pro for $priceFormatted"
    }

    fun disclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Boolean): String =
        if (eligibleForTrial && !trialLabel.isNullOrEmpty()) "${trialLabel.capitalizeWords()}, then $priceLabel. $RENEW_CLAUSE"
        else "$priceLabel. $RENEW_CLAUSE"

    /** The trial sheet's one-line terms, as on iOS. */
    fun sheetDisclosure(trialDays: Int?, priceLabel: String?, eligibleForTrial: Boolean): String? {
        priceLabel ?: return null
        return if (eligibleForTrial && trialDays != null) {
            "Free for $trialDays days, then $priceLabel. Auto-renews; cancel anytime in Google Play at least 24h before it ends."
        } else "$priceLabel. Auto-renews; cancel anytime in Google Play at least 24h before the period ends."
    }

    const val PURCHASE_CANCELLED = "Purchase cancelled. Tap again to continue."
    const val PURCHASE_FAILED = "Couldn't complete the purchase. Please try again."
    const val PURCHASE_PENDING = "Waiting on Google Play to approve this. Headache Pro unlocks as soon as it clears."

    /** nil while eligibility is still resolving, so the button never flashes between labels. */
    fun paywallCtaTitle(isLifetime: Boolean, hasIntroOffer: Boolean, eligibilityResolved: Boolean, eligibleForTrial: Boolean): String? = when {
        isLifetime -> "Unlock Lifetime"
        hasIntroOffer && !eligibilityResolved -> null
        eligibleForTrial -> TRIAL_CTA_TITLE
        else -> "Subscribe"
    }
}

/** Swift's `String.capitalized` for the short trial phrases this app uses. */
internal fun String.capitalizeWords(): String =
    split(" ").joinToString(" ") { word -> word.split("-").joinToString("-") { it.replaceFirstChar(Char::uppercaseChar) } }
