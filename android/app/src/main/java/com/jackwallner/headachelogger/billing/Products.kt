package com.jackwallner.headachelogger.billing

/** The iOS lifetime ID is reused on Play. The iOS subscription IDs exceed Play's 40-character limit, so Play drops `.pro`. Subscriptions with `monthly`/`yearly` base plans, lifetime as a one-time product. */
object HeadacheProProduct {
    const val LIFETIME = "com.jackwallner.headachelogger"
    const val YEARLY = "com.jackwallner.headachelogger.yearly"
    const val MONTHLY = "com.jackwallner.headachelogger.monthly"
    val all = listOf(LIFETIME, YEARLY, MONTHLY)
}
