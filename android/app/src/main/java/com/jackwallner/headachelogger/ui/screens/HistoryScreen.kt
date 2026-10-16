package com.jackwallner.headachelogger.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.QuestionAnswer
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.model.EventCsv
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.HeatmapData
import com.jackwallner.headachelogger.model.HeatmapDay
import com.jackwallner.headachelogger.model.HeadacheSeverity
import com.jackwallner.headachelogger.model.ImportResult
import com.jackwallner.headachelogger.model.ImportStrategy
import com.jackwallner.headachelogger.model.InsightsEngine
import com.jackwallner.headachelogger.model.Temperature
import com.jackwallner.headachelogger.ui.Format
import com.jackwallner.headachelogger.ui.LocalNav
import com.jackwallner.headachelogger.ui.Overlay
import com.jackwallner.headachelogger.ui.ReportPdf
import com.jackwallner.headachelogger.ui.severityColor
import com.jackwallner.headachelogger.ui.shareFile
import com.jackwallner.headachelogger.ui.statusColor
import com.jackwallner.headachelogger.ui.theme.Brand
import com.jackwallner.headachelogger.ui.theme.LargeTitle
import com.jackwallner.headachelogger.ui.theme.PrimaryButton
import com.jackwallner.headachelogger.ui.theme.StatusBadge
import com.jackwallner.headachelogger.ui.theme.Tint
import com.jackwallner.headachelogger.ui.theme.TopBar
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette
import com.jackwallner.headachelogger.ui.theme.tappable
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID

private const val DELETE_CONFIRM_GRACE_DAYS = 7L

/** Port of `HistoryView`: summary, 90-day heatmap, entries, quiz prompt, Pro upsell and import/export. */
@Composable
fun HistoryScreen(graph: AppGraph) {
    val nav = LocalNav.current
    val context = LocalContext.current
    val store = graph.store
    val all = graph.events.events
    var selectedYear by remember { mutableStateOf<Int?>(null) }
    var exportError by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<HeadacheEvent?>(null) }
    var importResult by remember { mutableStateOf<String?>(null) }
    val zone = ZoneId.systemDefault()
    val filtered = selectedYear?.let { year -> all.filter { it.timestamp.atZone(zone).year == year } } ?: all
    val years = all.map { it.timestamp.atZone(zone).year }.toSortedSet().reversed()
    val heatmap = HeatmapData.build(all)
    val quizDone = graph.quiz.hasCompletedQuiz

    fun share(file: File, mime: String, title: String) {
        context.shareFile(file, mime, title)
        graph.review.recordPositiveMoment()
    }
    fun exportCsv(events: List<HeadacheEvent>) {
        runCatching {
            val dir = File(context.cacheDir, "exports").apply { mkdirs() }
            File(dir, EventCsv.fileName()).apply { writeText(EventCsv.export(events)) }
        }.onSuccess { share(it, "text/csv", "Headache history") }.onFailure { exportError = true }
    }
    fun exportPdf() {
        if (!store.isPro) {
            nav.paywall("headache_history_sheet")
            return
        }
        runCatching { ReportPdf.render(all, File(context.cacheDir, "exports")) }
            .onSuccess { share(it, "application/pdf", "Headache report") }
            .onFailure { exportError = true }
    }
    fun delete(event: HeadacheEvent) {
        val cutoff = Instant.now().minusSeconds(DELETE_CONFIRM_GRACE_DAYS * 86_400)
        if (event.timestamp.isBefore(cutoff)) pendingDelete = event else graph.events.delete(event.id)
    }

    Column(Modifier.fillMaxSize().background(palette.background).testTag("historyView")) {
        LargeTitle("History") {
            if (all.isNotEmpty()) YearMenu(selectedYear, years.toList()) { selectedYear = it }
            OverflowMenu(
                pdfLabel = if (store.isPro) "Doctor PDF…" else "Doctor PDF… (Pro)",
                onPdf = ::exportPdf,
                onCsv = { exportCsv(filtered) },
                onImport = { nav.push(Overlay.ImportIntro) },
            )
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
            if (filtered.isEmpty()) {
                item { EmptyState(all.isEmpty(), selectedYear) }
                if (!quizDone) item { Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { QuizPromptCard(true) { nav.push(Overlay.Quiz) } } }
            } else {
                item { SummaryGrid(filtered, graph.settings.useCelsius) }
                if (heatmap.isNotEmpty()) {
                    item { SectionHeader("Last 90 days") }
                    item { Box(Modifier.padding(horizontal = 16.dp)) { CalendarHeatmapCard(heatmap) } }
                    item {
                        Text(
                            "Coloured cells mark days you logged a headache. Darker means a more severe attack when severity was rated.",
                            style = Type.footnote, color = palette.textSecondary, modifier = Modifier.padding(start = 32.dp, end = 32.dp, top = 6.dp, bottom = 12.dp),
                        )
                    }
                }
                if (!quizDone) item { Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp)) { QuizPromptCard(false) { nav.push(Overlay.Quiz) } } }
                if (!store.isPro && filtered.size >= InsightsEngine.MINIMUM_SAMPLE_SIZE) {
                    item { Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp)) { ProUpsellRow(filtered.size) { nav.paywall("headache_history_sheet") } } }
                }
                item { SectionHeader("Entries") }
                items(filtered, key = { it.id.toString() + it.captureStatusRaw + it.severityRaw + it.userNotes + it.timestamp }) { event ->
                    SwipeToDelete(onDelete = { delete(event) }) {
                        DetailedEventRow(event, graph.settings.useCelsius) { nav.push(Overlay.EditEvent(event.id)) }
                    }
                }
            }
            item { SectionHeader("Import & Export") }
            item {
                Column(Modifier.padding(horizontal = 16.dp).clip(RoundedCornerShape(12.dp)).background(palette.card)) {
                    ActionCard(
                        Icons.Filled.PictureAsPdf,
                        if (store.isPro) "Doctor PDF report" else "Doctor PDF report (Pro)",
                        "One-page report covering the last 90 days: attack count, severity mix, calendar heatmap, and your top patterns.",
                        if (store.isPro) "Export PDF" else "Unlock Pro",
                        ::exportPdf,
                    )
                    HorizontalDivider(Modifier.padding(start = 52.dp), thickness = 0.5.dp, color = palette.separator)
                    ActionCard(
                        Icons.Filled.Upload, "Export to CSV", exportSubtitle(all.size, filtered.size, selectedYear),
                        selectedYear?.let { "Export ${filtered.size} ($it)" } ?: "Export CSV",
                        { exportCsv(filtered) },
                        secondary = if (selectedYear != null) "Export all years" to { exportCsv(all) } else null,
                    )
                    HorizontalDivider(Modifier.padding(start = 52.dp), thickness = 0.5.dp, color = palette.separator)
                    ActionCard(
                        Icons.Filled.Download, "Import from CSV",
                        "Restore a backup or merge events from another device. You'll see exactly what was found and choose how to handle duplicates.",
                        "Start Import", { nav.push(Overlay.ImportIntro) },
                    )
                }
            }
        }
    }

    if (exportError) {
        InfoDialog("Export Failed", "The CSV export could not be created. Please try again.") { exportError = false }
    }
    pendingDelete?.let { target ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null }, containerColor = palette.card,
            title = { Text("Delete this entry?", style = Type.headline, color = palette.textPrimary) },
            text = { Text("This permanently removes the entry from your history. Export a CSV first if you need a backup.", style = Type.subhead, color = palette.textSecondary) },
            confirmButton = { TextButton({ graph.events.delete(target.id); pendingDelete = null }) { Text("Delete", color = Tint.red) } },
            dismissButton = { TextButton({ pendingDelete = null }) { Text("Cancel", color = Brand.primary) } },
        )
    }
    nav.pendingImportRows?.let { rows ->
        AlertDialog(
            onDismissRequest = { nav.pendingImportRows = null }, containerColor = palette.card,
            title = { Text("Import Data", style = Type.headline, color = palette.textPrimary) },
            text = {
                Text(
                    "Found ${rows.size} event${if (rows.size == 1) "" else "s"} in the file. How would you like to handle events that already exist?",
                    style = Type.subhead, color = palette.textSecondary,
                )
            },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton({ importResult = summary(graph.events.importRows(rows, ImportStrategy.SKIP_EXISTING)); nav.pendingImportRows = null }) {
                        Text("Skip Existing", color = Brand.primary)
                    }
                    TextButton({ importResult = summary(graph.events.importRows(rows, ImportStrategy.OVERWRITE_EXISTING)); nav.pendingImportRows = null }) {
                        Text("Overwrite Existing", color = Brand.primary)
                    }
                    TextButton({ nav.pendingImportRows = null }) { Text("Cancel", color = palette.textSecondary) }
                }
            },
        )
    }
    nav.importError?.let { InfoDialog("Import Failed", it) { nav.importError = null } }
    importResult?.let { InfoDialog("Import Complete", it) { importResult = null } }
}

private fun summary(result: ImportResult): String {
    val parts = buildList {
        if (result.imported > 0) add("${result.imported} imported")
        if (result.overwritten > 0) add("${result.overwritten} overwritten")
        if (result.skipped > 0) add("${result.skipped} skipped")
        if (result.errors > 0) add("${result.errors} errors")
    }
    return if (parts.isEmpty()) "No events were imported." else parts.joinToString(", ") + "."
}

private fun exportSubtitle(total: Int, filtered: Int, year: Int?): String {
    val entries = if (filtered == 1) "entry" else "entries"
    return when {
        total == 0 -> "Export your headache history to a CSV file you can share with a doctor or open in a spreadsheet."
        year != null -> "Exports $filtered $entries from $year, or export all years below. The CSV opens in any spreadsheet and works for your doctor."
        else -> "Save all $filtered $entries to a CSV file you can share with a doctor, open in a spreadsheet, or back up."
    }
}

@Composable
fun InfoDialog(title: String, message: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = palette.card,
        title = { Text(title, style = Type.headline, color = palette.textPrimary) },
        text = { Text(message, style = Type.subhead, color = palette.textSecondary) },
        confirmButton = { TextButton(onDismiss) { Text("OK", color = Brand.primary) } },
    )
}

@Composable
private fun SectionHeader(title: String) {
    Text(title.uppercase(), style = Type.footnote, color = palette.textSecondary, modifier = Modifier.padding(start = 32.dp, top = 16.dp, bottom = 6.dp))
}

@Composable
private fun YearMenu(selected: Int?, years: List<Int>, onSelect: (Int?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.clip(RoundedCornerShape(10.dp)).tappable("Filter by year") { open = true }.heightIn(min = 44.dp).padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.CalendarMonth, null, tint = Brand.primary, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(4.dp))
            Text(selected?.toString() ?: "All Years", style = Type.body, color = Brand.primary)
        }
        DropdownMenu(open, { open = false }, containerColor = palette.card) {
            DropdownMenuItem({ Text("All Years", color = palette.textPrimary) }, { onSelect(null); open = false }, enabled = selected != null)
            HorizontalDivider(color = palette.separator)
            years.forEach { year ->
                DropdownMenuItem({ Text(year.toString(), color = palette.textPrimary) }, { onSelect(year); open = false }, enabled = selected != year)
            }
        }
    }
}

@Composable
private fun OverflowMenu(pdfLabel: String, onPdf: () -> Unit, onCsv: () -> Unit, onImport: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Box(Modifier.size(44.dp).clip(CircleShape).testTag("historyMenu").tappable("Import or Export") { open = true }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.MoreHoriz, null, tint = Brand.primary)
        }
        DropdownMenu(open, { open = false }, containerColor = palette.card) {
            MenuItem(pdfLabel, Icons.Filled.Description, "exportPDFButton") { open = false; onPdf() }
            MenuItem("Export CSV", Icons.Filled.Upload, "exportHistoryButton") { open = false; onCsv() }
            MenuItem("Import CSV…", Icons.Filled.Download, "importHistoryButton") { open = false; onImport() }
        }
    }
}

@Composable
private fun MenuItem(label: String, icon: ImageVector, tag: String, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label, color = palette.textPrimary) }, onClick = onClick, modifier = Modifier.testTag(tag),
        trailingIcon = { Icon(icon, null, tint = palette.textPrimary) },
    )
}

@Composable
private fun EmptyState(noEvents: Boolean, year: Int?) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 40.dp).testTag("historyEmptyState"),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.MonitorHeart, null, tint = palette.textSecondary, modifier = Modifier.size(44.dp))
        Text(if (noEvents) "No Headaches Logged Yet" else "No Entries for ${year ?: 0}", style = Type.title2, color = palette.textPrimary, textAlign = TextAlign.Center)
        Text(
            if (noEvents) "Use the Headache button on the One Tap tab and the app will start building a timeline you can share with your doctor."
            else "Try selecting a different year or tap All Years.",
            style = Type.subhead, color = palette.textSecondary, textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun QuizPromptCard(prominent: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    if (prominent) {
        Column(
            Modifier.fillMaxWidth().clip(shape).background(Brand.primary.copy(alpha = 0.08f)).border(1.dp, Brand.primary.copy(alpha = 0.25f), shape)
                .testTag("historyQuizPrompt").tappable("Tell us about your headaches", onClick = onClick).padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.QuestionAnswer, null, tint = Brand.primary, modifier = Modifier.size(26.dp))
                Spacer(Modifier.width(12.dp))
                Text("Tell us about your headaches", style = Type.headline, color = palette.textPrimary)
            }
            Text("A few quick questions so Patterns can surface the triggers most relevant to you. Take it anytime.", style = Type.subhead, color = palette.textSecondary)
            Text(
                "Start quiz", style = Type.subheadBold, color = Color.White,
                modifier = Modifier.clip(CircleShape).background(Brand.primary).padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
    } else {
        Row(
            Modifier.fillMaxWidth().clip(shape).background(palette.card).testTag("historyQuizPrompt").tappable("Take the headache quiz", onClick = onClick).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.QuestionAnswer, null, tint = Brand.primary, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Take the headache quiz", style = Type.headline, color = palette.textPrimary)
                Text("Optional. Helps Patterns surface the triggers most relevant to you.", style = Type.footnote, color = palette.textSecondary)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.textTertiary)
        }
    }
}

@Composable
private fun ProUpsellRow(count: Int, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(palette.card).tappable("Personalized patterns", onClick = onClick).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.BarChart, null, tint = Brand.primary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Personalized patterns", style = Type.headline, color = palette.textPrimary)
                Spacer(Modifier.width(6.dp))
                ProBadge()
            }
            Text(
                "See what time, sleep, and weather patterns emerge from your $count logged headache${if (count == 1) "" else "s"}.",
                style = Type.footnote, color = palette.textSecondary,
            )
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.textTertiary)
    }
}

@Composable
fun ProBadge() {
    Text(
        "Pro", style = Type.of(11.sp, FontWeight.Bold), color = Brand.primary,
        modifier = Modifier.clip(CircleShape).background(Brand.primary.copy(alpha = 0.15f)).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

@Composable
private fun SummaryGrid(events: List<HeadacheEvent>, useCelsius: Boolean) {
    fun <T> mode(values: List<T>): T? = values.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key
    val temps = events.mapNotNull { it.temperatureC }
    val avg = if (temps.isEmpty()) "–" else temps.average().let { c ->
        if (useCelsius) "${Math.round(c)}°C" else "${Math.round(Temperature.celsiusToFahrenheit(c))}°F"
    }
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SummaryCard("Total Logs", events.size.toString(), Tint.pink, Modifier.weight(1f))
            SummaryCard("Most Common Day", mode(events.map { it.weekdayName }) ?: "–", Tint.orange, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SummaryCard("Most Common Time", mode(events.map { it.partOfDay.title }) ?: "–", Tint.purple, Modifier.weight(1f))
            SummaryCard("Avg Temp", avg, Tint.blue, Modifier.weight(1f))
        }
    }
}

@Composable
private fun SummaryCard(title: String, value: String, tint: Color, modifier: Modifier) {
    Column(modifier.clip(RoundedCornerShape(18.dp)).background(palette.card).padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = Type.caption, color = palette.textSecondary)
        Text(value, style = Type.title3.copy(fontWeight = FontWeight.Bold), color = tint, maxLines = 1)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDelete(onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        onDismiss = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) onDelete()
            scope.launch { state.reset() }
        },
        backgroundContent = {
            Box(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 8.dp).clip(RoundedCornerShape(18.dp)).background(Tint.red), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Filled.Delete, "Delete", tint = Color.White, modifier = Modifier.padding(end = 24.dp))
            }
        },
    ) { content() }
}

@Composable
private fun DetailedEventRow(event: HeadacheEvent, useCelsius: Boolean, onEdit: () -> Unit) {
    Column(
        Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(palette.card)
            .padding(16.dp).testTag("historyEventRow"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(Format.dateTime(event.timestamp), style = Type.headline, color = palette.textPrimary)
                Text("${event.weekdayName} • ${event.partOfDay.title}", style = Type.caption, color = palette.textSecondary)
            }
            Spacer(Modifier.width(8.dp))
            StatusBadge(event.captureStatus.raw.replaceFirstChar(Char::uppercaseChar), statusColor(event.captureStatus))
            event.severity?.let {
                Spacer(Modifier.width(6.dp))
                StatusBadge(it.title, severityColor(it))
            }
            Box(
                Modifier.size(40.dp).clip(CircleShape).testTag("historyEntryNotesButton")
                    .tappable(if (event.userNotes.isNullOrEmpty()) "Add note" else "Edit note", onClick = onEdit),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.EditNote, null, tint = Brand.primary) }
        }
        event.userNotes?.takeIf { it.isNotEmpty() }?.let {
            Text(it, style = Type.footnote, color = palette.textSecondary, maxLines = 4, modifier = Modifier.testTag("historyEntryNotesPreview"))
        }
        val weather = Temperature.weatherSummaryWithTemperature(event.weatherSummary, event.temperatureC, useCelsius)
        if (event.locationLabel.isNotEmpty() || event.weatherSummary != null) {
            Text(listOfNotNull(event.locationLabel.ifEmpty { null }, weather).joinToString(" • "), style = Type.subhead, color = palette.textSecondary)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DataPill("Sleep", event.sleepHoursLastNight?.let { "${Format.oneDecimal(it)}h" } ?: "–")
            DataPill("hPa", event.pressureHpa?.let { String.format(java.util.Locale.US, "%.0f", it) } ?: "–")
            DataPill("AQI", event.usAQI?.let { String.format(java.util.Locale.US, "%.0f", it) } ?: "–")
        }
    }
}

@Composable
private fun DataPill(title: String, value: String) {
    Column(Modifier.clip(RoundedCornerShape(12.dp)).background(palette.cardRaised).padding(horizontal = 10.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, style = Type.caption2, color = palette.textSecondary)
        Text(value, style = Type.subhead, color = palette.textPrimary)
    }
}

@Composable
private fun ActionCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    action: String,
    onAction: () -> Unit,
    secondary: Pair<String, () -> Unit>? = null,
) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = Brand.primary, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = Type.subheadBold, color = palette.textPrimary)
                Text(subtitle, style = Type.caption, color = palette.textSecondary)
            }
            Spacer(Modifier.width(10.dp))
            Text(
                action, style = Type.captionBold, color = Color.White, maxLines = 1,
                modifier = Modifier.clip(CircleShape).background(Brand.primary).testTag("importExportAction-$action")
                    .tappable(action, onClick = onAction).padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
        secondary?.let { (label, onClick) ->
            Text(
                label, style = Type.captionBold, color = Brand.primary,
                modifier = Modifier.padding(start = 36.dp).clip(RoundedCornerShape(6.dp)).testTag("importExportAction-$label").tappable(label, onClick = onClick).padding(6.dp),
            )
        }
    }
}

// Heatmap

fun heatmapColor(day: HeatmapDay?, empty: Color): Color {
    day ?: return Color.Transparent
    if (day.count == 0) return empty
    val alpha = when (day.peakSeverity) {
        HeadacheSeverity.SLIGHT -> 0.35f
        HeadacheSeverity.MEDIUM -> 0.65f
        HeadacheSeverity.EXTREME -> 0.95f
        null -> if (day.count >= 2) 0.75f else 0.50f
    }
    return Brand.primary.copy(alpha = alpha)
}

@Composable
fun CalendarHeatmapCard(days: List<HeatmapDay>) {
    val headacheDays = days.count { it.count > 0 }
    val empty = palette.textSecondary.copy(alpha = 0.15f)
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(palette.card).padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HeatmapGrid(days, empty)
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Chip(headacheDays, "headache days")
            Chip(days.size - headacheDays, "headache-free")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Less", style = Type.caption2, color = palette.textSecondary)
            val now = java.time.LocalDate.now()
            listOf(
                HeatmapDay(now, 0, null), HeatmapDay(now, 1, HeadacheSeverity.SLIGHT), HeatmapDay(now, 1, HeadacheSeverity.MEDIUM),
                HeatmapDay(now, 1, HeadacheSeverity.EXTREME), HeatmapDay(now, 3, HeadacheSeverity.EXTREME),
            ).forEach { Box(Modifier.size(12.dp).clip(RoundedCornerShape(3.dp)).background(heatmapColor(it, empty))) }
            Text("More", style = Type.caption2, color = palette.textSecondary)
        }
    }
}

@Composable
private fun Chip(value: Int, label: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("$value", style = Type.captionBold, color = palette.textPrimary)
        Text(label, style = Type.caption, color = palette.textSecondary)
    }
}

@Composable
private fun HeatmapGrid(days: List<HeatmapDay>, empty: Color) {
    val first = days.firstOrNull() ?: return
    val cells: List<HeatmapDay?> = List(first.date.dayOfWeek.value % 7) { null } + days
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        cells.chunked(7).forEach { column ->
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                column.forEach { day -> Box(Modifier.size(14.dp).clip(RoundedCornerShape(3.dp)).background(heatmapColor(day, empty))) }
            }
        }
    }
}

// Import intro

/** Port of `ImportIntroSheet`; picking a file hands the parsed rows back to History's alerts. */
@Composable
fun ImportIntroScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val nav = LocalNav.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        onClose()
        uri ?: return@rememberLauncherForActivityResult
        val text = runCatching { context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() } }.getOrNull()
        if (text == null) {
            nav.importError = "Cannot access the selected file."
            return@rememberLauncherForActivityResult
        }
        runCatching { EventCsv.parse(text) }
            .onSuccess { rows -> if (rows.isEmpty()) nav.importError = "No valid headache events found in the file." else nav.pendingImportRows = rows }
            .onFailure { nav.importError = it.message ?: "The import could not be completed." }
    }
    Column(Modifier.fillMaxSize().background(palette.background)) {
        TopBar("Import", leading = "Cancel" to onClose)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Download, null, tint = Brand.primary, modifier = Modifier.size(40.dp))
                Text("Import from CSV", style = Type.title2, color = palette.textPrimary)
                Text("Bring entries in from a backup or another device, using a CSV file exported from this app.", style = Type.subhead, color = palette.textSecondary)
            }
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("How it works", style = Type.headline, color = palette.textPrimary)
                ImportStep("1", "Pick a CSV file", "On the next screen, choose a file from your device, Google Drive, or anywhere else you saved it.")
                ImportStep("2", "Review what was found", "We'll tell you how many entries are in the file before saving anything.")
                ImportStep("3", "Choose how to handle duplicates", "Skip entries that already exist, or overwrite them with values from the file.")
            }
            Note(Icons.Filled.Description, "Compatible files", "Use a CSV exported from this app. Other CSVs are not guaranteed to match the columns we expect.")
            Note(Icons.Filled.VerifiedUser, "Nothing happens until you confirm", "You can cancel at any step before the final confirmation. Existing entries are never changed without your approval.")
        }
        Box(Modifier.fillMaxWidth().background(palette.card).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 20.dp, vertical = 12.dp)) {
            PrimaryButton(
                "Choose CSV File",
                { picker.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "application/csv")) },
                brush = androidx.compose.ui.graphics.SolidColor(Brand.primary),
            )
        }
    }
}

@Composable
private fun ImportStep(number: String, title: String, detail: String) {
    Row(verticalAlignment = Alignment.Top) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(Brand.primary), contentAlignment = Alignment.Center) {
            Text(number, style = Type.headline, color = Color.White)
        }
        Spacer(Modifier.width(14.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Type.subheadBold, color = palette.textPrimary)
            Text(detail, style = Type.footnote, color = palette.textSecondary)
        }
    }
}

@Composable
private fun Note(icon: ImageVector, title: String, detail: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = Brand.primary, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(title, style = Type.subheadBold, color = palette.textPrimary)
        }
        Text(detail, style = Type.footnote, color = palette.textSecondary)
    }
}

// Edit event

/** Port of `EditEventSheet`: date and time, severity and notes; moving the time recomputes calendar fields. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditEventScreen(graph: AppGraph, id: UUID, onClose: () -> Unit) {
    val event = graph.events.find(id)
    if (event == null) {
        onClose()
        return
    }
    val zone = ZoneId.systemDefault()
    val local = remember(id) { event.timestamp.atZone(zone).toLocalDateTime() }
    val dateState = rememberDatePickerState(
        initialSelectedDateMillis = local.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        selectableDates = object : androidx.compose.material3.SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= System.currentTimeMillis() + 86_400_000
        },
    )
    val timeState = rememberTimePickerState(local.hour, local.minute)
    var severity by remember(id) { mutableStateOf(event.severity) }
    var notes by remember(id) { mutableStateOf(event.userNotes ?: "") }
    var showTime by remember { mutableStateOf(false) }

    fun save() {
        val date = dateState.selectedDateMillis?.let { Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() } ?: local.toLocalDate()
        val next = LocalDateTime.of(date, java.time.LocalTime.of(timeState.hour, timeState.minute)).atZone(zone).toInstant()
        if (local.withSecond(0).withNano(0) != LocalDateTime.ofInstant(next, zone)) event.reschedule(next, zone)
        event.severity = severity
        event.userNotes = notes.trim().ifEmpty { null }
        graph.events.save()
        onClose()
    }

    val pickerColors = DatePickerDefaults.colors(
        containerColor = palette.card, selectedDayContainerColor = Brand.primary, todayDateBorderColor = Brand.primary,
        todayContentColor = Brand.primary, dayContentColor = palette.textPrimary, weekdayContentColor = palette.textSecondary,
        navigationContentColor = palette.textPrimary, yearContentColor = palette.textPrimary, currentYearContentColor = Brand.primary,
        selectedYearContainerColor = Brand.primary, subheadContentColor = palette.textSecondary,
    )
    Column(Modifier.fillMaxSize().background(palette.background).testTag("editEventSheet")) {
        TopBar("Edit Event", leading = "Cancel" to onClose, trailing = "Save" to ::save, trailingBold = true)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("WHEN DID THE HEADACHE OCCUR?", style = Type.footnote, color = palette.textSecondary, modifier = Modifier.padding(start = 16.dp))
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(palette.card)) {
                    DatePicker(dateState, title = null, headline = null, showModeToggle = false, colors = pickerColors)
                    HorizontalDivider(color = palette.separator, thickness = 0.5.dp)
                    Row(
                        Modifier.fillMaxWidth().tappable("Time") { showTime = !showTime }.heightIn(min = 48.dp).padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Time", style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
                        Text(
                            Format.hourMinute(timeState.hour, timeState.minute), style = Type.body, color = Brand.primary,
                            modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(palette.cardRaised).padding(horizontal = 10.dp, vertical = 6.dp),
                        )
                    }
                    if (showTime) {
                        Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                            TimePicker(
                                timeState,
                                colors = TimePickerDefaults.colors(
                                    clockDialColor = palette.cardRaised, selectorColor = Brand.primary, timeSelectorSelectedContainerColor = Brand.primary.copy(alpha = 0.2f),
                                    timeSelectorSelectedContentColor = palette.textPrimary, timeSelectorUnselectedContainerColor = palette.cardRaised,
                                    timeSelectorUnselectedContentColor = palette.textPrimary, periodSelectorSelectedContainerColor = Brand.primary.copy(alpha = 0.2f),
                                    clockDialUnselectedContentColor = palette.textPrimary,
                                ),
                            )
                        }
                    }
                }
            }
            SeverityPicker(severity) { severity = it }
            NotesField(notes) { notes = it }
            Spacer(Modifier.height(24.dp))
        }
    }
}
