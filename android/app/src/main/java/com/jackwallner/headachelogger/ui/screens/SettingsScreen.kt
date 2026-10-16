package com.jackwallner.headachelogger.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.capture.HealthAccess
import com.jackwallner.headachelogger.data.Appearance
import com.jackwallner.headachelogger.ui.LocalForeground
import com.jackwallner.headachelogger.ui.LocalNav
import com.jackwallner.headachelogger.ui.Links
import com.jackwallner.headachelogger.ui.Overlay
import com.jackwallner.headachelogger.ui.appVersionLine
import com.jackwallner.headachelogger.ui.composeMail
import com.jackwallner.headachelogger.ui.deviceLine
import com.jackwallner.headachelogger.ui.openAppSettings
import com.jackwallner.headachelogger.ui.openHealthConnectSettings
import com.jackwallner.headachelogger.ui.openUrl
import com.jackwallner.headachelogger.ui.openWriteReview
import com.jackwallner.headachelogger.ui.theme.Brand
import com.jackwallner.headachelogger.ui.theme.FormSection
import com.jackwallner.headachelogger.ui.theme.LargeTitle
import com.jackwallner.headachelogger.ui.theme.RowDivider
import com.jackwallner.headachelogger.ui.theme.ToggleRow
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette
import com.jackwallner.headachelogger.ui.theme.tappable
import kotlinx.coroutines.launch

/** Port of `SettingsView`. */
@Composable
fun SettingsScreen(graph: AppGraph) {
    val settings = graph.settings
    val store = graph.store
    val nav = LocalNav.current
    val context = LocalContext.current
    val foreground = LocalForeground.current
    val scope = rememberCoroutineScope()
    var healthStatus by remember { mutableStateOf("Checking…") }
    var locationStatus by remember { mutableStateOf(graph.environment.authorizationSummary()) }
    var restoring by remember { mutableStateOf(false) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    var reviewDialog by remember { mutableStateOf(false) }

    LaunchedEffect(foreground) {
        locationStatus = graph.environment.authorizationSummary()
        healthStatus = when (graph.health.access()) {
            HealthAccess.READY -> "Connected"
            HealthAccess.NEEDS_PERMISSION -> if (settings.declinedHealthRead) "Not allowed" else "Not connected"
            HealthAccess.UNAVAILABLE -> "Unavailable on this device"
        }
    }

    Column(Modifier.fillMaxSize().background(palette.background)) {
        LargeTitle("Settings")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
            FormSection(
                header = "Headache Pro",
                footer = "Pro checks your local forecast and only pings when your logs support the pressure, AQI, or timing pattern behind the alert.",
            ) {
                ProRow(store.isPro) { if (store.isPro) nav.push(Overlay.ProAlerts) else nav.paywall("headache_settings_sheet") }
                if (store.isPro && store.activeSubscriptionProductId != null) {
                    RowDivider()
                    ActionRow("Manage Subscription") { context.openUrl(Links.manageSubscription(store.activeSubscriptionProductId)) }
                }
                RowDivider()
                Row(
                    Modifier.fillMaxWidth().tappable("Restore Purchases", enabled = !restoring) {
                        restoring = true
                        scope.launch {
                            store.restorePurchases()
                            restoreMessage = if (store.isPro) "Your Headache Pro access is active." else store.lastError ?: com.jackwallner.headachelogger.billing.ConversionCopy.NO_PURCHASE_FOUND
                            restoring = false
                        }
                    }.heightIn(min = 48.dp).padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (restoring) CircularProgressIndicator(Modifier.size(20.dp), color = palette.textSecondary, strokeWidth = 2.dp)
                    else Text("Restore Purchases", style = Type.body, color = Brand.primary)
                }
            }
            FormSection(header = "Logging") {
                ToggleRow("Prompt for severity and notes", settings.promptForSeverityNotes, { settings.promptForSeverityNotes = it }, tag = "severityPromptToggle")
                if (graph.quiz.hasCompletedQuiz) {
                    RowDivider()
                    Row(
                        Modifier.fillMaxWidth().tappable("Headache Pattern Quiz") { nav.push(Overlay.QuizRetake) }.heightIn(min = 48.dp).padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.HelpOutline, null, tint = Brand.primary, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.width(12.dp))
                        Text("Headache Pattern Quiz", style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.textTertiary)
                    }
                }
            }
            FormSection(header = "Display") {
                PickerRow("Color scheme", settings.appearance.label, Appearance.entries.map { it.label }) { settings.appearance = Appearance.entries[it] }
                RowDivider()
                ToggleRow("Use Celsius", settings.useCelsius, { settings.useCelsius = it })
            }
            FormSection(header = "Permissions", footer = "Health Connect and location are read-only and only used to enrich logs with context.") {
                ValueLine("Health Connect", healthStatus, "healthPermissionValue")
                RowDivider()
                ValueLine("Location", locationStatus, "locationPermissionValue")
                RowDivider()
                ActionRow("Open Health Connect") { context.openHealthConnectSettings() }
                RowDivider()
                ActionRow("Open App Settings") { context.openAppSettings() }
            }
            FormSection(header = "About & Support") {
                ActionRow("Rate One Tap Headache Tracker") {
                    graph.review.markOpenedWriteReview()
                    context.openWriteReview()
                }
                RowDivider()
                ActionRow("Send Feedback") {
                    graph.review.markFeedbackSubmitted()
                    context.composeMail("One Tap Headache Tracker feedback", "\n\n$appVersionLine\n$deviceLine")
                }
                RowDivider()
                ActionRow("Privacy Policy") { context.openUrl(Links.PRIVACY) }
                RowDivider()
                ActionRow("Terms of Use") { context.openUrl(Links.TERMS) }
                RowDivider()
                ActionRow("Support") { context.openUrl(Links.SUPPORT) }
                RowDivider()
                VersionRow { reviewDialog = true }
            }
            Text(
                "One Tap Headache Tracker records context to support conversations with your doctor. It does not diagnose, treat, or prevent any condition.",
                style = Type.footnote, color = palette.textTertiary, modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
    restoreMessage?.let { InfoDialog("Restore Purchases", it) { restoreMessage = null } }
    if (reviewDialog) ReviewCodeDialog(graph) { reviewDialog = false }
}

@Composable
private fun ProRow(unlocked: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().testTag("settingsProRow").tappable("Proactive Alerts", onClick = onClick).heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (unlocked) Icons.Filled.NotificationsActive else Icons.Filled.Lock, null,
            tint = if (unlocked) Brand.primary else palette.textSecondary, modifier = Modifier.size(22.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Proactive Alerts", style = Type.body, color = palette.textPrimary)
            Text(
                if (unlocked) "Configure personal triggers, thresholds, and quiet hours" else "Unlock Pro to get personalized headache-weather warnings",
                style = Type.footnote, color = palette.textSecondary,
            )
        }
        if (!unlocked) {
            Text(
                "Pro", style = Type.of(12.sp, FontWeight.Bold), color = Brand.primary,
                modifier = Modifier.clip(CircleShape).background(Brand.primary.copy(alpha = 0.15f)).padding(horizontal = 8.dp, vertical = 4.dp),
            )
        } else {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.textTertiary)
        }
    }
}

@Composable
private fun ActionRow(title: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().tappable(title, onClick = onClick).heightIn(min = 48.dp).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) { Text(title, style = Type.body, color = Brand.primary) }
}

@Composable
private fun ValueLine(title: String, value: String, tag: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
        Text(value, style = Type.body, color = palette.textSecondary, modifier = Modifier.testTag(tag))
    }
}

/** Long-press opens the Play reviewer code entry, as in the other fleet ports. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun VersionRow(onLongPress: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = onLongPress).semantics { contentDescription = "Version" }
            .heightIn(min = 48.dp).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Version", style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
        Text(appVersionLine, style = Type.body, color = palette.textSecondary)
    }
}

@Composable
fun PickerRow(title: String, value: String, options: List<String>, onPick: (Int) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().tappable(title) { expanded = true }.heightIn(min = 48.dp).padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
            Text(value, style = Type.body, color = palette.textSecondary)
        }
        DropdownMenu(expanded, { expanded = false }, containerColor = palette.card) {
            options.forEachIndexed { index, option ->
                DropdownMenuItem(text = { Text(option, style = Type.body, color = palette.textPrimary) }, onClick = { expanded = false; onPick(index) })
            }
        }
    }
}

/** Play reviewers unlock Headache Pro with a code checked against a hash baked into the release build. */
@Composable
private fun ReviewCodeDialog(graph: AppGraph, onDismiss: () -> Unit) {
    var code by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = palette.card,
        title = { Text("Reviewer access", style = Type.headline, color = palette.textPrimary) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Enter the review code from the Play Console app access notes.", style = Type.footnote, color = palette.textSecondary)
                BasicTextField(
                    value = code, onValueChange = { code = it; failed = false }, singleLine = true,
                    textStyle = Type.body.copy(color = palette.textPrimary), cursorBrush = SolidColor(Brand.primary),
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(palette.background).padding(12.dp),
                )
                if (failed) Text("That code didn't match.", style = Type.caption, color = Color(0xFFFF3B30))
            }
        },
        confirmButton = { TextButton(onClick = { if (graph.store.activateReviewAccess(code)) onDismiss() else failed = true }) { Text("Unlock", color = Brand.primary) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel", color = palette.textSecondary) } },
    )
}
