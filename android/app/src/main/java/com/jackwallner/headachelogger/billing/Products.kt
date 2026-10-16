package com.jackwallner.headachelogger.billing

/** The iOS product IDs, reused on Play: subscriptions with `monthly`/`yearly` base plans, lifetime as a one-time product. */
object HeadacheProProduct {
    const val LIFETIME = "com.jackwallner.headachelogger"
    const val YEARLY = "com.jackwallner.headachelogger.pro.yearly"
    const val MONTHLY = "com.jackwallner.headachelogger.pro.monthly"
    val all = listOf(LIFETIME, YEARLY, MONTHLY)
}
