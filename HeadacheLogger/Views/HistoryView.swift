import SwiftData
import SwiftUI
import RevenueCatUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: StoreService
    @Query(sort: \HeadacheEvent.timestamp, order: .reverse) private var events: [HeadacheEvent]
    @AppStorage(HeadacheStorageKey.useCelsiusTemperature.rawValue, store: HeadacheAppGroup.userDefaults) private var useCelsius = false
    // C9: a single source of truth avoids the sibling `.sheet(isPresented:)` race that
    // SwiftUI historically exhibited and keeps sheet presentation deterministic under test.
    @State private var activeSheet: ActiveSheet?
    @State private var showExportError = false
    @State private var selectedYear: Int? = nil
    /// Tracked separately from `activeSheet` because SwiftUI nils the binding before `onDismiss` fires,
    /// and we still need the temp file URL to clean it up.
    @State private var pendingExportURL: URL?
    @State private var showFileImporter = false
    @State private var showImportConfirmation = false
    @State private var showImportError = false
    @State private var importErrorMessage: String?
    @State private var importResultMessage: String?
    @State private var pendingImportRows: [[String: String]] = []
    @State private var importStrategy: ImportStrategy = .skipExisting
    @State private var showImportIntro = false
    @State private var showPaywall = false
    @State private var showQuiz = false
    @State private var quizCompleted = HeadacheQuizStore.hasCompletedQuiz
    /// Holds events pending a confirmed delete (entries older than the grace window),
    /// so an accidental swipe on a long-scrolled list can't silently drop history.
    @State private var pendingDeleteEvents: [HeadacheEvent] = []
    @State private var showDeleteConfirmation = false

    private static let deleteConfirmGraceDays = 7

    private enum ActiveSheet: Identifiable {
        case export(URL)
        case edit(UUID)

        var id: String {
            switch self {
            case .export(let url): return "export:\(url.path)"
            case .edit(let uuid): return "edit:\(uuid.uuidString)"
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    private var availableYears: [Int] {
        let years = events.compactMap { Calendar.current.component(.year, from: $0.timestamp) }
        return Array(Set(years)).sorted(by: >)
    }

    private var filteredEvents: [HeadacheEvent] {
        guard let selectedYear else { return events }
        return events.filter { Calendar.current.component(.year, from: $0.timestamp) == selectedYear }
    }

    private var emptyStateView: some View {
        let title = events.isEmpty
            ? "No Headaches Logged Yet"
            : "No Entries for \(selectedYear ?? 0)"
        let descriptionText = events.isEmpty
            ? "Use the Headache button on the One Tap tab and the app will start building a timeline you can share with your doctor."
            : "Try selecting a different year or tap All Years."
        return ContentUnavailableView(
            title,
            systemImage: "waveform.path.ecg",
            description: Text(descriptionText)
        )
        .accessibilityIdentifier("historyEmptyState")
        .listRowBackground(Color.clear)
    }

    var body: some View {
        decoratedList
    }

    private var decoratedList: some View {
        historyList
            .listStyle(.plain)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .accessibilityIdentifier("historyView")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    try? modelContext.save()
                }
            }
            .toolbar { historyToolbar }
            .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
                sheetContent(for: sheet)
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The CSV export could not be created. Please try again.")
            }
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    commitDelete(pendingDeleteEvents)
                    pendingDeleteEvents = []
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteEvents = []
                }
            } message: {
                Text("This permanently removes the entr\(pendingDeleteEvents.count == 1 ? "y" : "ies") from your history. Export a CSV first if you need a backup.")
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .modifier(ImportAlertModifier(
                showConfirmation: $showImportConfirmation,
                showError: $showImportError,
                errorMessage: $importErrorMessage,
                resultMessage: $importResultMessage,
                pendingRows: $pendingImportRows,
                importStrategy: $importStrategy,
                onSkip: { performImport(strategy: .skipExisting) },
                onOverwrite: { performImport(strategy: .overwriteExisting) }
            ))
            .sheet(isPresented: $showImportIntro) {
                ImportIntroSheet(
                    onContinue: {
                        showImportIntro = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showFileImporter = true
                        }
                    },
                    onCancel: { showImportIntro = false }
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showQuiz, onDismiss: {
                quizCompleted = HeadacheQuizStore.hasCompletedQuiz
            }) {
                NavigationStack {
                    HeadacheQuizView(hasCompleted: Binding(
                        get: { quizCompleted },
                        set: { completed in
                            quizCompleted = completed
                            if completed { showQuiz = false }
                        }
                    ))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showQuiz = false }
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .export(let url):
            ShareSheet(items: [url])
        case .edit(let targetID):
            if let event = events.first(where: { $0.id == targetID }) {
                EditEventSheet(event: event)
            }
        }
    }

    private var historyList: some View {
        List {
            if filteredEvents.isEmpty {
                emptyStateView
                if !quizCompleted {
                    quizPromptCard(prominent: true)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    SummaryGrid(events: filteredEvents, useCelsius: useCelsius)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                if !quizCompleted {
                    quizPromptCard(prominent: false)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                if !store.isProUnlocked, filteredEvents.count >= InsightsEngine.minimumSampleSize {
                    proUpsellRow
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("Entries") {
                    ForEach(filteredEvents, id: \.id) { event in
                        DetailedEventRow(event: event, useCelsius: useCelsius) {
                            activeSheet = .edit(event.id)
                        }
                        .id("history-\(event.id)-\(event.captureStatus.rawValue)")
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deleteEvents)
                }
            }

            Section {
                ImportExportActionCard(
                    icon: "square.and.arrow.up.fill",
                    title: "Export to CSV",
                    subtitle: exportSubtitle,
                    actionLabel: exportActionLabel,
                    action: { export() },
                    secondaryLabel: selectedYear != nil ? "Export all years" : nil,
                    secondaryAction: selectedYear != nil ? { exportAllYears() } : nil
                )
                ImportExportActionCard(
                    icon: "square.and.arrow.down.fill",
                    title: "Import from CSV",
                    subtitle: "Restore a backup or merge events from another device. You'll see exactly what was found and choose how to handle duplicates.",
                    actionLabel: "Start Import",
                    action: { showImportIntro = true }
                )
            } header: {
                Text("Import & Export")
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        if !events.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                yearFilterMenu
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    export()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("exportHistoryButton")
                Button {
                    showImportIntro = true
                } label: {
                    Label("Import CSV…", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("importHistoryButton")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Import or Export")
            }
        }
    }

    private var yearFilterMenu: some View {
        Menu {
            Button("All Years") {
                selectedYear = nil
            }
            .disabled(selectedYear == nil)
            Divider()
            ForEach(availableYears, id: \.self) { year in
                Button(String(year)) {
                    selectedYear = year
                }
                .disabled(selectedYear == year)
            }
        } label: {
            Label(
                selectedYear.map(String.init) ?? "All Years",
                systemImage: "calendar"
            )
            .labelStyle(.titleAndIcon)
        }
    }

    private func handleSheetDismiss() {
        removeTemporaryExport()
    }

    private var exportSubtitle: String {
        if events.isEmpty {
            return "Export your headache history to a CSV file you can share with a doctor or open in Numbers."
        }
        if let selectedYear {
            return "Exports \(filteredEvents.count) entr\(filteredEvents.count == 1 ? "y" : "ies") from \(selectedYear) — or export all years below. The CSV opens in Numbers and works for your doctor."
        }
        return "Save all \(filteredEvents.count) entr\(filteredEvents.count == 1 ? "y" : "ies") to a CSV file you can share with a doctor, open in Numbers, or back up."
    }

    private var exportActionLabel: String {
        if let selectedYear {
            return "Export \(filteredEvents.count) (\(selectedYear))"
        }
        return "Export CSV"
    }

    private func export() {
        exportEvents(filteredEvents)
    }

    private func exportAllYears() {
        exportEvents(events)
    }

    private func exportEvents(_ toExport: [HeadacheEvent]) {
        do {
            let url = try ExportService.exportCSV(events: toExport)
            pendingExportURL = url
            activeSheet = .export(url)
        } catch {
            showExportError = true
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        let targets = offsets.map { filteredEvents[$0] }
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -Self.deleteConfirmGraceDays,
            to: Date()
        ) ?? Date()
        let hasOldEntry = targets.contains { $0.timestamp < cutoff }
        if hasOldEntry {
            pendingDeleteEvents = targets
            showDeleteConfirmation = true
        } else {
            commitDelete(targets)
        }
    }

    private var deleteConfirmationTitle: String {
        pendingDeleteEvents.count == 1
            ? "Delete this entry?"
            : "Delete \(pendingDeleteEvents.count) entries?"
    }

    private func commitDelete(_ targets: [HeadacheEvent]) {
        for eventToDelete in targets {
            if let originalIndex = events.firstIndex(where: { $0.id == eventToDelete.id }) {
                modelContext.delete(events[originalIndex])
            }
        }
        do {
            try modelContext.save()
        } catch {
            print("HistoryView: delete save failed | \(error)")
        }
    }

    private func removeTemporaryExport() {
        if let url = pendingExportURL {
            try? FileManager.default.removeItem(at: url)
            pendingExportURL = nil
        }
    }

    private func handleImportResult(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importErrorMessage = "No file was selected."
                showImportError = true
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                importErrorMessage = "Cannot access the selected file."
                showImportError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let rows = try ImportService.parseCSV(from: url)
                guard !rows.isEmpty else {
                    importErrorMessage = "No valid headache events found in the file."
                    showImportError = true
                    return
                }
                pendingImportRows = rows
                showImportConfirmation = true
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func performImport(strategy: ImportStrategy) {
        let result = ImportService.importEvents(
            from: pendingImportRows,
            into: modelContext,
            strategy: strategy
        )
        pendingImportRows = []
        importResultMessage = summaryMessage(from: result)
    }

    private func summaryMessage(from result: ImportResult) -> String {
        var parts: [String] = []
        if result.imported > 0 { parts.append("\(result.imported) imported") }
        if result.overwritten > 0 { parts.append("\(result.overwritten) overwritten") }
        if result.skipped > 0 { parts.append("\(result.skipped) skipped") }
        if result.errors > 0 { parts.append("\(result.errors) errors") }
        return parts.isEmpty ? "No events were imported." : parts.joined(separator: ", ") + "."
    }

    @ViewBuilder
    private func quizPromptCard(prominent: Bool) -> some View {
        Button {
            showQuiz = true
        } label: {
            if prominent {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.bubble.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(brandColor)
                            .frame(width: 30)
                        Text("Tell us about your headaches")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Text("A short, optional quiz that helps us improve future versions of Patterns. Take it anytime.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Text("Start quiz")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(brandColor, in: Capsule())
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(brandColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(brandColor.opacity(0.25), lineWidth: 1)
                )
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(brandColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Take the headache quiz")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Optional — helps us improve future versions of Patterns.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(brandColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(brandColor.opacity(0.25), lineWidth: 1)
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("historyQuizPrompt")
    }

    private var proUpsellRow: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(brandColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Personalized patterns")
                            .font(.headline)
                        Text("Pro")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(brandColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(brandColor)
                    }
                    Text("See what time, sleep, and weather patterns emerge from your \(filteredEvents.count) logged headache\(filteredEvents.count == 1 ? "" : "s").")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }
}

private struct SummaryGrid: View {
    let events: [HeadacheEvent]
    var useCelsius: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SummaryCard(title: "Total Logs", value: "\(events.count)", tint: .pink)
                SummaryCard(title: "Most Common Day", value: mostCommonWeekday ?? "—", tint: .orange)
            }
            HStack(spacing: 12) {
                SummaryCard(title: "Most Common Time", value: mostCommonPartOfDay ?? "—", tint: .purple)
                SummaryCard(title: "Avg Temp", value: averageTemperatureText, tint: .blue)
            }
        }
        .padding(.horizontal)
    }

    private var mostCommonWeekday: String? {
        groupedMax(from: events.map(\.weekdayName))
    }

    private var mostCommonPartOfDay: String? {
        groupedMax(from: events.map { $0.partOfDay.rawValue.capitalized })
    }

    private var averageTemperatureText: String {
        let temps = events.compactMap(\.temperatureC)
        guard !temps.isEmpty else { return "—" }
        let avgC = temps.reduce(0, +) / Double(temps.count)
        if useCelsius {
            return "\(Int(avgC.rounded()))°C"
        }
        let avgF = HeadacheTemperatureFormatting.celsiusToFahrenheit(avgC)
        return "\(Int(avgF.rounded()))°F"
    }

    private func groupedMax(from values: [String]) -> String? {
        values
            .reduce(into: [:]) { counts, value in
                counts[value, default: 0] += 1
            }
            .max(by: { lhs, rhs in lhs.value < rhs.value })?
            .key
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DetailedEventRow: View {
    let event: HeadacheEvent
    var useCelsius: Bool
    var onEditNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Text("\(event.weekdayName) • \(event.partOfDay.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)

                Text(event.captureStatus.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor)

                if let severity = event.severity {
                    Text(severity.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(severityColor(severity).opacity(0.12), in: Capsule())
                        .foregroundStyle(severityColor(severity))
                }

                Button {
                    onEditNotes()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .accessibilityLabel((event.userNotes?.isEmpty == false) ? "Edit note" : "Add note")
                .accessibilityIdentifier("historyEntryNotesButton")
            }

            if let notes = event.userNotes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .accessibilityIdentifier("historyEntryNotesPreview")
            }

            if !event.locationLabel.isEmpty || event.weatherSummary != nil {
                Text([event.locationLabel.isEmpty ? nil : event.locationLabel, weatherLine]
                    .compactMap { $0 }
                    .joined(separator: " • "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                DataPill(title: "Steps", value: event.stepsToday?.formatted(.number) ?? "—")
                DataPill(title: "Sleep", value: event.sleepHoursLastNight.map { String(format: "%.1fh", $0) } ?? "—")
                DataPill(title: "hPa", value: event.pressureHpa.map { String(format: "%.0f", $0) } ?? "—")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .accessibilityIdentifier("historyEventRow")
    }

    private var weatherLine: String? {
        HeadacheTemperatureFormatting.weatherSummaryWithTemperature(
            summary: event.weatherSummary,
            celsius: event.temperatureC,
            useCelsius: useCelsius
        )
    }

    private var statusColor: Color {
        switch event.captureStatus {
        case .complete: .green
        case .partial: .orange
        case .failed: .red
        case .pending: .blue
        }
    }

    private func severityColor(_ severity: HeadacheSeverity) -> Color {
        switch severity {
        case .slight: .yellow
        case .medium: .orange
        case .extreme: .red
        }
    }
}

private struct DataPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ImportExportActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionLabel: String
    let action: () -> Void
    var secondaryLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: action) {
                    Text(actionLabel)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .controlSize(.small)
                .accessibilityIdentifier("importExportAction-\(actionLabel)")
            }
            if let secondaryLabel, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryLabel)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .padding(.leading, 36)
                .accessibilityIdentifier("importExportAction-\(secondaryLabel)")
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ImportIntroSheet: View {
    var onContinue: () -> Void
    var onCancel: () -> Void

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(brandColor)
                        Text("Import from CSV")
                            .font(.title2.bold())
                        Text("Bring entries in from a backup or another device — using a CSV file exported from this app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("How it works")
                            .font(.headline)
                        ImportStep(number: "1", title: "Pick a CSV file", detail: "On the next screen, choose a file from Files, iCloud Drive, or anywhere else you saved it.")
                        ImportStep(number: "2", title: "Review what was found", detail: "We'll tell you how many entries are in the file before saving anything.")
                        ImportStep(number: "3", title: "Choose how to handle duplicates", detail: "Skip entries that already exist, or overwrite them with values from the file.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Compatible files", systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                        Text("Use a CSV exported from this app. Other CSVs are not guaranteed to match the columns we expect.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Nothing happens until you confirm", systemImage: "checkmark.shield")
                            .font(.subheadline.weight(.semibold))
                        Text("You can cancel at any step before the final confirmation. Existing entries are never changed without your approval.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onContinue) {
                    Text("Choose CSV File")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(brandColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
    }
}

private struct ImportStep: View {
    let number: String
    let title: String
    let detail: String

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(brandColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ImportAlertModifier: ViewModifier {
    @Binding var showConfirmation: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String?
    @Binding var resultMessage: String?
    @Binding var pendingRows: [[String: String]]
    @Binding var importStrategy: ImportStrategy
    var onSkip: () -> Void
    var onOverwrite: () -> Void

    private var resultBinding: Binding<Bool> {
        Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
    }

    func body(content: Content) -> some View {
        content
            .alert("Import Data", isPresented: $showConfirmation) {
                Button("Skip Existing") {
                    onSkip()
                }
                Button("Overwrite Existing") {
                    onOverwrite()
                }
                Button("Cancel", role: .cancel) {
                    pendingRows = []
                }
            } message: {
                Text("Found \(pendingRows.count) event\(pendingRows.count == 1 ? "" : "s") in the file. How would you like to handle events that already exist?")
            }
            .alert("Import Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "The import could not be completed.")
            }
            .alert("Import Complete", isPresented: resultBinding) {
                Button("OK", role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
    }
}
