package com.jackwallner.headachelogger.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.DebugLaunchOptions
import com.jackwallner.headachelogger.billing.FunnelStep
import com.jackwallner.headachelogger.billing.PurchaseException
import com.jackwallner.headachelogger.billing.PurchaseOutcome
import com.jackwallner.headachelogger.model.Insight
import com.jackwallner.headachelogger.ui.screens.EditEventScreen
import com.jackwallner.headachelogger.ui.screens.HistoryScreen
import com.jackwallner.headachelogger.ui.screens.HomeScreen
import com.jackwallner.headachelogger.ui.screens.ImportIntroScreen
import com.jackwallner.headachelogger.ui.screens.InsightDetailScreen
import com.jackwallner.headachelogger.ui.screens.OnboardingScreen
import com.jackwallner.headachelogger.ui.screens.PatternsScreen
import com.jackwallner.headachelogger.ui.screens.PaywallScreen
import com.jackwallner.headachelogger.ui.screens.ProAlertsScreen
import com.jackwallner.headachelogger.ui.screens.ProIntroScreen
import com.jackwallner.headachelogger.ui.screens.QuizRetakeScreen
import com.jackwallner.headachelogger.ui.screens.QuizScreen
import com.jackwallner.headachelogger.ui.screens.SettingsScreen
import com.jackwallner.headachelogger.ui.screens.SeverityNotesScreen
import com.jackwallner.headachelogger.ui.screens.TrialOfferScreen
import com.jackwallner.headachelogger.ui.theme.Brand
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette
import com.jackwallner.headachelogger.ui.theme.tappable
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("No AppGraph provided") }
val LocalForeground = compositionLocalOf { 0 }
val LocalNav = staticCompositionLocalOf<Navigator> { error("No Navigator provided") }
val LocalPromos = staticCompositionLocalOf<PromoController> { error("No PromoController provided") }

/** Screens pushed over the tabs, the iOS sheets and navigation links. */
sealed interface Overlay {
    data class Paywall(val impression: String) : Overlay
    data object ProAlerts : Overlay
    data class InsightDetail(val insight: Insight, val totalEvents: Int) : Overlay
    data class EditEvent(val id: UUID) : Overlay
    data class SeverityNotes(val id: UUID) : Overlay
    data object ImportIntro : Overlay
    data object Quiz : Overlay
    data object QuizRetake : Overlay
}

enum class Tab(val label: String, val tag: String) {
    HOME("One Tap", "tab_home"),
    HISTORY("History", "tab_history"),
    PATTERNS("Patterns", "tab_patterns"),
    SETTINGS("Settings", "tab_settings"),
}

class Navigator {
    val stack = mutableStateListOf<Overlay>()
    var tab by mutableStateOf(Tab.HOME)

    fun push(overlay: Overlay) { stack.add(overlay) }
    fun pop() { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
    fun remove(overlay: Overlay) { stack.remove(overlay) }
    fun paywall(impression: String) = push(Overlay.Paywall(impression))
    fun select(tab: Tab) { this.tab = tab; stack.clear() }

    /** CSV import hand-off from the intro screen to History's confirmation alerts. */
    var pendingImportRows by mutableStateOf<List<Map<String, String>>?>(null)
    var importError by mutableStateOf<String?>(null)
}

/** The root-level promo sheets from `HeadacheLoggerRootContent`. */
sealed interface RootSheet {
    data object ProIntro : RootSheet
    data object TrialOffer : RootSheet
    data class Paywall(val impression: String) : RootSheet
}

/**
 * Ports the promo and review timing in `HeadacheLoggerApp.swift`: one promo sheet per
 * session, the trial offer after the first log (+4s) or for an existing user (+3s), the
 * Patterns second touch, the What's New sheet when no trial applies, and the review ask
 * 3.5s after a complete log when Home is clear.
 */
class PromoController(private val graph: AppGraph) {
    enum class Source { FIRST_LOG, EXISTING_USER, INSIGHTS }

    var sheet by mutableStateOf<RootSheet?>(null)
    var trialInFlight by mutableStateOf(false)
    var trialError by mutableStateOf<String?>(null)
    var pendingPaywallAfterTrial = false
    private var firstLogOfferShownThisSession = false
    private var source = Source.FIRST_LOG
    var reviewShownThisSession = false

    /** Bumped when a log or the details sheet finishes, the iOS `headachePositiveMomentForReview`. */
    var reviewTick by mutableIntStateOf(0)

    private val settings get() = graph.settings
    private val store get() = graph.store

    val hasTrialOffer: Boolean
        get() = store.onboardingPlan?.let(store::isEligibleForIntroOffer) == true

    private val promosAllowed: Boolean get() = !DebugLaunchOptions.suppressPromos

    fun dismissSheet() {
        trialInFlight = false
        trialError = null
        if (pendingPaywallAfterTrial) {
            pendingPaywallAfterTrial = false
            sheet = RootSheet.Paywall("headache_trial_sheet")
        } else {
            sheet = null
        }
    }

    fun proIntroCandidate(): Boolean =
        promosAllowed && settings.hasCompletedOnboarding && !settings.hasSeenProIntro && !store.isPro && !hasTrialOffer

    fun showProIntroIfReady(active: Boolean) {
        if (!active || !proIntroCandidate()) return
        if (!store.hasResolvedEntitlements || sheet != null || store.hasRecentOrActiveProSignal) return
        if (graph.capture.proPromptShownThisSession) return
        graph.capture.proPromptShownThisSession = true
        settings.hasSeenProIntro = true
        sheet = RootSheet.ProIntro
    }

    fun firstLogCandidate(): Boolean =
        promosAllowed && settings.hasCompletedOnboarding && !store.isPro && !settings.hasSeenTrialOffer && hasTrialOffer

    fun existingUserCandidate(): Boolean = firstLogCandidate() && graph.events.events.isNotEmpty()

    fun onPatternsAppear(active: Boolean) {
        if (!promosAllowed || !settings.hasCompletedOnboarding || store.isPro || settings.hasSeenTrialOffer) return
        if (settings.hasSeenInsightsTrialOffer || firstLogOfferShownThisSession || !hasTrialOffer || sheet != null) return
        presentTrialOffer(Source.INSIGHTS, active)
    }

    fun presentTrialOffer(from: Source, active: Boolean) {
        if (!store.hasResolvedEntitlements || !active || sheet != null || store.isPro) return
        if (store.hasRecentOrActiveProSignal || !hasTrialOffer || graph.capture.proPromptShownThisSession) return
        when (from) {
            Source.FIRST_LOG, Source.EXISTING_USER -> if (settings.hasSeenTrialOffer) return
            Source.INSIGHTS -> if (settings.hasSeenInsightsTrialOffer) return
        }
        trialError = null
        trialInFlight = false
        source = from
        if (from != Source.INSIGHTS) firstLogOfferShownThisSession = true
        graph.capture.proPromptShownThisSession = true
        settings.hasSeenTrialOffer = true
        if (from == Source.INSIGHTS) settings.hasSeenInsightsTrialOffer = true
        sheet = RootSheet.TrialOffer
    }

    fun seeAllPlans() {
        pendingPaywallAfterTrial = true
        dismissSheet()
    }

    suspend fun startDirectTrial(activity: android.app.Activity?) {
        val plan = store.onboardingPlan
        if (plan == null || activity == null || !hasTrialOffer) {
            seeAllPlans()
            return
        }
        trialError = null
        trialInFlight = true
        try {
            when (store.purchase(activity, plan)) {
                PurchaseOutcome.PURCHASED, PurchaseOutcome.PENDING -> {
                    settings.hasSeenTrialOffer = true
                    dismissSheet()
                }
                PurchaseOutcome.CANCELLED -> trialError = null
            }
        } catch (_: PurchaseException) {
            trialError = "Couldn't start your trial. Please try again."
        } finally {
            trialInFlight = false
        }
    }

    fun onProUnlocked() {
        settings.hasSeenProIntro = true
        settings.hasSeenTrialOffer = true
        if (sheet == RootSheet.ProIntro || sheet == RootSheet.TrialOffer) sheet = null
    }

    @Suppress("unused")
    private fun record(step: FunnelStep) = graph.diagnostics.record(step)
}

/** Onboarding until setup completes, then the tab host. A branch, never a cover. */
@Composable
fun RootScreen(graph: AppGraph) {
    val nav = remember { Navigator() }
    val promos = remember(graph) { PromoController(graph) }
    CompositionLocalProvider(LocalNav provides nav, LocalPromos provides promos) {
        AnimatedContent(graph.settings.hasCompletedOnboarding, transitionSpec = { fadeIn(tween(350)) togetherWith fadeOut(tween(350)) }, label = "root") { done ->
            if (done) MainShell(graph, nav, promos) else OnboardingScreen(graph)
        }
    }
}

@Composable
private fun MainShell(graph: AppGraph, nav: Navigator, promos: PromoController) {
    val store = graph.store
    val foreground = LocalForeground.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val context = LocalContext.current
    fun isActive() = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)

    LaunchedEffect(Unit) {
        DebugLaunchOptions.tab?.let { name -> Tab.entries.firstOrNull { it.name.equals(name, true) }?.let { nav.tab = it } }
        when (DebugLaunchOptions.sheet) {
            "paywall" -> nav.paywall("headache_settings_sheet")
            "alerts" -> nav.push(Overlay.ProAlerts)
            "trial" -> promos.sheet = RootSheet.TrialOffer
            "prointro" -> promos.sheet = RootSheet.ProIntro
            "details" -> graph.events.events.firstOrNull()?.let { nav.push(Overlay.SeverityNotes(it.id)) }
            "quiz" -> nav.push(Overlay.Quiz)
        }
    }

    // Foreground hooks: widget enrichment, pattern alerts, daily records and the first promo checks.
    LaunchedEffect(foreground) {
        graph.capture.enrichPendingCapturesIfNeeded()
        graph.schedulePatternAlerts()
        graph.maintainDailyRecords()
        graph.updateForecastSchedule()
        val epoch = foreground
        if (promos.proIntroCandidate()) {
            delay(800)
            if (epoch == foreground) promos.showProIntroIfReady(isActive())
        }
        if (promos.existingUserCandidate()) {
            delay(3_000)
            promos.presentTrialOffer(PromoController.Source.EXISTING_USER, isActive())
        }
    }
    LaunchedEffect(store.hasResolvedEntitlements, store.plans.size, store.introEligibilityResolved) {
        if (!store.hasResolvedEntitlements) return@LaunchedEffect
        promos.showProIntroIfReady(isActive())
        if (promos.existingUserCandidate()) {
            delay(3_000)
            promos.presentTrialOffer(PromoController.Source.EXISTING_USER, isActive())
        }
    }
    LaunchedEffect(store.isPro) {
        graph.updateForecastSchedule()
        if (store.isPro) promos.onProUnlocked()
    }
    LaunchedEffect(Unit) {
        var previous = graph.events.events.size
        snapshotFlow { graph.events.events.size }.collect { count ->
            if (previous == 0 && count >= 1 && promos.firstLogCandidate()) {
                launch {
                    delay(4_000)
                    promos.presentTrialOffer(PromoController.Source.FIRST_LOG, isActive())
                }
            }
            previous = count
        }
    }
    ReviewHost(graph, nav, promos)

    val canGoBack = nav.stack.isNotEmpty()
    BackHandler(enabled = canGoBack && promos.sheet == null) { nav.pop() }
    BackHandler(enabled = promos.sheet != null && !promos.trialInFlight) { promos.dismissSheet() }

    Box(Modifier.fillMaxSize().background(palette.background)) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) {
                when (nav.tab) {
                    Tab.HOME -> HomeScreen(graph)
                    Tab.HISTORY -> HistoryScreen(graph)
                    Tab.PATTERNS -> PatternsScreen(graph)
                    Tab.SETTINGS -> SettingsScreen(graph)
                }
            }
            TabBar(nav)
        }
        OverlayHost(graph, nav)
        SheetHost(graph, promos, context)
    }
}

@Composable
private fun OverlayHost(graph: AppGraph, nav: Navigator) {
    val top = nav.stack.lastOrNull()
    AnimatedVisibility(
        visible = top != null,
        enter = slideInVertically(tween(260)) { it / 6 } + fadeIn(tween(220)),
        exit = slideOutVertically(tween(200)) { it / 6 } + fadeOut(tween(160)),
    ) {
        Box(Modifier.fillMaxSize().background(palette.background)) {
            when (val overlay = top ?: return@Box) {
                is Overlay.Paywall -> PaywallScreen(graph, overlay.impression, onClose = { nav.remove(overlay) })
                Overlay.ProAlerts -> ProAlertsScreen(graph, onClose = { nav.remove(overlay) })
                is Overlay.InsightDetail -> InsightDetailScreen(overlay.insight, overlay.totalEvents, onClose = { nav.remove(overlay) })
                is Overlay.EditEvent -> EditEventScreen(graph, overlay.id, onClose = { nav.remove(overlay) })
                is Overlay.SeverityNotes -> SeverityNotesScreen(graph, overlay.id, onClose = { nav.remove(overlay) })
                Overlay.ImportIntro -> ImportIntroScreen(onClose = { nav.remove(overlay) })
                Overlay.Quiz -> QuizScreen(graph, onClose = { nav.remove(overlay) })
                Overlay.QuizRetake -> QuizRetakeScreen(graph, onClose = { nav.remove(overlay) })
            }
        }
    }
}

@Composable
private fun SheetHost(graph: AppGraph, promos: PromoController, context: android.content.Context) {
    val scope = rememberCoroutineScope()
    AnimatedVisibility(
        visible = promos.sheet != null,
        enter = slideInVertically(tween(300)) { it / 4 } + fadeIn(tween(240)),
        exit = slideOutVertically(tween(220)) { it / 4 } + fadeOut(tween(180)),
    ) {
        Box(Modifier.fillMaxSize().background(palette.background)) {
            when (val sheet = promos.sheet ?: return@Box) {
                RootSheet.ProIntro -> ProIntroScreen(
                    onSeePlans = { promos.sheet = RootSheet.Paywall("headache_pro_intro_sheet") },
                    onClose = { graph.settings.hasSeenProIntro = true; promos.dismissSheet() },
                )
                RootSheet.TrialOffer -> TrialOfferScreen(
                    graph = graph,
                    isPurchasing = promos.trialInFlight,
                    errorMessage = promos.trialError,
                    onStartTrial = { scope.launch { promos.startDirectTrial(context.findActivity()) } },
                    onSeeAllPlans = promos::seeAllPlans,
                    onDismiss = promos::dismissSheet,
                )
                is RootSheet.Paywall -> PaywallScreen(graph, sheet.impression, onClose = promos::dismissSheet)
            }
        }
    }
}

/** Asks for a Play review 3.5s after a complete log when Home is clear; never from a button, no question first. */
@Composable
private fun ReviewHost(graph: AppGraph, nav: Navigator, promos: PromoController) {
    val context = LocalContext.current
    val foreground = LocalForeground.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    fun homeClear() = graph.settings.hasCompletedOnboarding && nav.tab == Tab.HOME && nav.stack.isEmpty() &&
        promos.sheet == null && !promos.pendingPaywallAfterTrial && !graph.capture.proPromptShownThisSession
    fun eligible() = !promos.reviewShownThisSession && graph.review.shouldRequestAfterPositiveMoment(graph.settings.hasCompletedOnboarding)
    LaunchedEffect(graph.capture.positiveMomentTick, promos.reviewTick) {
        if (graph.capture.positiveMomentTick == 0 && promos.reviewTick == 0) return@LaunchedEffect
        if (!eligible() || !homeClear()) return@LaunchedEffect
        val epoch = foreground
        delay(3_500)
        if (epoch != foreground || !lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return@LaunchedEffect
        if (!homeClear() || !eligible()) return@LaunchedEffect
        promos.reviewShownThisSession = true
        graph.review.markShown()
        context.launchPlayReview()
    }
}

@Composable
private fun TabBar(nav: Navigator) {
    Column(Modifier.fillMaxWidth().background(palette.card)) {
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(palette.separator))
        Row(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars).height(58.dp)) {
            Tab.entries.forEach { tab ->
                val selected = nav.tab == tab
                val tint = if (selected) Brand.primary else palette.textSecondary
                val icon = when (tab) {
                    Tab.HOME -> Icons.Filled.Psychology
                    Tab.HISTORY -> Icons.Filled.History
                    Tab.PATTERNS -> Icons.Filled.BarChart
                    Tab.SETTINGS -> Icons.Filled.Tune
                }
                Column(
                    Modifier.weight(1f).fillMaxSize().testTag(tab.tag).tappable("${tab.label} tab", Role.Tab) { nav.select(tab) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(icon, null, tint = tint, modifier = Modifier.size(24.dp))
                    Text(tab.label, style = Type.of(11.sp, if (selected) FontWeight.SemiBold else FontWeight.Medium), color = tint)
                }
            }
        }
    }
}
