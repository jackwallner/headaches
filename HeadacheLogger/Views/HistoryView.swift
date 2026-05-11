import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
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
            } else {
                Section {
                    SummaryGrid(events: filteredEvents, useCelsius: useCelsius)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Export creates a standard CSV file", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                        Text("One row per headache with 60+ columns — timestamp, location, weather, Health app data, severity, and notes. Opens in Numbers, Excel, or Google Sheets. Share with your doctor or keep as a backup.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Label("Import reads back an exported CSV", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 4)
                        Text("Restore your data or merge events from another device. You'll be asked to skip or overwrite duplicates.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Import & Export")
                }
                .listRowBackground(Color.clear)

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
        }
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        if !events.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                yearFilterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("importHistoryButton")
                    Button {
                        export()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportHistoryButton")
                }
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

    private func export() {
        do {
            let url = try ExportService.exportCSV(events: filteredEvents)
            pendingExportURL = url
            activeSheet = .export(url)
        } catch {
            showExportError = true
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        for index in offsets {
            let eventToDelete = filteredEvents[index]
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
