package com.jackwallner.headachelogger.model

/** Port of `HomeView.ProMilestone`: the Pro card shown at 3, 5 and 10 logs. */
enum class ProMilestone(val count: Int, val title: String, val detail: String) {
    TEN(10, "10 headaches, meaningful data", "You've built enough history for meaningful patterns. Unlock Pro to see your personalized patterns and get proactive alerts."),
    FIVE(5, "5 headaches logged, enough for patterns", "You have enough data for personalized pattern analysis. Pro shows the patterns in your logs."),
    THREE(3, "You've logged 3 headaches", "Great start! Pro reveals the patterns hiding in your logs: time, sleep, weather, and more."),
    ;

    companion object {
        /**
         * One Pro moment per session: the card yields to a trial offer that already fired, but its
         * own claim on the session must not hide it again. A retired top milestone stays retired.
         */
        fun active(
            count: Int,
            isPro: Boolean,
            sessionClaimedElsewhere: Boolean,
            shown3: Boolean,
            shown5: Boolean,
            shown10: Boolean,
        ): ProMilestone? {
            if (isPro || sessionClaimedElsewhere) return null
            return when {
                count >= 10 -> if (shown10) null else TEN
                count >= 5 -> if (shown5) null else FIVE
                count >= 3 -> if (shown3) null else THREE
                else -> null
            }
        }
    }
}
