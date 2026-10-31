package com.jackwallner.headachelogger.data

/** What the user did about a review. Only opening the write-review page ends the passive asks. */
enum class ReviewOutcome(val raw: String) {
    OPENED_WRITE_REVIEW("openedWriteReview"),
    SUBMITTED_FEEDBACK("submittedFeedback"),
}

/**
 * Port of `ReviewPromptTracker.swift`: launch counts, positive moments and
 * eligibility for the rating ask, with the same keys and thresholds. On Android
 * the ask is Google's in-app review card, called directly with no enjoyment
 * question first and never from a button.
 */
class ReviewPromptTracker(
    private val defaults: KeyValueStore,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    var appLaunchCount: Int
        get() = maxOf(defaults.getInt(LAUNCH_COUNT), 0)
        private set(value) = defaults.putInt(LAUNCH_COUNT, value)

    var positiveMomentCount: Int
        get() = maxOf(defaults.getInt(MOMENT_COUNT), 0)
        private set(value) = defaults.putInt(MOMENT_COUNT, value)

    val hasPendingPositiveMoment: Boolean get() = defaults.getBoolean(PENDING)

    val outcome: ReviewOutcome?
        get() = defaults.getString(OUTCOME)?.let { raw -> ReviewOutcome.entries.firstOrNull { it.raw == raw } }

    val lastShownMillis: Long? get() = if (defaults.contains(LAST_SHOWN)) defaults.getLong(LAST_SHOWN) else null

    /** Once per process launch. */
    fun recordAppLaunch() {
        if (!defaults.contains(FIRST_OPEN)) defaults.putLong(FIRST_OPEN, nowMillis())
        appLaunchCount += 1
    }

    /** A complete one-tap log. */
    fun recordPositiveMoment() {
        positiveMomentCount += 1
        defaults.putBoolean(PENDING, true)
    }

    fun consumePendingPositiveMoment() = defaults.putBoolean(PENDING, false)

    fun passivePromptAllowed(): Boolean {
        if (outcome == ReviewOutcome.OPENED_WRITE_REVIEW) return false
        val last = lastShownMillis ?: return true
        return nowMillis() - last >= COOLDOWN_DAYS * DAY_MS
    }

    fun canRequestReview(hasCompletedOnboarding: Boolean): Boolean {
        if (!hasCompletedOnboarding || !passivePromptAllowed()) return false
        return appLaunchCount >= MINIMUM_LAUNCH_COUNT
    }

    fun shouldRequestAfterPositiveMoment(hasCompletedOnboarding: Boolean): Boolean =
        hasPendingPositiveMoment && canRequestReview(hasCompletedOnboarding)

    fun markShown() {
        defaults.putLong(LAST_SHOWN, nowMillis())
        consumePendingPositiveMoment()
    }

    fun markOpenedWriteReview() {
        defaults.putString(OUTCOME, ReviewOutcome.OPENED_WRITE_REVIEW.raw)
        markShown()
    }

    /** Never overwrites `OPENED_WRITE_REVIEW`, and never stops the asks. */
    fun markFeedbackSubmitted() {
        if (outcome != ReviewOutcome.OPENED_WRITE_REVIEW) defaults.putString(OUTCOME, ReviewOutcome.SUBMITTED_FEEDBACK.raw)
    }

    companion object {
        /**
         * Home is clear for the rating ask when no sheet covers it. The session's Pro moment is
         * deliberately not part of this: the Home milestone card claims it on every launch for a
         * free user with 3+ logs, which would block the ask for those users forever.
         */
        fun isHomeClear(hasCompletedOnboarding: Boolean, homeIsUncovered: Boolean, hasActiveSheet: Boolean, pendingPaywallAfterTrialDismiss: Boolean): Boolean =
            hasCompletedOnboarding && homeIsUncovered && !hasActiveSheet && !pendingPaywallAfterTrialDismiss

        const val MINIMUM_LAUNCH_COUNT = 2
        const val COOLDOWN_DAYS = 30

        private const val LAUNCH_COUNT = "reviewPrompt.appLaunchCount"
        private const val FIRST_OPEN = "reviewPrompt.firstAppOpenDate"
        private const val LAST_SHOWN = "reviewPrompt.lastShownDate"
        private const val OUTCOME = "reviewPrompt.outcome"
        private const val MOMENT_COUNT = "reviewPrompt.positiveMomentCount"
        private const val PENDING = "reviewPrompt.pendingPositiveMoment"
    }
}
