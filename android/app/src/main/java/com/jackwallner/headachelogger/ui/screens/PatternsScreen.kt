package com.jackwallner.headachelogger.ui.screens

import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LocationOff
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.capture.Http
import com.jackwallner.headachelogger.model.Breakdown
import com.jackwallner.headachelogger.model.DailyRecord
import com.jackwallner.headachelogger.model.Insight
import com.jackwallner.headachelogger.model.InsightCategory
import com.jackwallner.headachelogger.model.InsightSummary
import com.jackwallner.headachelogger.model.InsightsEngine
import com.jackwallner.headachelogger.model.OpenMeteo
import com.jackwallner.headachelogger.model.ProactiveAlertsEngine
import com.jackwallner.headachelogger.model.RiskForecast
import com.jackwallner.headachelogger.model.RiskLevel
import com.jackwallner.headachelogger.data.QuizStore
import com.jackwallner.headachelogger.ui.Format
import com.jackwallner.headachelogger.ui.LocalNav
import com.jackwallner.headachelogger.ui.LocalPromos
import com.jackwallner.headachelogger.ui.Overlay
import com.jackwallner.headachelogger.ui.Symbols
import com.jackwallner.headachelogger.ui.theme.Brand
import com.jackwallner.headachelogger.ui.theme.LargeTitle
import com.jackwallner.headachelogger.ui.theme.PrimaryButton
import com.jackwallner.headachelogger.ui.theme.Tint
import com.jackwallner.headachelogger.ui.theme.TopBar
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette
import com.jackwallner.headachelogger.ui.theme.tappable
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.launch

/** `QuizInsightPriority`: the quiz answers float matching insight categories to the top. */
object QuizInsightPriority {
    fun categories(quiz: QuizStore): List<InsightCategory> {
        val out = mutableListOf<InsightCategory>()
        fun add(category: InsightCategory) { if (category !in out) out += category }
        when (quiz.answer("trigger_weather")) {
            "Pressure drops" -> add(InsightCategory.PRESSURE)
            "Heat", "Cold" -> add(InsightCategory.WEATHER)
        }
        if (quiz.answer("trigger_sleep") == "Yes") add(InsightCategory.SLEEP)
        quiz.answer("time_of_day")?.let { if (it != "No pattern") add(InsightCategory.TIME) }
        quiz.answer("severity")?.let { if (it.startsWith("Extreme") || it.startsWith("Medium")) add(InsightCategory.SEVERITY) }
        return out
    }

    fun prioritize(summary: InsightSummary, categories: List<InsightCategory>): InsightSummary {
        if (categories.isEmpty()) return summary
        val rank = categories.withIndex().associate { it.value to it.index }
        val sorted = summary.insights.withIndex().sortedWith(compareBy({ rank[it.value.category] ?: Int.MAX_VALUE }, { it.index })).map { it.value }
        return summary.copy(insights = sorted)
    }
}

/** Port of `InsightsView`: Pro patterns, today's risk and Proactive Alerts, or the locked teaser. */
@Composable
fun PatternsScreen(graph: AppGraph) {
    val store = graph.store
    val nav = LocalNav.current
    val promos = LocalPromos.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val events = graph.events.events
    var records by remember { mutableStateOf<List<DailyRecord>>(emptyList()) }
    var risk by remember { mutableStateOf<RiskForecast?>(null) }
    var riskLoading by remember { mutableStateOf(false) }
    var locationMissing by remember { mutableStateOf(false) }
    var notedMoment by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val summary = QuizInsightPriority.prioritize(
        InsightsEngine.summarize(events, records, graph.settings.useCelsius),
        QuizInsightPriority.categories(graph.quiz),
    )

    suspend fun refreshRisk(force: Boolean = false) {
        if (!store.isPro) return
        val current = risk
        if (!force && current != null && Duration.between(current.evaluatedAt, Instant.now()).toMinutes() < 30) return
        locationMissing = false
        riskLoading = true
        val coord = graph.settings.cachedLocation
        if (coord == null) {
            locationMissing = true
            risk = null
            riskLoading = false
            return
        }
        val now = Instant.now()
        val weather = Http.get(OpenMeteo.forecastPressureUrl(coord.latitude, coord.longitude), 10_000)
        val air = Http.get(OpenMeteo.forecastAirUrl(coord.latitude, coord.longitude), 10_000)
        val forecast = weather?.let { OpenMeteo.parseForecastWindow(it, air, now) }
        val sleep = graph.health.sleepHoursForNightBefore(LocalDate.now())
        risk = ProactiveAlertsEngine.dailyRiskForecast(forecast, sleep, graph.settings.personalAlertProfile)
        riskLoading = false
    }

    LaunchedEffect(Unit) { promos.onPatternsAppear(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    LaunchedEffect(events.size, store.isPro) {
        records = graph.backfillSleep()
        refreshRisk()
        if (!notedMoment && store.isPro && events.size >= InsightsEngine.MINIMUM_SAMPLE_SIZE && summary.insights.isNotEmpty()) {
            notedMoment = true
            graph.review.recordPositiveMoment()
        }
    }

    Column(Modifier.fillMaxSize().background(palette.background)) {
        LargeTitle("Patterns")
        if (store.isPro) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
                Column(Modifier.padding(horizontal = 4.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${summary.totalEvents} headache${if (summary.totalEvents == 1) "" else "s"} logged", style = Type.title2, color = palette.textPrimary)
                    val first = summary.firstDate
                    val last = summary.lastDate
                    if (first != null && last != null) {
                        Text("${Format.mediumDate(first)} to ${Format.mediumDate(last)}", style = Type.subhead, color = palette.textSecondary)
                    }
                }
                PatternsSection(events.size, summary) { nav.push(Overlay.InsightDetail(it, summary.totalEvents)) }
                Header("Today's risk")
                RiskCard(risk, riskLoading, locationMissing) { scope.launch { refreshRisk(force = true) } }
                Footer("Risk combines tomorrow's forecast pressure and air quality with last night's sleep. It's a heads-up, not a prediction.")
                Header("Get ahead of triggers")
                AlertsCard(graph.settings.alertsEnabled) { nav.push(Overlay.ProAlerts) }
                Footer("Proactive Alerts use the same forecast signals shown here to give you a 12-24 hour heads-up before risky weather.")
            }
        } else {
            LockedTeaser(events.size, summary, Modifier.weight(1f)) { nav.paywall("headache_insights_sheet") }
        }
    }
}

@Composable
private fun Header(text: String) {
    Text(text.uppercase(), style = Type.footnote, color = palette.textSecondary, modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 6.dp))
}

@Composable
private fun Footer(text: String) {
    Text(text, style = Type.footnote, color = palette.textSecondary, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
}

@Composable
private fun PatternsSection(count: Int, summary: InsightSummary, onOpen: (Insight) -> Unit) {
    Header("Your patterns")
    val box = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(palette.card)
    when {
        count < InsightsEngine.MINIMUM_SAMPLE_SIZE -> Column(box.padding(16.dp)) {
            LearningState(
                "Personalized patterns warming up",
                "Personalized patterns unlock after ${InsightsEngine.MINIMUM_SAMPLE_SIZE} logs. You have $count.",
                count / InsightsEngine.MINIMUM_SAMPLE_SIZE.toFloat(),
            )
        }
        summary.insights.isEmpty() -> Column(box.padding(16.dp)) {
            LearningState(
                "Still watching for a clear pattern",
                "$count headaches logged so far. Keep using the one-tap button and Pro will surface a pattern when a signal stands out.",
                null,
            )
        }
        else -> {
            Column(box) {
                summary.insights.forEachIndexed { index, insight ->
                    if (index > 0) Box(Modifier.padding(start = 60.dp).fillMaxWidth().height(0.5.dp).background(palette.separator))
                    Row(
                        Modifier.fillMaxWidth().testTag("insight_${insight.id}").tappable(insight.title) { onOpen(insight) }.padding(16.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Icon(Symbols.of(insight.icon), null, tint = Brand.primary, modifier = Modifier.size(28.dp))
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(insight.title, style = Type.headline, color = palette.textPrimary)
                            Text(insight.detail, style = Type.subhead, color = palette.textSecondary)
                        }
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.textTertiary)
                    }
                }
            }
            Footer("Patterns are computed locally from your logged events. They describe your data, not a clinical diagnosis. Share with a doctor if you're trying to identify triggers.")
        }
    }
}

@Composable
private fun LearningState(title: String, detail: String, progress: Float?) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.AutoAwesome, null, tint = Brand.primary, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(title, style = Type.headline, color = Brand.primary)
        }
        Text(detail, style = Type.subhead, color = palette.textSecondary)
        if (progress != null) {
            LinearProgressIndicator(
                progress = { progress.coerceAtMost(1f) }, modifier = Modifier.fillMaxWidth(),
                color = Brand.primary, trackColor = palette.separator.copy(alpha = 0.3f), drawStopIndicator = {},
            )
        }
    }
}

private val RiskLevel.displayName get() = when (this) { RiskLevel.LOW -> "Low"; RiskLevel.MODERATE -> "Moderate"; RiskLevel.HIGH -> "High" }
private val RiskLevel.tint get() = when (this) { RiskLevel.LOW -> Tint.green; RiskLevel.MODERATE -> Tint.orange; RiskLevel.HIGH -> Tint.red }

@Composable
fun RiskCard(forecast: RiskForecast?, loading: Boolean, locationMissing: Boolean, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(palette.card).padding(14.dp).testTag("riskCard"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        when {
            forecast != null -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(forecast.level.displayName, style = Type.title2, color = forecast.level.tint)
                    Spacer(Modifier.width(10.dp))
                    Text("risk today", style = Type.subhead, color = palette.textSecondary, modifier = Modifier.weight(1f))
                    Box(Modifier.size(40.dp).clip(CircleShape).tappable("Refresh risk forecast", onClick = onRetry), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Refresh, null, tint = palette.textSecondary, modifier = Modifier.size(18.dp))
                    }
                }
                if (forecast.factors.isEmpty()) {
                    Text("No elevated signals in the next 24 hours.", style = Type.footnote, color = palette.textSecondary)
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        forecast.factors.forEach { factor ->
                            Row(verticalAlignment = Alignment.Top) {
                                Icon(Symbols.of(factor.icon), null, tint = Brand.primary, modifier = Modifier.size(20.dp))
                                Spacer(Modifier.width(10.dp))
                                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(factor.title, style = Type.subheadBold, color = palette.textPrimary)
                                    Text(factor.detail, style = Type.footnote, color = palette.textSecondary)
                                }
                            }
                        }
                    }
                }
                Row(verticalAlignment = Alignment.Top) {
                    Icon(Icons.Filled.CheckCircle, null, tint = forecast.level.tint, modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(forecast.recommendation, style = Type.footnote, color = palette.textPrimary)
                }
            }
            loading -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), color = palette.textSecondary, strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text("Checking forecast…", style = Type.subhead, color = palette.textSecondary)
            }
            locationMissing -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.LocationOff, null, tint = palette.textPrimary, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Location unavailable", style = Type.subheadBold, color = palette.textPrimary)
                }
                Text("Log a headache once to capture your location, then come back here for forecast-based risk.", style = Type.footnote, color = palette.textSecondary)
            }
            else -> Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.WifiOff, null, tint = palette.textSecondary, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(10.dp))
                Text("Forecast unavailable. Tap to retry.", style = Type.footnote, color = palette.textSecondary, modifier = Modifier.weight(1f))
                Text("Retry", style = Type.of(13.sp, FontWeight.Bold), color = Brand.primary, modifier = Modifier.clip(RoundedCornerShape(6.dp)).tappable("Retry", onClick = onRetry).padding(8.dp))
            }
        }
    }
}

@Composable
private fun AlertsCard(enabled: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Brand.primary.copy(alpha = 0.08f))
            .border(1.dp, Brand.primary.copy(alpha = if (enabled) 0f else 0.25f), shape)
            .testTag("proactiveAlertsCard").tappable("Proactive Alerts", onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (enabled) Icons.Filled.NotificationsActive else Icons.Filled.NotificationsOff, null,
            tint = if (enabled) Brand.primary else palette.textSecondary, modifier = Modifier.size(28.dp),
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Proactive Alerts", style = Type.headline, color = palette.textPrimary)
                Spacer(Modifier.width(8.dp))
                val (label, tint) = if (enabled) "On" to Tint.green else "Suggested setup" to Brand.primary
                Text(
                    label, style = Type.of(11.sp, FontWeight.Bold), color = tint,
                    modifier = Modifier.clip(CircleShape).background(tint.copy(alpha = if (enabled) 0.18f else 0.15f)).padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
            Text(
                if (enabled) "You'll be notified when the forecast matches a supported personal trigger. Tap to tune thresholds and quiet hours."
                else "Turn on background forecast checks that stay quiet until your logs support a pressure or AQI trigger.",
                style = Type.footnote, color = palette.textSecondary,
            )
        }
    }
}

@Composable
private fun LockedTeaser(count: Int, summary: InsightSummary, modifier: Modifier, onUnlock: () -> Unit) {
    Column(modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Column(Modifier.fillMaxWidth().padding(top = 24.dp, start = 20.dp, end = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.BarChart, null, tint = Brand.primary, modifier = Modifier.size(60.dp))
                Text("See what triggers your headaches", style = Type.title2, color = palette.textPrimary, textAlign = TextAlign.Center)
                Text(
                    "Pro analyzes your logged events and surfaces the patterns hiding in the data (sleep, pressure, time of day, weather) with a chart and explanation for each one.",
                    style = Type.callout, color = palette.textSecondary, textAlign = TextAlign.Center,
                )
            }
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (count >= InsightsEngine.MINIMUM_SAMPLE_SIZE && summary.insights.isNotEmpty()) {
                    Text("Your patterns so far", style = Type.captionBold, color = palette.textSecondary, modifier = Modifier.padding(start = 4.dp))
                    summary.insights.forEach { LockedInsightRow(it, onUnlock) }
                } else {
                    Text("Example patterns you'll see", style = Type.captionBold, color = palette.textSecondary, modifier = Modifier.padding(start = 4.dp))
                    SampleRow(Icons.Filled.WbTwilight, "Most common time: Evening", "40% of your headaches, 1.6× the even baseline.")
                    SampleRow(Icons.Filled.Hotel, "Sleep before a headache", "Median 5h 40m, 47% under 6 hours.")
                    SampleRow(Icons.Filled.Speed, "Falling pressure pattern", "62% of headaches followed a pressure drop.")
                    SampleRow(Icons.Filled.NotificationsActive, "Proactive Alerts", "Get notified 12-24h before risky weather.")
                }
            }
        }
        Column(
            Modifier.fillMaxWidth().background(palette.card).padding(vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("Logged so far: $count headache${if (count == 1) "" else "s"}", style = Type.footnote, color = palette.textSecondary)
            Box(Modifier.padding(horizontal = 20.dp)) {
                PrimaryButton("See Pro plans", onUnlock, modifier = Modifier.testTag("patternsSeePlans"), brush = SolidColor(Brand.primary))
            }
        }
    }
}

@Composable
private fun LockedInsightRow(insight: Insight, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).tappable(insight.title, onClick = onClick), contentAlignment = Alignment.Center) {
        Row(Modifier.fillMaxWidth().blur(7.dp).padding(vertical = 4.dp), verticalAlignment = Alignment.Top) {
            Icon(Symbols.of(insight.icon), null, tint = Brand.primary, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(insight.title, style = Type.headline, color = palette.textPrimary)
                    Spacer(Modifier.width(6.dp))
                    ProBadge()
                }
                Text(insight.detail, style = Type.subhead, color = palette.textSecondary)
            }
        }
        Icon(Icons.Filled.Lock, "Locked", tint = palette.textSecondary, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun SampleRow(icon: ImageVector, title: String, detail: String) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(palette.textSecondary.copy(alpha = 0.08f)).padding(12.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = Brand.primary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Type.subheadBold, color = palette.textPrimary)
            Text(detail, style = Type.footnote, color = palette.textSecondary)
        }
    }
}

// Insight detail

/** Port of `InsightDetailView`: hero, breakdown chart, your pattern, why it matters, alerts link. */
@Composable
fun InsightDetailScreen(insight: Insight, totalEvents: Int, onClose: () -> Unit) {
    val nav = LocalNav.current
    Column(Modifier.fillMaxSize().background(palette.background)) {
        TopBar(insight.title, leading = "Back" to onClose)
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 32.dp)
                .windowInsetsPadding(WindowInsets.navigationBars),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Symbols.of(insight.icon), null, tint = Brand.primary, modifier = Modifier.size(34.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(insight.title, style = Type.title2, color = palette.textPrimary)
                }
                Text(insight.detail, style = Type.body, color = palette.textSecondary)
                Text("Based on $totalEvents logged headache${if (totalEvents == 1) "" else "s"}.", style = Type.caption, color = palette.textTertiary)
            }
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(palette.textSecondary.copy(alpha = 0.08f)).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(insight.breakdown.axisCaption, style = Type.subheadBold, color = palette.textPrimary)
                BreakdownChart(insight.breakdown, Modifier.fillMaxWidth().height(220.dp))
                insight.breakdown.evenBaseline?.let { baseline ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.width(18.dp).height(2.dp).background(palette.textSecondary))
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "Even baseline (${InsightsEngine.percent(baseline)}): what you'd see if headaches were spread evenly across these buckets.",
                            style = Type.caption, color = palette.textSecondary,
                        )
                    }
                }
            }
            Block(Icons.Filled.AccountCircle, "Your pattern", insight.yourPattern)
            Block(Icons.Filled.Lightbulb, "Why this matters", insight.whyItMatters)
            if (insight.category in setOf(InsightCategory.PRESSURE, InsightCategory.AIR_QUALITY, InsightCategory.WEATHER)) {
                val shape = RoundedCornerShape(14.dp)
                Row(
                    Modifier.fillMaxWidth().clip(shape).background(Brand.primary.copy(alpha = 0.08f)).border(1.dp, Brand.primary.copy(alpha = 0.25f), shape)
                        .tappable("Set up Proactive Alerts") { nav.push(Overlay.ProAlerts) }.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.NotificationsActive, null, tint = Brand.primary, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("Set up Proactive Alerts", style = Type.headline, color = palette.textPrimary)
                        Text("Get a notification before this signal spikes.", style = Type.footnote, color = palette.textSecondary)
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.textSecondary)
                }
            }
            Text("Computed locally from your logged events. Descriptive only, not a clinical diagnosis.", style = Type.footnote, color = palette.textTertiary)
        }
    }
}

@Composable
private fun Block(icon: ImageVector, title: String, body: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = Brand.primary, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(title, style = Type.headline, color = palette.textPrimary)
        }
        Text(body, style = Type.callout, color = palette.textPrimary)
    }
}

/** The Swift Charts bar chart: peak bucket in brand, others muted, dashed even baseline, percent labels. */
@Composable
private fun BreakdownChart(breakdown: Breakdown, modifier: Modifier) {
    val measurer = rememberTextMeasurer()
    val muted = palette.textSecondary.copy(alpha = 0.45f)
    val secondary = palette.textSecondary
    val grid = palette.separator
    val density = LocalDensity.current
    val buckets = breakdown.buckets
    val top = maxOf(0.4, (buckets.maxOfOrNull { it.share } ?: 0.4) * 1.25)
    Canvas(modifier) {
        val axisWidth = with(density) { 34.dp.toPx() }
        val labelHeight = with(density) { 30.dp.toPx() }
        val topPad = with(density) { 16.dp.toPx() }
        val plotWidth = size.width - axisWidth
        val plotHeight = size.height - labelHeight - topPad
        fun yOf(value: Double) = topPad + plotHeight * (1 - (value / top)).toFloat()
        val small = Type.caption2.copy(color = secondary)
        listOf(0.0, top / 4, top / 2, top * 3 / 4, top).forEach { tick ->
            val y = yOf(tick)
            drawLine(grid, Offset(0f, y), Offset(plotWidth, y), strokeWidth = 1f)
            drawLabel(measurer, InsightsEngine.percent(tick), Offset(plotWidth + 6f, y - 14f), small)
        }
        if (buckets.isEmpty()) return@Canvas
        val slot = plotWidth / buckets.size
        val barWidth = slot * 0.6f
        buckets.forEachIndexed { i, bucket ->
            val x = slot * i + (slot - barWidth) / 2
            val y = yOf(bucket.share)
            val color = if (bucket.isPeak) Brand.primary else muted
            drawRoundRect(color, Offset(x, y), Size(barWidth, yOf(0.0) - y), CornerRadius(8f, 8f))
            val style = Type.caption2.copy(color = if (bucket.isPeak) Brand.primary else secondary, fontWeight = if (bucket.isPeak) FontWeight.Bold else FontWeight.Normal)
            val pct = measurer.measure(InsightsEngine.percent(bucket.share), style)
            drawText(pct, topLeft = Offset(x + barWidth / 2 - pct.size.width / 2, y - pct.size.height - 2f))
            val label = measurer.measure(bucket.label, small, maxLines = 2, constraints = androidx.compose.ui.unit.Constraints(maxWidth = slot.toInt().coerceAtLeast(1)))
            drawText(label, topLeft = Offset(slot * i + slot / 2 - label.size.width / 2, yOf(0.0) + 6f))
        }
        breakdown.evenBaseline?.let { baseline ->
            val y = yOf(baseline)
            drawLine(secondary, Offset(0f, y), Offset(plotWidth, y), strokeWidth = 3f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 9f)))
            val tag = measurer.measure("Even baseline", small)
            drawText(tag, topLeft = Offset(plotWidth - tag.size.width - 4f, y - tag.size.height - 2f))
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawLabel(measurer: TextMeasurer, text: String, at: Offset, style: androidx.compose.ui.text.TextStyle) {
    drawText(measurer.measure(text, style), topLeft = at)
}
