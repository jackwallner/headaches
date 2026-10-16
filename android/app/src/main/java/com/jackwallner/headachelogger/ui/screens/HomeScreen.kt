package com.jackwallner.headachelogger.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WbCloudy
import androidx.compose.material.icons.outlined.ChatBubbleOutline
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.CaptureStatus
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.HeadacheSeverity
import com.jackwallner.headachelogger.model.PressureTrend
import com.jackwallner.headachelogger.model.Temperature
import com.jackwallner.headachelogger.ui.Format
import com.jackwallner.headachelogger.ui.LocalNav
import com.jackwallner.headachelogger.ui.LocalPromos
import com.jackwallner.headachelogger.ui.Overlay
import com.jackwallner.headachelogger.ui.appVersionLine
import com.jackwallner.headachelogger.ui.composeMail
import com.jackwallner.headachelogger.ui.deviceLine
import com.jackwallner.headachelogger.ui.severityColor
import com.jackwallner.headachelogger.ui.theme.Brand
import com.jackwallner.headachelogger.ui.theme.Card
import com.jackwallner.headachelogger.ui.theme.Disclosure
import com.jackwallner.headachelogger.ui.theme.SegmentedControl
import com.jackwallner.headachelogger.ui.theme.StatusBadge
import com.jackwallner.headachelogger.ui.theme.Tint
import com.jackwallner.headachelogger.ui.theme.TopBar
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette
import com.jackwallner.headachelogger.ui.theme.tappable
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val UNDO_TTL_MS = 15_000L
private const val CAPTURE_EXPLAINER_THRESHOLD = 3

private enum class Milestone(val count: Int, val title: String, val detail: String, val icon: ImageVector) {
    TEN(10, "10 headaches, meaningful data", "You've built enough history for meaningful patterns. Unlock Pro to see your personalized patterns and get proactive alerts.", Icons.Filled.Bolt),
    FIVE(5, "5 headaches logged, enough for patterns", "You have enough data for personalized pattern analysis. Pro finds what's triggering your headaches.", Icons.Filled.AutoAwesome),
    THREE(3, "You've logged 3 headaches", "Great start! Pro reveals the patterns hiding in your logs: time, sleep, weather, and more.", Icons.Filled.BarChart),
}

/** Port of `HomeView`: the one-tap button, the latest event, recovery, milestone prompts and the undo bar. */
@Composable
fun HomeScreen(graph: AppGraph) {
    val capture = graph.capture
    val settings = graph.settings
    val nav = LocalNav.current
    val events = graph.events.events
    val latest = events.firstOrNull()
    val recent = events.drop(1).take(3)
    val scope = rememberCoroutineScope()
    var showCheckmark by remember { mutableStateOf(false) }
    var undoVisible by remember { mutableStateOf(false) }
    var undoJob by remember { mutableStateOf<Job?>(null) }

    fun showUndo() {
        undoJob?.cancel()
        undoVisible = true
        undoJob = scope.launch { delay(UNDO_TTL_MS); undoVisible = false }
    }
    fun hideUndo() {
        undoJob?.cancel()
        undoJob = null
        undoVisible = false
    }

    LaunchedEffect(capture.isCapturing) {
        if (!capture.isCapturing && capture.lastCapturedEventId != null) {
            showCheckmark = true
            showUndo()
            delay(3_500)
            showCheckmark = false
        }
    }
    LaunchedEffect(capture.lastCapturedEventId) { if (capture.lastCapturedEventId == null) hideUndo() }

    val milestone = when {
        graph.store.isPro || capture.proPromptShownThisSession -> null
        events.size >= 10 && !settings.milestone10Shown -> Milestone.TEN
        events.size >= 5 && !settings.milestone5Shown -> Milestone.FIVE
        events.size >= 3 && !settings.milestone3Shown -> Milestone.THREE
        else -> null
    }

    Box(Modifier.fillMaxSize().background(palette.background).testTag("homeView")) {
        Column(Modifier.fillMaxSize()) {
            TopBar(com.jackwallner.headachelogger.ui.AppBrand.NAME)
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    LogButton(
                        capturing = capture.isCapturing,
                        showCheckmark = showCheckmark,
                        onTap = {
                            val success = capture.captureHeadache()
                            if (success && settings.promptForSeverityNotes) {
                                val id = capture.lastCapturedEventId
                                scope.launch {
                                    delay(500)
                                    if (id != null && capture.lastCapturedEventId == id) nav.push(Overlay.SeverityNotes(id))
                                }
                            }
                        },
                    )
                    val status = capture.bannerMessage
                    if (!capture.isCapturing && status != null) {
                        CaptureStatusLine(status, capture.bannerIsError) { capture.bannerMessage = null }
                    }
                }
                if (latest != null) {
                    LatestEventCard(latest, settings.useCelsius)
                    if (latest.captureStatus == CaptureStatus.PARTIAL || latest.captureStatus == CaptureStatus.FAILED) {
                        RecoveryCard(latest, capture.isCapturing) { capture.retryCapture(latest.id) }
                    }
                }
                if (milestone != null) {
                    LaunchedEffect(milestone) { capture.proPromptShownThisSession = true }
                    MilestonePrompt(
                        milestone,
                        onShow = { nav.paywall("headache_home_sheet") },
                        onDismiss = {
                            when (milestone) {
                                Milestone.THREE -> settings.milestone3Shown = true
                                Milestone.FIVE -> settings.milestone5Shown = true
                                Milestone.TEN -> settings.milestone10Shown = true
                            }
                        },
                    )
                }
                if (recent.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Previous entries", style = Type.headline, color = palette.textPrimary, modifier = Modifier.weight(1f))
                            Text("See all in History", style = Type.footnote, color = palette.textSecondary)
                        }
                        recent.forEach { RecentEventRow(it) }
                    }
                }
                if (events.size < CAPTURE_EXPLAINER_THRESHOLD) CaptureExplainer()
                Spacer(Modifier.heightIn(min = if (undoVisible) 72.dp else 0.dp))
            }
        }
        AnimatedVisibility(
            visible = undoVisible && capture.lastCapturedEventId != null,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(tween(250)) { it } + fadeIn(tween(250)),
            exit = slideOutVertically(tween(250)) { it } + fadeOut(tween(250)),
        ) {
            UndoSnackbar(
                onAddDetails = { capture.lastCapturedEventId?.let { nav.push(Overlay.SeverityNotes(it)) } },
                onUndo = { capture.undoLastCapture(); hideUndo() },
                onDismiss = ::hideUndo,
            )
        }
    }
}

@Composable
private fun LogButton(capturing: Boolean, showCheckmark: Boolean, onTap: () -> Unit) {
    val shape = RoundedCornerShape(28.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .shadow(18.dp, shape, ambientColor = Brand.secondary.copy(alpha = 0.3f), spotColor = Brand.secondary.copy(alpha = 0.3f))
            .clip(shape)
            .background(Brand.gradient)
            .testTag("logHeadacheButton")
            .tappable("Log headache", enabled = !capturing && !showCheckmark, onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        Column(Modifier.padding(vertical = 44.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Icon(Icons.Filled.Psychology, null, tint = Color.White, modifier = Modifier.size(60.dp))
            Text("Log Headache", style = Type.of(28.sp, FontWeight.ExtraBold), color = Color.White)
            Text(
                if (capturing) "Saving and collecting context..." else "Tap once, we'll record the moment",
                style = Type.subhead, color = Color.White.copy(alpha = 0.9f),
            )
        }
        AnimatedVisibility(showCheckmark, Modifier.matchParentSize(), enter = fadeIn(tween(250)), exit = fadeOut(tween(250))) {
            Box(Modifier.fillMaxSize().background(palette.card.copy(alpha = 0.92f)), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.CheckCircle, null, tint = Tint.green, modifier = Modifier.size(36.dp))
                    Text("Logged", style = Type.headline, color = palette.textPrimary)
                }
            }
        }
    }
}

@Composable
private fun CaptureStatusLine(text: String, isError: Boolean, onDismiss: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(palette.cardRaised.takeIf { !palette.isDark } ?: palette.cardRaised)
            .padding(start = 14.dp, end = 4.dp, top = 6.dp, bottom = 6.dp).testTag("captureStatusLine"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (isError) Icons.Filled.Warning else Icons.Filled.CheckCircle, null, tint = if (isError) Tint.orange else Tint.green, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, style = Type.of(15.sp, FontWeight.Medium), color = palette.textPrimary, modifier = Modifier.weight(1f))
        Box(Modifier.size(40.dp).clip(CircleShape).tappable("Dismiss", onClick = onDismiss), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Close, null, tint = palette.textSecondary, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
private fun LatestEventCard(event: HeadacheEvent, useCelsius: Boolean) {
    Card(Modifier.testTag("latestEventCard")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Latest Event", style = Type.headline, color = palette.textPrimary, modifier = Modifier.weight(1f))
            event.severity?.let { StatusBadge(it.title, severityColor(it)) }
        }
        Spacer(Modifier.heightIn(min = 12.dp))
        Text(latestSummary(event, useCelsius), style = Type.subhead, color = palette.textPrimary, modifier = Modifier.testTag("latestEventSummary"))
        Spacer(Modifier.heightIn(min = 12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            MetricChip("Steps", event.stepsToday?.let(Format::grouped) ?: "–", Tint.teal, Modifier.weight(1f))
            MetricChip("Sleep", event.sleepHoursLastNight?.let { "${Format.oneDecimal(it)} h" } ?: "–", Tint.indigo, Modifier.weight(1f))
            MetricChip("AQI", event.usAQI?.let { String.format(java.util.Locale.US, "%.0f", it) } ?: "–", Tint.mint, Modifier.weight(1f))
        }
        if (event.healthStatus != CaptureSourceStatus.CAPTURED || event.environmentStatus != CaptureSourceStatus.CAPTURED) {
            Spacer(Modifier.heightIn(min = 6.dp))
            Disclosure("Why is something missing?", Modifier.testTag("latestEventDetailsDisclosure")) {
                Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    StatusBadge("Health: ${event.healthStatus.raw}", if (event.healthStatus == CaptureSourceStatus.CAPTURED) Tint.green else Tint.orange)
                    StatusBadge("Environment: ${event.environmentStatus.raw}", if (event.environmentStatus == CaptureSourceStatus.CAPTURED) Tint.blue else Tint.orange)
                }
            }
        }
    }
}

private fun latestSummary(event: HeadacheEvent, useCelsius: Boolean): String {
    val parts = mutableListOf("${Format.weekdayDateTime(event.timestamp)} · ${event.partOfDay.title}")
    val weather = Temperature.weatherSummaryWithTemperature(event.weatherSummary, event.temperatureC, useCelsius)
    when {
        weather != null -> parts += weather
        event.locationLabel.isNotEmpty() -> parts += event.locationLabel
    }
    when (event.pressureTrend) {
        PressureTrend.FALLING -> parts += "pressure falling"
        PressureTrend.RISING -> parts += "pressure rising"
        else -> Unit
    }
    event.sleepHoursLastNight?.let { parts += "slept ${Format.oneDecimal(it)}h" }
    return parts.joinToString(" · ")
}

@Composable
private fun MetricChip(title: String, value: String, tint: Color, modifier: Modifier) {
    Column(modifier.clip(RoundedCornerShape(14.dp)).background(tint.copy(alpha = 0.10f)).padding(horizontal = 12.dp, vertical = 10.dp)) {
        Text(title.uppercase(), style = Type.of(11.sp, FontWeight.SemiBold), color = palette.textSecondary)
        Text(value, style = Type.headline, color = tint, maxLines = 1)
    }
}

@Composable
private fun RecoveryCard(event: HeadacheEvent, retrying: Boolean, onRetry: () -> Unit) {
    val context = LocalContext.current
    val shape = RoundedCornerShape(18.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(Tint.orange.copy(alpha = 0.10f)).border(1.dp, Tint.orange.copy(alpha = 0.35f), shape)
            .padding(16.dp).testTag("captureRecoveryCard"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.ChatBubbleOutline, null, tint = Tint.orange, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Some context couldn't be captured", style = Type.subheadBold, color = Tint.orange)
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (event.healthStatus != CaptureSourceStatus.CAPTURED) {
                Text("Health ${event.healthStatus.raw}: ${event.healthStatusMessage ?: "no detail"}", style = Type.footnote, color = palette.textSecondary)
            }
            if (event.environmentStatus != CaptureSourceStatus.CAPTURED) {
                Text("Environment ${event.environmentStatus.raw}: ${event.environmentStatusMessage ?: "no detail"}", style = Type.footnote, color = palette.textSecondary)
            }
        }
        Box(
            Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp)).background(Tint.orange)
                .testTag("captureRetryButton").tappable("Try Again", enabled = !retrying, onClick = onRetry),
            contentAlignment = Alignment.Center,
        ) {
            if (retrying) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
            else Text("Try Again", style = Type.headline, color = Color.White)
        }
        Disclosure("Still stuck?") {
            Box(
                Modifier.padding(top = 8.dp).fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp))
                    .background(palette.separator.copy(alpha = 0.25f)).testTag("captureReportButton")
                    .tappable("Email Developer") { context.composeMail("One Tap Headache Tracker: capture failed", captureMailBody(event)) },
                contentAlignment = Alignment.Center,
            ) { Text("Email Developer", style = Type.headline, color = Brand.primary) }
        }
    }
}

private fun captureMailBody(event: HeadacheEvent): String = listOf(
    "Hi Jack,",
    "",
    "Context capture hit an issue after logging a headache. Details below.",
    "",
    "- App version: $appVersionLine",
    "- $deviceLine",
    "- Event ID: ${event.id.toString().uppercase()}",
    "- Event time: ${DateTimeFormatter.ISO_INSTANT.format(event.timestamp)}",
    "- Capture status: ${event.captureStatus.raw}",
    "- Health status: ${event.healthStatus.raw}${event.healthStatusMessage?.let { ": $it" } ?: ""}",
    "- Environment status: ${event.environmentStatus.raw}${event.environmentStatusMessage?.let { ": $it" } ?: ""}",
    "",
    "Anything else you want to add:",
    "",
).joinToString("\n")

@Composable
private fun RecentEventRow(event: HeadacheEvent) {
    Card(radius = 18.dp, padding = 16.dp, modifier = Modifier.testTag("recentEventRow")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(Format.dateTime(event.timestamp), style = Type.subheadBold, color = palette.textPrimary, modifier = Modifier.weight(1f))
            Text(event.partOfDay.title, style = Type.captionBold, color = palette.textSecondary)
        }
        Spacer(Modifier.heightIn(min = 8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconLabel(Icons.Filled.LocationOn, event.locationLabel.ifEmpty { "Location unavailable" }, Modifier.weight(1f))
            IconLabel(Icons.Filled.Cloud, event.weatherSummary ?: "No weather")
        }
    }
}

@Composable
private fun IconLabel(icon: ImageVector, text: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = palette.textSecondary, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(4.dp))
        Text(text, style = Type.caption, color = palette.textSecondary, maxLines = 1)
    }
}

@Composable
private fun CaptureExplainer() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("What Gets Captured", style = Type.headline, color = palette.textPrimary)
        Text(
            "Press once when a headache starts; the app records the moment and fills in as much health and environmental context as it can.",
            style = Type.footnote, color = palette.textSecondary,
        )
        CaptureItem(Icons.Filled.AccessTime, "Time context", "Date, weekday, hour, minute, timezone, and part of day.")
        CaptureItem(Icons.Filled.Favorite, "Health Connect context", "Sleep duration plus inferred wake time from Health Connect, all without typing.")
        CaptureItem(Icons.Filled.WbCloudy, "Weather and environment", "Location-based weather, pressure, air quality, UV, and pollen-style signals when available.")
    }
}

@Composable
private fun CaptureItem(icon: ImageVector, title: String, subtitle: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = Brand.primary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = Type.subheadBold, color = palette.textPrimary)
            Text(subtitle, style = Type.footnote, color = palette.textSecondary)
        }
    }
}

@Composable
private fun MilestonePrompt(milestone: Milestone, onShow: () -> Unit, onDismiss: () -> Unit) {
    var dismissed by remember(milestone) { mutableStateOf(false) }
    AnimatedVisibility(!dismissed, exit = fadeOut(tween(200))) {
        val shape = RoundedCornerShape(18.dp)
        Row(
            Modifier.fillMaxWidth().clip(shape).background(palette.card).border(1.dp, Brand.primary.copy(alpha = 0.25f), shape).padding(16.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(milestone.icon, null, tint = Brand.primary, modifier = Modifier.size(26.dp))
            Spacer(Modifier.width(14.dp))
            Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.weight(1f)) {
                Text(milestone.title, style = Type.subheadBold, color = palette.textPrimary)
                Text(milestone.detail, style = Type.footnote, color = palette.textSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Show me", style = Type.of(12.sp, FontWeight.Bold), color = Color.White,
                        modifier = Modifier.clip(CircleShape).background(Brand.primary).tappable("Show me", onClick = onShow).padding(horizontal = 14.dp, vertical = 8.dp),
                    )
                    Text(
                        "Not now", style = Type.caption, color = palette.textTertiary,
                        modifier = Modifier.clip(RoundedCornerShape(6.dp)).tappable("Not now") { dismissed = true; onDismiss() }.padding(8.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun UndoSnackbar(onAddDetails: () -> Unit, onUndo: () -> Unit, onDismiss: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth()
            .shadow(8.dp, shape).clip(shape).background(palette.card).border(1.dp, palette.textPrimary.copy(alpha = 0.08f), shape)
            .padding(start = 8.dp, end = 4.dp, top = 4.dp, bottom = 4.dp).testTag("undoSnackbar"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SnackAction(Icons.Filled.EditNote, "Add Details", Brand.primary, "addDetailsButton", onAddDetails)
        Spacer(Modifier.weight(1f))
        SnackAction(Icons.AutoMirrored.Filled.Undo, "Undo", Tint.red, "undoLastTapButton", onUndo)
        Box(Modifier.size(40.dp).clip(CircleShape).tappable("Dismiss", onClick = onDismiss), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Close, null, tint = palette.textSecondary, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
private fun SnackAction(icon: ImageVector, label: String, tint: Color, tag: String, onClick: () -> Unit) {
    Row(
        Modifier.clip(RoundedCornerShape(10.dp)).testTag(tag).tappable(label, onClick = onClick).heightIn(min = 44.dp).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text(label, style = Type.subheadBold, color = tint)
    }
}

/** Port of `SeverityNotesSheet`. */
@Composable
fun SeverityNotesScreen(graph: AppGraph, id: UUID, onClose: () -> Unit) {
    val event = graph.events.find(id)
    var severity by remember(id) { mutableStateOf(event?.severity) }
    var notes by remember(id) { mutableStateOf(event?.userNotes ?: "") }
    val promos = LocalPromos.current
    fun close() {
        onClose()
        promos.reviewTick += 1
    }
    Column(Modifier.fillMaxSize().background(palette.background).imePadding()) {
        TopBar(
            "Headache Details",
            leading = "Cancel" to ::close,
            trailing = "Save" to {
                graph.events.find(id)?.let { e ->
                    e.severity = severity
                    e.userNotes = notes.trim().ifEmpty { null }
                    graph.events.save()
                }
                close()
            },
            trailingBold = true,
        )
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            SeverityPicker(severity) { severity = it }
            NotesField(notes) { notes = it }
        }
    }
}

@Composable
fun SeverityPicker(selected: HeadacheSeverity?, onSelect: (HeadacheSeverity?) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Severity", style = Type.headline, color = palette.textPrimary)
        val options = listOf<HeadacheSeverity?>(null) + HeadacheSeverity.entries
        SegmentedControl(
            options.map { it?.title ?: "Not set" },
            options.indexOf(selected),
            { onSelect(options[it]) },
        )
    }
}

@Composable
fun NotesField(notes: String, title: String? = "Notes", onChange: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (title != null) Text(title, style = Type.headline, color = palette.textPrimary)
        BasicTextField(
            value = notes, onValueChange = onChange,
            textStyle = Type.body.copy(color = palette.textPrimary),
            cursorBrush = SolidColor(Brand.primary),
            modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp).clip(RoundedCornerShape(14.dp)).background(palette.card).padding(12.dp).testTag("notesField"),
            decorationBox = { inner ->
                Box {
                    if (notes.isEmpty()) Text("Add a note", style = Type.body, color = palette.textTertiary, textAlign = TextAlign.Start)
                    inner()
                }
            },
        )
    }
}
