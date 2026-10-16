package com.jackwallner.headachelogger.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.billing.ConversionCopy
import com.jackwallner.headachelogger.billing.PackageKind
import com.jackwallner.headachelogger.billing.Plan
import com.jackwallner.headachelogger.billing.PurchaseException
import com.jackwallner.headachelogger.billing.PurchaseOutcome
import com.jackwallner.headachelogger.billing.capitalizeWords
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

private val paywallFeatures = listOf(
    Icons.Filled.NotificationsActive to "12-24h warnings: heads-up before pressure and AQI shift",
    Icons.Filled.BarChart to "Personal triggers: patterns from your sleep and weather",
    Icons.Filled.MonitorHeart to "Daily risk forecast: tomorrow's score from your own data",
)

/** Port of `PaywallView`: yearly, monthly and lifetime from the Play offering. */
@Composable
fun PaywallScreen(graph: AppGraph, impression: String, onClose: () -> Unit) {
    val store = graph.store
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selectedId by remember { mutableStateOf<String?>(null) }
    var isPurchasing by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    val plans = store.plans
    val selected = plans.firstOrNull { it.packageId == selectedId }

    LaunchedEffect(impression) { store.trackPaywallImpression(impression) }
    LaunchedEffect(Unit) { if (store.plans.isEmpty()) store.fetchProducts() }
    LaunchedEffect(plans.size) {
        if (selectedId == null && plans.isNotEmpty()) selectedId = (store.yearlyPlan ?: plans.first()).packageId
    }
    LaunchedEffect(store.isPro) { if (store.isPro) onClose() }

    fun restore() {
        errorMessage = null
        restoreMessage = null
        isRestoring = true
        scope.launch {
            store.restorePurchases()
            isRestoring = false
            if (!store.isPro) restoreMessage = store.lastError ?: ConversionCopy.NO_PURCHASE_FOUND
        }
    }
    fun purchase() {
        val plan = selected ?: return
        val activity = context.findActivity() ?: return
        errorMessage = null
        restoreMessage = null
        isPurchasing = true
        scope.launch {
            try {
                when (store.purchase(activity, plan)) {
                    PurchaseOutcome.PURCHASED -> Unit
                    PurchaseOutcome.PENDING -> errorMessage = ConversionCopy.PURCHASE_PENDING
                    PurchaseOutcome.CANCELLED -> errorMessage = ConversionCopy.PURCHASE_CANCELLED
                }
            } catch (error: PurchaseException) {
                errorMessage = error.message ?: ConversionCopy.PURCHASE_FAILED
            } finally {
                isPurchasing = false
            }
        }
    }

    Box(Modifier.fillMaxSize().background(palette.background).testTag("paywall")) {
        Column(
            Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars).windowInsetsPadding(WindowInsets.navigationBars)
                .verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(top = 44.dp, bottom = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            when {
                store.isLoadingProducts && plans.isEmpty() -> {
                    Spacer(Modifier.height(160.dp))
                    CircularProgressIndicator(color = Brand.primary, modifier = Modifier.size(28.dp))
                    Text("Loading plans…", style = Type.footnote, color = palette.textSecondary)
                    Spacer(Modifier.height(160.dp))
                }
                plans.isEmpty() -> {
                    Spacer(Modifier.height(120.dp))
                    Icon(Icons.Filled.WifiOff, null, tint = palette.textTertiary, modifier = Modifier.size(40.dp))
                    Text("Couldn't Load Plans", style = Type.headline, color = palette.textPrimary)
                    Text(
                        store.lastError ?: "Check your connection and try again.", style = Type.subhead, color = palette.textSecondary,
                        textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 10.dp),
                    )
                    TextAction("Try Again", { scope.launch { store.fetchProducts() } }, color = Brand.primary)
                    Spacer(Modifier.height(120.dp))
                }
                else -> {
                    PaywallHeader()
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        paywallFeatures.forEach { (icon, title) ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(icon, null, tint = Brand.primary, modifier = Modifier.width(24.dp).size(18.dp))
                                Spacer(Modifier.width(12.dp))
                                Text(title, style = Type.subhead, color = palette.textPrimary)
                            }
                        }
                    }
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        plans.forEach { plan ->
                            PlanCard(
                                plan = plan,
                                isSelected = plan.packageId == selectedId,
                                showsTrialBadge = store.isEligibleForIntroOffer(plan),
                                savingsPercent = if (plan.kind == PackageKind.YEARLY) store.annualSavingsPercent else null,
                            ) { selectedId = plan.packageId }
                        }
                    }
                    Spacer(Modifier.height(4.dp))
                    val eligible = selected?.let(store::isEligibleForIntroOffer) == true
                    val cta = selected?.let {
                        ConversionCopy.paywallCtaTitle(it.kind == PackageKind.LIFETIME, it.trial != null, store.introEligibilityResolved, eligible)
                    } ?: "Continue"
                    PrimaryButton(
                        cta, ::purchase, enabled = selected != null && !isPurchasing, loading = isPurchasing,
                        shape = CircleShape, modifier = Modifier.testTag("paywallCta"),
                    )
                    val trust = when {
                        selected == null -> null
                        selected.kind == PackageKind.LIFETIME -> "One-time payment. No subscription."
                        eligible -> "No charge today."
                        else -> null
                    }
                    if (trust != null) Text(trust, style = Type.footnote.copy(fontWeight = FontWeight.Medium), color = palette.textSecondary, textAlign = TextAlign.Center)
                    disclosure(selected, eligible)?.let {
                        Text(it, style = Type.caption, color = palette.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                    }
                    errorMessage?.let { Text(it, style = Type.footnote, color = Tint.red, textAlign = TextAlign.Center) }
                    restoreMessage?.let { Text(it, style = Type.footnote, color = palette.textSecondary, textAlign = TextAlign.Center) }
                }
            }
            LegalFooter(isRestoring, isPurchasing, ::restore)
        }
        Icon(
            Icons.Filled.Cancel, contentDescription = null, tint = palette.textTertiary,
            modifier = Modifier.align(Alignment.TopEnd).windowInsetsPadding(WindowInsets.statusBars).padding(8.dp).clip(CircleShape)
                .tappable("Close", onClick = onClose).padding(8.dp).size(28.dp).testTag("paywallClose"),
        )
    }
}

private fun disclosure(plan: Plan?, eligible: Boolean): String? {
    plan ?: return null
    if (plan.kind == PackageKind.LIFETIME) return "${plan.priceLabel}. One-time purchase. Lifetime access, no subscription."
    return ConversionCopy.disclosure(plan.introOfferLabel, plan.priceLabel, eligible)
}

@Composable
private fun PaywallHeader() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(52.dp).clip(CircleShape).background(Brand.primary.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.NotificationsActive, null, tint = Brand.primary, modifier = Modifier.size(26.dp))
        }
        Text("Know before the headache hits", style = Type.title3.copy(fontWeight = FontWeight.Bold), color = palette.textPrimary, textAlign = TextAlign.Center)
        Text(
            "Unlock every Headache Pro feature. Private, on-device, no accounts.",
            style = Type.footnote, color = palette.textSecondary, textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun PlanCard(plan: Plan, isSelected: Boolean, showsTrialBadge: Boolean, savingsPercent: Int?, onTap: () -> Unit) {
    val isRecommended = plan.kind == PackageKind.YEARLY
    val shape = RoundedCornerShape(14.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(palette.card)
            .border(BorderStroke(2.dp, if (isSelected) Brand.primary else Color.Transparent), shape)
            .tappable("${plan.displayName}, ${plan.priceLabel}", role = Role.RadioButton, onClick = onTap)
            .testTag("plan_${plan.kind.name.lowercase()}")
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(22.dp).border(2.dp, if (isSelected) Brand.primary else palette.textSecondary.copy(alpha = 0.35f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (isSelected) Box(Modifier.size(12.dp).clip(CircleShape).background(Brand.primary))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(plan.displayName, style = Type.subheadBold.copy(fontWeight = FontWeight.Bold), color = palette.textPrimary)
                if (isRecommended) {
                    Pill("BEST VALUE", Color.White, Brand.primary)
                } else if (savingsPercent != null) {
                    Pill("SAVE $savingsPercent%", Brand.primary, Brand.primary.copy(alpha = 0.14f))
                }
            }
            val trial = plan.introOfferLabel.takeIf { showsTrialBadge }
            val sub = buildList {
                when {
                    trial != null -> add(trial.capitalizeWords() to Brand.primary)
                    plan.kind == PackageKind.LIFETIME -> add("One-time purchase" to null)
                }
                if (isRecommended && savingsPercent != null) add("Save $savingsPercent%" to null)
            }
            if (sub.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    sub.forEachIndexed { index, (text, color) ->
                        if (index > 0) Text("·", style = Type.caption2, color = palette.textTertiary)
                        Text(text, style = Type.caption2.copy(fontWeight = FontWeight.SemiBold), color = color ?: palette.textSecondary, maxLines = 1)
                    }
                }
            }
        }
        Spacer(Modifier.width(8.dp))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(plan.priceLabel, style = Type.subheadBold, color = palette.textPrimary, maxLines = 1)
            plan.perMonthLabel?.let { Text(it, style = Type.caption2.copy(fontWeight = FontWeight.Medium), color = palette.textSecondary, maxLines = 1) }
        }
    }
}

@Composable
private fun Pill(text: String, fg: Color, bg: Color) {
    Text(
        text, color = fg, fontSize = 9.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1,
        modifier = Modifier.clip(CircleShape).background(bg).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

@Composable
private fun LegalFooter(isRestoring: Boolean, isPurchasing: Boolean, onRestore: () -> Unit) {
    val context = LocalContext.current
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        TextAction(if (isRestoring) "Restoring…" else "Restore Purchases", onRestore, enabled = !isRestoring && !isPurchasing)
        Row(verticalAlignment = Alignment.CenterVertically) {
            SmallLink("Terms") { context.openUrl(Links.TERMS) }
            Text("·", style = Type.caption2, color = palette.textTertiary)
            SmallLink("Privacy Policy") { context.openUrl(Links.PRIVACY) }
        }
    }
}

@Composable
private fun SmallLink(text: String, onClick: () -> Unit) {
    Text(
        text, style = Type.caption, color = palette.textSecondary,
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).tappable(text, onClick = onClick).heightIn(min = 32.dp).padding(horizontal = 8.dp, vertical = 8.dp),
    )
}

/** Port of `ProIntroSheet`, shown once to users who finished onboarding before Pro existed. */
@Composable
fun ProIntroScreen(onSeePlans: () -> Unit, onClose: () -> Unit) {
    Column(Modifier.fillMaxSize().background(palette.background).testTag("proIntro")) {
        TopBar("What's New", trailing = "Close" to onClose)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Icon(Icons.Filled.NotificationsActive, null, tint = Brand.primary, modifier = Modifier.size(48.dp))
            Text("Headache Pro is here", style = Type.title, color = palette.textPrimary)
            Text(
                "Forecast checks stay quiet until your logs support a personal pressure, AQI, or timing pattern. When an alert fires, it explains the matching trigger and personal lift.",
                style = Type.body, color = palette.textSecondary,
            )
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                ProBullet(Icons.Filled.Speed, "Pressure-drop and AQI alerts based on your own logs")
                ProBullet(Icons.Filled.BarChart, "Personalized patterns from your existing logs")
                ProBullet(Icons.Filled.Shield, "All processing stays on-device")
            }
        }
        Column(
            Modifier.fillMaxWidth().background(palette.card).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            PrimaryButton("See Pro plans", onSeePlans, brush = androidx.compose.ui.graphics.SolidColor(Brand.primary))
            TextAction("Not now", onClose, style = Type.footnote)
        }
    }
}

@Composable
private fun ProBullet(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = Brand.primary, modifier = Modifier.width(26.dp).size(24.dp))
        Spacer(Modifier.width(12.dp))
        Text(text, style = Type.callout, color = palette.textPrimary)
    }
}

/** Port of `TrialOfferSheet`: one tap starts the monthly plan's free trial in Google Play. */
@Composable
fun TrialOfferScreen(
    graph: AppGraph,
    isPurchasing: Boolean,
    errorMessage: String?,
    onStartTrial: () -> Unit,
    onSeeAllPlans: () -> Unit,
    onDismiss: () -> Unit,
) {
    val store = graph.store
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isRestoring by remember { mutableStateOf(false) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    val plan = store.onboardingPlan
    val direct = plan != null && store.isEligibleForIntroOffer(plan)
    val trialDays = plan?.trial?.days
    val period = trialDays?.let { if (it == 1) "1 day" else "$it days" }
    val headline = if (period != null) "$period of Pro, free." else "Try Headache Pro free."
    val sub = if (period != null) "Find your triggers and get ahead of risky weather. Free until your trial ends."
    else "Find your triggers and get ahead of risky weather, free for eligible new subscribers."
    val billing = when {
        direct && period != null -> "Free for $period, then ${plan!!.priceLabel}. Auto-renews; cancel anytime in Google Play at least 24h before it ends."
        direct -> "Then ${plan!!.priceLabel}. Auto-renews; cancel anytime in Google Play at least 24h before it ends."
        else -> "Billed through Google Play. No charge during the trial."
    }

    LaunchedEffect(Unit) { store.trackPaywallImpression("headache_trial_offer_sheet", oncePerSession = true) }

    Column(
        Modifier.fillMaxSize().background(palette.background).windowInsetsPadding(WindowInsets.statusBars).windowInsetsPadding(WindowInsets.navigationBars)
            .verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(top = 8.dp, bottom = 28.dp).testTag("trialOffer"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Box(Modifier.padding(top = 18.dp).size(76.dp).clip(CircleShape).background(Brand.gradient), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.AutoAwesome, null, tint = Color.White, modifier = Modifier.size(32.dp))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(headline, style = Type.title, color = palette.textPrimary, textAlign = TextAlign.Center)
            Text(sub, style = Type.subhead, color = palette.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp))
        }
        Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            TrialBullet(Icons.Filled.BarChart, Tint.indigo, "Your personal patterns", "Sleep, timing, pressure, and weather from your own logs.")
            TrialBullet(Icons.Filled.Speed, Tint.orange, "Pressure & AQI alerts", "A heads-up 12-24h before risky weather hits.")
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Shield, null, tint = palette.textSecondary, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(6.dp))
            Text("All on-device. Your logs never leave your phone.", style = Type.caption, color = palette.textSecondary)
        }
        errorMessage?.let { Text(it, style = Type.footnote, color = Tint.red, textAlign = TextAlign.Center) }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            PrimaryButton(
                ConversionCopy.TRIAL_CTA_TITLE, { if (direct) onStartTrial() else onSeeAllPlans() },
                loading = isPurchasing, shape = CircleShape, modifier = Modifier.testTag("trialCta"),
            )
            Text(billing, style = Type.caption2, color = palette.textTertiary, textAlign = TextAlign.Center)
            if (direct) TextAction("See all plans", onSeeAllPlans, color = Brand.primary, enabled = !isPurchasing)
            TextAction("Not now", onDismiss, enabled = !isPurchasing)
            TextAction(if (isRestoring) "Restoring…" else "Restore Purchases", {
                restoreMessage = null
                isRestoring = true
                scope.launch {
                    store.restorePurchases()
                    isRestoring = false
                    if (!store.isPro) restoreMessage = store.lastError ?: ConversionCopy.NO_PURCHASE_FOUND
                }
            }, enabled = !isRestoring && !isPurchasing)
            restoreMessage?.let { Text(it, style = Type.caption, color = palette.textSecondary, textAlign = TextAlign.Center) }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            SmallLink("Terms") { context.openUrl(Links.TERMS) }
            Text("·", style = Type.caption2, color = palette.textTertiary)
            SmallLink("Privacy Policy") { context.openUrl(Links.PRIVACY) }
        }
    }
}

@Composable
private fun TrialBullet(icon: ImageVector, tint: Color, title: String, detail: String) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(palette.card).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(tint.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Type.subheadBold, color = palette.textPrimary)
            Text(detail, style = Type.footnote, color = palette.textSecondary)
        }
    }
}
