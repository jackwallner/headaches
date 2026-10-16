package com.jackwallner.headachelogger

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.core.view.WindowCompat
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.lifecycleScope
import com.jackwallner.headachelogger.data.Appearance
import com.jackwallner.headachelogger.ui.LocalForeground
import com.jackwallner.headachelogger.ui.LocalGraph
import com.jackwallner.headachelogger.ui.RootScreen
import com.jackwallner.headachelogger.ui.theme.HeadacheTheme
import kotlinx.coroutines.launch

@OptIn(ExperimentalComposeUiApi::class)
class MainActivity : ComponentActivity() {
    private val graph: AppGraph get() = (application as HeadacheApplication).graph

    private val healthPermissions = registerForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
        graph.permissions.complete(granted)
    }

    /** Bumped on every return to the foreground; the iOS `scenePhase == .active` hooks key off it. */
    private var foregroundEpoch by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) DebugLaunchOptions.prepare(application as HeadacheApplication, intent)
        val graph = graph
        graph.permissions.launch = { healthPermissions.launch(it) }
        if (savedInstanceState == null) {
            graph.review.recordAppLaunch()
            graph.diagnostics.recordAppOpen()
            DebugLaunchOptions.apply(graph, intent)
        }
        enableEdgeToEdge()
        lifecycleScope.launch { graph.store.start() }
        setContent {
            val dark = when (graph.settings.appearance) {
                Appearance.SYSTEM -> isSystemInDarkTheme()
                Appearance.LIGHT -> false
                Appearance.DARK -> true
            }
            val view = LocalView.current
            SideEffect {
                val controller = WindowCompat.getInsetsController(window, view)
                controller.isAppearanceLightStatusBars = !dark
                controller.isAppearanceLightNavigationBars = !dark
            }
            CompositionLocalProvider(LocalGraph provides graph, LocalForeground provides foregroundEpoch) {
                HeadacheTheme(dark = dark) {
                    // Test tags double as resource ids so UI Automator and capture scripts can find controls.
                    Box(Modifier.semantics { testTagsAsResourceId = true }) { RootScreen(graph) }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        foregroundEpoch += 1
    }

    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { graph.store.refreshCustomerInfo() }
    }

    override fun onStop() {
        super.onStop()
        foregroundEpoch += 1
        graph.store.syncConversionAttributes()
        graph.updateForecastSchedule()
    }

    override fun onDestroy() {
        if (isFinishing) graph.permissions.launch = null
        super.onDestroy()
    }
}
