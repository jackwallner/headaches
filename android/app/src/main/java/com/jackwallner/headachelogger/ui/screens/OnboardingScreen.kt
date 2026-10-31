package com.jackwallner.headachelogger.ui.screens

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.DebugLaunchOptions
import com.jackwallner.headachelogger.billing.ConversionCopy
import com.jackwallner.headachelogger.billing.FunnelStep
import com.jackwallner.headachelogger.billing.PurchaseException
import com.jackwallner.headachelogger.billing.PurchaseOutcome
import com.jackwallner.headachelogger.capture.HealthAccess
import com.jackwallner.headachelogger.capture.HealthPermissions
import com.jackwallner.headachelogger.ui.Links
import com.jackwallner.headachelogger.ui.findActivity
import com.jackwallner.headachelogger.ui.openUrl
import com.jackwallner.headachelogger.ui.theme.Brand
import com.jackwallner.headachelogger.ui.theme.PrimaryButton
import com.jackwallner.headachelogger.ui.theme.TextAction
import com.jackwallner.headachelogger.ui.theme.Tint
import com.jackwallner.headachelogger.ui.theme.TopBar
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette
import com.jackwallner.headachelogger.ui.theme.tappable
import kotlinx.coroutines.launch

private const val TOTAL_STEPS = 4

/** Port of `OnboardingView`: welcome, Health Connect, location, then the Headache Pro trial. */
@Composable
fun OnboardingScreen(graph: AppGraph) {
    var step by rememberSaveable { mutableIntStateOf(DebugLaunchOptions.onboardingStep?.coerceIn(0, 3) ?: 0) }
    var working by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val locationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        graph.settings.declinedLocation = !granted
        working = false
        step = 3
    }

    LaunchedEffect(Unit) { if (graph.store.plans.isEmpty()) graph.store.fetchProducts() }

    Column(Modifier.fillMaxSize().background(palette.background)) {
        TopBar("Welcome")
        LinearProgressIndicator(
            progress = { (step + 1) / TOTAL_STEPS.toFloat() },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp).clip(RoundedCornerShape(2.dp)),
            color = Brand.primary,
            trackColor = palette.separator.copy(alpha = 0.3f),
            drawStopIndicator = {},
        )
        Box(Modifier.weight(1f)) {
            when (step) {
                0 -> Page(
                    icon = Icons.Filled.Psychology, tint = Brand.primary, title = "One Tap Headache Tracker",
                    primaryLabel = "Get Started", tag = "onboarding_get_started", onPrimary = { step = 1 },
                ) {
                    BodyText("Log a headache with a single tap. The app quietly captures time, optional Health Connect sleep, and optional local weather so you can spot patterns.")
                }
                1 -> Page(
                    icon = Icons.Filled.Favorite, tint = Tint.pink, title = "Health Connect",
                    primaryLabel = "Continue", busy = working, tag = "onboarding_health_continue",
                    onPrimary = {
                        working = true
                        scope.launch {
                            when (graph.health.access()) {
                                HealthAccess.NEEDS_PERMISSION -> {
                                    val granted = graph.permissions.request(HealthPermissions.all)
                                    graph.settings.declinedHealthRead = HealthPermissions.sleep !in granted
                                }
                                HealthAccess.UNAVAILABLE -> graph.settings.declinedHealthRead = true
                                HealthAccess.READY -> Unit
                            }
                            working = false
                            step = 2
                        }
                    },
                ) {
                    BodyText("Next, Android will ask whether to allow read access to your sleep in Health Connect. It's used to note how long you slept before a headache. Nothing is written to Health Connect, and you can change this anytime in Settings.")
                }
                2 -> Page(
                    icon = Icons.Filled.LocationOn, tint = Tint.blue, title = "Location",
                    primaryLabel = "Continue", busy = working, tag = "onboarding_location_continue",
                    onPrimary = {
                        if (graph.environment.hasPermission()) {
                            step = 3
                        } else {
                            working = true
                            locationLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
                        }
                    },
                ) {
                    BodyText("Next, Android will ask whether to share your approximate location. It's used only to fetch weather and place labels when you log. We don't track you in the background.")
                }
                else -> TrialPage(graph)
            }
        }
    }
}

@Composable
private fun TrialPage(graph: AppGraph) {
    val store = graph.store
    val context = LocalContext.current
    val nav = com.jackwallner.headachelogger.ui.LocalNav.current
    val scope = rememberCoroutineScope()
    var purchasing by remember { mutableStateOf(false) }
    var trialError by remember { mutableStateOf<String?>(null) }
    var restoring by remember { mutableStateOf(false) }

    fun finish() {
        graph.settings.hasSeenProIntro = true
        graph.settings.hasCompletedOnboarding = true
        graph.initializeDailyRecords()
    }

    // Mirrors the paywall: a restored purchase finishes onboarding, anything else says why.
    fun restore() {
        trialError = null
        restoring = true
        scope.launch {
            try {
                store.restorePurchases()
                val failure = ConversionCopy.restoreMessage(store.isPro, store.lastError)
                if (failure == null) finish() else trialError = failure
            } finally {
                restoring = false
            }
        }
    }

    LaunchedEffect(Unit) {
        graph.settings.hasSeenTrialOffer = true
        graph.diagnostics.record(FunnelStep.TRIAL_OFFER_REACHED)
        store.trackPaywallImpression("headache_onboarding_trial", oncePerSession = true)
    }

    Page(
        icon = Icons.Filled.AutoAwesome, tint = Brand.primary, title = "Get ahead of your headaches",
        primaryLabel = if (store.onboardingPlan != null) store.onboardingCtaLabel else "Start 7-day free trial",
        busy = purchasing, tag = "onboarding_trial_cta", showLegal = true, restoring = restoring, onRestore = ::restore,
        aboveButton = {
            TextAction(
                "Get Started", enabled = !purchasing, modifier = Modifier.testTag("onboarding_free"),
                onClick = {
                    graph.diagnostics.record(FunnelStep.FREE_VERSION_CHOSEN)
                    store.syncConversionAttributes()
                    finish()
                },
            )
            store.onboardingDisclosure?.let {
                Text(it, style = Type.caption2, color = palette.textTertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            }
            trialError?.let { Text(it, style = Type.caption, color = Tint.red, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().testTag("onboarding_trial_error")) }
        },
        onPrimary = {
            val plan = store.onboardingPlan
            val activity = context.findActivity()
            if (plan == null || activity == null) {
                nav.paywall("headache_onboarding_trial")
                finish()
                return@Page
            }
            trialError = null
            purchasing = true
            graph.diagnostics.record(FunnelStep.TRIAL_CTA_TAPPED)
            scope.launch {
                try {
                    when (store.purchase(activity, plan)) {
                        PurchaseOutcome.PURCHASED, PurchaseOutcome.PENDING -> {
                            graph.diagnostics.record(FunnelStep.PURCHASE_SUCCEEDED)
                            finish()
                        }
                        PurchaseOutcome.CANCELLED -> graph.diagnostics.record(FunnelStep.PURCHASE_CANCELLED)
                    }
                } catch (error: PurchaseException) {
                    graph.diagnostics.record(FunnelStep.PURCHASE_FAILED)
                    trialError = error.message ?: "Couldn't start your trial. Please try again."
                } finally {
                    purchasing = false
                    store.syncConversionAttributes()
                }
            }
        },
    ) {
        BodyText("Headache Pro turns your logs into a heads-up so you can plan around risky days.")
        Bullet(Icons.Filled.BarChart, "Spot your personal patterns across sleep, timing, and weather")
        Bullet(Icons.Filled.Speed, "Pressure and air-quality heads-up 12-24h before risky weather")
        Bullet(Icons.Filled.Shield, "All processing stays on your device")
    }
}

@Composable
private fun Page(
    icon: ImageVector,
    tint: Color,
    title: String,
    primaryLabel: String,
    onPrimary: () -> Unit,
    tag: String,
    busy: Boolean = false,
    showLegal: Boolean = false,
    restoring: Boolean = false,
    onRestore: (() -> Unit)? = null,
    aboveButton: @Composable ColumnScope.() -> Unit = {},
    body: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp).windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 16.dp)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(60.dp))
            Text(title, style = Type.title, color = palette.textPrimary)
            body()
        }
        Column(Modifier.fillMaxWidth().padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            aboveButton()
            PrimaryButton(primaryLabel, onPrimary, loading = busy, modifier = Modifier.testTag(tag), brush = androidx.compose.ui.graphics.SolidColor(Brand.primary))
            LegalFooter(Modifier.alpha(if (showLegal) 1f else 0f), enabled = showLegal, restoring = restoring, busy = busy, onRestore = onRestore)
        }
    }
}

@Composable
private fun LegalFooter(modifier: Modifier, enabled: Boolean, restoring: Boolean, busy: Boolean, onRestore: (() -> Unit)?) {
    val context = LocalContext.current
    Row(modifier.height(32.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        FooterLink("Terms of Use", enabled) { context.openUrl(Links.TERMS) }
        Text("·", style = Type.caption2, color = palette.textTertiary)
        FooterLink("Privacy Policy", enabled) { context.openUrl(Links.PRIVACY) }
        Text("·", style = Type.caption2, color = palette.textTertiary)
        FooterLink(if (restoring) "Restoring…" else "Restore", enabled && !restoring && !busy) { onRestore?.invoke() }
    }
}

@Composable
private fun FooterLink(label: String, enabled: Boolean, onClick: () -> Unit) {
    Text(
        label, style = Type.caption2, color = palette.textTertiary,
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).tappable(label, enabled = enabled, onClick = onClick).padding(horizontal = 4.dp, vertical = 6.dp),
    )
}

@Composable
private fun BodyText(text: String) {
    Text(text, style = Type.body, color = palette.textSecondary)
}

@Composable
private fun Bullet(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = Brand.primary, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(text, style = Type.body, color = palette.textSecondary, modifier = Modifier.weight(1f))
    }
}
