package com.jackwallner.headachelogger.ui.screens

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Masks
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.alerts.Alerts
import com.jackwallner.headachelogger.model.AlertKind
import com.jackwallner.headachelogger.model.PersonalSignalProfile
import com.jackwallner.headachelogger.model.ProactiveAlertsEngine
import com.jackwallner.headachelogger.ui.Format
import com.jackwallner.headachelogger.ui.LocalForeground
import com.jackwallner.headachelogger.ui.openAppSettings
import com.jackwallner.headachelogger.ui.theme.Brand
import com.jackwallner.headachelogger.ui.theme.FormSection
import com.jackwallner.headachelogger.ui.theme.RowDivider
import com.jackwallner.headachelogger.ui.theme.SegmentedControl
import com.jackwallner.headachelogger.ui.theme.ToggleRow
import com.jackwallner.headachelogger.ui.theme.TopBar
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette
import com.jackwallner.headachelogger.ui.theme.tappable
import java.time.Instant
import java.util.Locale

/** Port of `ProAlertsConfigView`. */
@Composable
fun ProAlertsScreen(graph: AppGraph, onClose: () -> Unit) {
    val settings = graph.settings
    val context = LocalContext.current
    val foreground = LocalForeground.current
    var canNotify by remember { mutableStateOf(Alerts.canNotify(context)) }
    var asked by remember { mutableStateOf(false) }
    var location by remember { mutableStateOf(graph.environment.authorizationSummary()) }
    var testMessage by remember { mutableStateOf<String?>(null) }
    var profileVersion by remember { mutableIntStateOf(0) }
    val profile = remember(profileVersion) { settings.personalAlertProfile }

    fun refresh() {
        canNotify = Alerts.canNotify(context)
        location = graph.environment.authorizationSummary()
    }
    fun sendTest() {
        if (!Alerts.canNotify(context)) {
            refresh()
            testMessage = "Notifications are not enabled. Open Android Settings and allow notifications for One Tap Headache Tracker."
            return
        }
        Alerts.post(context, 3_000, "Test Headache Pro Alert", "Notifications are working. Real alerts fire only when a forecast matches a supported personal trigger from your logs.")
        testMessage = "Test alert sent."
    }
    val locationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) settings.declinedLocation = false
        refresh()
    }
    val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        asked = true
        refresh()
        if (!graph.environment.hasPermission()) locationLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
    }
    fun requestPermissions() {
        if (Build.VERSION.SDK_INT >= 33 && !Alerts.canNotify(context)) {
            notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else if (!graph.environment.hasPermission()) {
            locationLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }

    LaunchedEffect(foreground) {
        graph.schedulePatternAlerts()
        profileVersion++
        refresh()
    }

    val notificationLabel = when {
        canNotify -> "Ready"
        asked || Build.VERSION.SDK_INT < 33 -> "Off in Settings"
        else -> "Needs permission"
    }
    val locationLabel = when (location) {
        "Allowed" -> "Ready"
        "Not allowed" -> "Off in Settings"
        "Off" -> "Location services off"
        "Not yet asked" -> "Needs permission"
        else -> location
    }
    val banner = if (!settings.alertsEnabled) null else buildList {
        if (!canNotify) add(if (asked) "Notifications are off. Alerts can't be delivered until you enable them in Settings." else "Notification permission hasn't been granted yet.")
        if (location == "Not allowed" || location == "Off") add("Location is off. Without it the app can't fetch your local forecast.")
    }.takeIf { it.isNotEmpty() }?.joinToString(" ")

    Column(Modifier.fillMaxSize().background(palette.background)) {
        TopBar("Proactive Alerts", leading = "Back" to onClose)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
            FormSection(footer = "When enabled, the app checks your local forecast every few hours and only notifies you when your own daily history shows a clear link between headaches and pressure drops or air quality.") {
                ToggleRow("Enable Proactive Alerts", settings.alertsEnabled, { enabled ->
                    settings.alertsEnabled = enabled
                    graph.updateForecastSchedule()
                    if (enabled) requestPermissions()
                }, tag = "alertsToggle")
            }
            if (banner != null) {
                FormSection {
                    Text(banner, style = Type.footnote, color = palette.textSecondary, modifier = Modifier.padding(16.dp))
                    RowDivider()
                    LinkRow("Open Android Settings") { context.openAppSettings() }
                }
            }
            FormSection(
                header = "Status",
                footer = if (settings.alertsEnabled) "Use a test alert to confirm notifications are working before waiting for real headache weather." else "Enable Proactive Alerts first, then send a test notification.",
            ) {
                StatusRow(if (canNotify) Icons.Filled.NotificationsActive else if (notificationLabel == "Off in Settings") Icons.Filled.NotificationsOff else Icons.Filled.Notifications, "Notifications", notificationLabel)
                RowDivider()
                StatusRow(Icons.Filled.LocationOn, "Forecast location", locationLabel)
                RowDivider()
                StatusRow(Icons.Filled.History, "Last proactive alert", lastAlertText(settings.alertLastFiredAt, settings.alertLastFiredKind))
                RowDivider()
                Row(
                    Modifier.fillMaxWidth().tappable("Send Test Alert", enabled = settings.alertsEnabled) {
                        if (Build.VERSION.SDK_INT >= 33 && !Alerts.canNotify(context) && !asked) notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) else sendTest()
                    }.heightIn(min = 48.dp).padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val tint = if (settings.alertsEnabled) Brand.primary else palette.textTertiary
                    Icon(Icons.Filled.Send, null, tint = tint, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(12.dp))
                    Text("Send Test Alert", style = Type.body, color = tint)
                }
            }
            FormSection(
                header = "Personalization",
                footer = if (profile.pressure.isSupported || (settings.airQualityEnabled && profile.airQuality.isSupported)) {
                    "Alert text includes the probability lift and breakdown so you know why it fired."
                } else {
                    "Keep logging. Forecast alerts stay quiet until your daily history shows a clear weather-pattern link across at least ${ProactiveAlertsEngine.PERSONAL_MIN_SAMPLE_SIZE} days."
                },
            ) {
                StatusRow(Icons.Filled.Speed, "Pressure signal", signalStatus(profile.pressure))
                RowDivider()
                StatusRow(Icons.Filled.Masks, "Air-quality signal", if (settings.airQualityEnabled) signalStatus(profile.airQuality) else "Off")
            }
            FormSection(header = "Pressure drop", footer = "Most barometric-trigger studies use 3-6 hPa over 12-24 hours.") {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                    Text("Alert when pressure is forecast to drop by", style = Type.body, color = palette.textPrimary)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Slider(
                            value = settings.pressureDropThresholdHpa.toFloat(),
                            onValueChange = { settings.pressureDropThresholdHpa = (Math.round(it * 2) / 2.0) },
                            valueRange = 2f..10f, steps = 15, modifier = Modifier.weight(1f),
                            colors = SliderDefaults.colors(thumbColor = Brand.primary, activeTrackColor = Brand.primary, inactiveTrackColor = palette.separator, activeTickColor = Brand.primary.copy(alpha = 0f), inactiveTickColor = palette.separator.copy(alpha = 0f)),
                        )
                        Text("${Format.oneDecimal(settings.pressureDropThresholdHpa)} hPa", style = Type.body, color = palette.textPrimary, modifier = Modifier.width(76.dp).padding(start = 8.dp))
                    }
                }
            }
            FormSection(
                header = "Air quality",
                footer = if (settings.airQualityEnabled) "US AQI 100 is \"unhealthy for sensitive groups\". 150+ is unhealthy for everyone." else null,
            ) {
                ToggleRow("Alert on poor air quality", settings.airQualityEnabled, { settings.airQualityEnabled = it })
                if (settings.airQualityEnabled) {
                    RowDivider()
                    StepperRow("Threshold", "AQI ${settings.airQualityThreshold}", settings.airQualityThreshold > 50, settings.airQualityThreshold < 300,
                        { settings.airQualityThreshold -= 25 }, { settings.airQualityThreshold += 25 })
                }
            }
            FormSection(header = "Quiet hours") {
                ToggleRow("Don't alert at night", settings.quietHoursEnabled, { settings.quietHoursEnabled = it })
                if (settings.quietHoursEnabled) {
                    RowDivider()
                    StepperRow("From", Format.hour(settings.quietHoursStart), settings.quietHoursStart > 0, settings.quietHoursStart < 23,
                        { settings.quietHoursStart -= 1 }, { settings.quietHoursStart += 1 })
                    RowDivider()
                    StepperRow("Until", Format.hour(settings.quietHoursEnd), settings.quietHoursEnd > 0, settings.quietHoursEnd < 23,
                        { settings.quietHoursEnd -= 1 }, { settings.quietHoursEnd += 1 })
                }
            }
            FormSection(header = "How this works") {
                Text(
                    "Alerts use Open-Meteo's free public forecast, your most recent location, and your local headache history. Location and pattern analysis stay on your device.",
                    style = Type.footnote, color = palette.textPrimary, modifier = Modifier.padding(16.dp),
                )
            }
            FormSection(
                header = "Prediction",
                footer = if (settings.patternAlertsEnabled) {
                    "Analyzes your headache history on-device for recurring time patterns, then notifies you about an hour before a headache is likely. All analysis runs locally; nothing leaves your phone."
                } else {
                    "When enabled, the app analyzes your personal headache patterns and sends a heads-up about an hour before you'd typically get one."
                },
            ) {
                ToggleRow("Predict from your patterns", settings.patternAlertsEnabled, {
                    settings.patternAlertsEnabled = it
                    if (it && Build.VERSION.SDK_INT >= 33 && !Alerts.canNotify(context)) notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    graph.schedulePatternAlerts()
                })
                if (settings.patternAlertsEnabled) {
                    RowDivider()
                    Box(Modifier.padding(12.dp)) {
                        SegmentedControl(
                            listOf("High chance only", "Any chance"),
                            if (settings.patternAlertSensitivity >= 0.5) 1 else 0,
                            { settings.patternAlertSensitivity = it.toDouble(); graph.schedulePatternAlerts() },
                        )
                    }
                }
            }
        }
    }
    testMessage?.let { InfoDialog("Test Alert", it) { testMessage = null } }
}

internal fun signalStatus(signal: PersonalSignalProfile): String = when {
    signal.isSupported -> "${String.format(Locale.US, "%.1f", signal.relativeRisk)}× more likely • ${signal.headacheConditionDays} of ${signal.conditionDays} days"
    signal.totalDays < ProactiveAlertsEngine.PERSONAL_MIN_SAMPLE_SIZE -> "Learning ${signal.totalDays}/${ProactiveAlertsEngine.PERSONAL_MIN_SAMPLE_SIZE}"
    else -> "No clear pattern"
}

private fun lastAlertText(at: Long?, kind: String?): String {
    at ?: return "None yet"
    val prefix = if (kind == AlertKind.AIR_QUALITY.raw) "AQI" else "Pressure"
    return "$prefix • ${Format.dateTime(Instant.ofEpochMilli(at))}"
}

@Composable
private fun StatusRow(icon: ImageVector, title: String, value: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Brand.primary, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(title, style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
        Text(value, style = Type.body, color = palette.textSecondary)
    }
}

@Composable
private fun LinkRow(title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().tappable(title, onClick = onClick).heightIn(min = 48.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = Type.body, color = Brand.primary)
    }
}

@Composable
private fun StepperRow(title: String, value: String, canDecrease: Boolean, canIncrease: Boolean, onDecrease: () -> Unit, onIncrease: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(start = 16.dp, end = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
        Text(value, style = Type.body, color = palette.textSecondary)
        Spacer(Modifier.width(10.dp))
        Row(Modifier.clip(RoundedCornerShape(8.dp)).background(palette.separator.copy(alpha = 0.25f))) {
            StepButton(Icons.Filled.Remove, "Decrease $title", canDecrease, onDecrease)
            StepButton(Icons.Filled.Add, "Increase $title", canIncrease, onIncrease)
        }
    }
}

@Composable
private fun StepButton(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(width = 46.dp, height = 34.dp).testTag(label).tappable(label, enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = if (enabled) palette.textPrimary else palette.textTertiary, modifier = Modifier.size(18.dp))
    }
}
