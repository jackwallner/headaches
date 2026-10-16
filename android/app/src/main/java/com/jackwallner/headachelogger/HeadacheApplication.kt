package com.jackwallner.headachelogger

import android.app.Application
import com.jackwallner.headachelogger.alerts.Alerts

class HeadacheApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
        Alerts.ensureChannel(this)
    }

    /** Debug launch extras only: a fresh graph after stored state was wiped. */
    fun rebuildGraph() {
        graph = AppGraph(this)
    }
}
