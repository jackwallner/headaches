package com.jackwallner.headachelogger

import android.content.Intent

/** Release builds ignore launch extras, so nothing here can unlock paid content in production. */
object DebugLaunchOptions {
    var tab: String? = null
    var sheet: String? = null
    var onboardingStep: Int? = null
    var suppressPromos: Boolean = false

    fun prepare(app: HeadacheApplication, intent: Intent?) = Unit

    fun apply(graph: AppGraph, intent: Intent?) = Unit
}
