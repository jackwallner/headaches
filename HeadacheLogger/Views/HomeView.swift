import SwiftData
import SwiftUI
import UIKit
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator
    @EnvironmentObject private var store: StoreService
    @AppStorage(HeadacheStorageKey.useCelsiusTemperature.rawValue, store: HeadacheAppGroup.userDefaults) private var useCelsius = false
    @AppStorage(HeadacheStorageKey.promptForSeverityNotes.rawValue, store: HeadacheAppGroup.userDefaults) private var promptForSeverityNotes = false
    @AppStorage(HeadacheStorageKey.milestonePrompt3Shown.rawValue, store: HeadacheAppGroup.userDefaults) private var milestone3PromptShown = false
    @AppStorage(HeadacheStorageKey.milestonePrompt5Shown.rawValue, store: HeadacheAppGroup.userDefaults) private var milestone5PromptShown = false
    @AppStorage(HeadacheStorageKey.milestonePrompt10Shown.rawValue, store: HeadacheAppGroup.userDefaults) private var milestone10PromptShown = false
    @Query(sort: \HeadacheEvent.timestamp, order: .reverse) private var events: [HeadacheEvent]
    @State private var severityNotesEventID: UUID?
    @State private var showSeverityNotesSheet = false
    @State private var showCheckmark = false
    @State private var showPaywall = false
    /// Drives the bottom Undo / Add Details snackbar. Set when a tap completes and
    /// auto-clears after `undoSnackbarTTLSeconds` so the controls don't linger forever.
    @State private var undoSnackbarVisible = false
    @State private var undoDismissTask: Task<Void, Never>?

    private static let undoSnackbarTTLSeconds: UInt64 = 15
    /// Once the user has logged this many times, the long "What Gets Captured"
    /// explainer collapses so Home stays focused on action + latest + recent.
    private static let captureExplainerLogThreshold = 3

    private var latestEvent: HeadacheEvent? { events.first }
    // C18: skip the latest event so it doesn't duplicate between LatestEventCard and Recent Logs.
    private var recentEvents: [HeadacheEvent] { Array(events.dropFirst().prefix(3)) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 14) {
                    Button {
                        let success = captureCoordinator.captureHeadache(in: modelContext)
                        if success && promptForSeverityNotes {
                            let capturedID = captureCoordinator.lastCapturedEventID
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                if let capturedID, captureCoordinator.lastCapturedEventID == capturedID {
                                    showDetails(for: capturedID)
                                }
                            }
                        }
                    } label: {
                        VStack(spacing: 14) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 56, weight: .bold))
                            Text("Log Headache")
                                .font(.system(size: 28, weight: .heavy))
                            Text(captureCoordinator.isCapturing ? "Saving and collecting context..." : "Tap once, we'll record the moment")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.95, green: 0.25, blue: 0.36), Color(red: 0.86, green: 0.16, blue: 0.43)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                        .shadow(color: Color(red: 0.86, green: 0.16, blue: 0.43).opacity(0.30), radius: 18, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(captureCoordinator.isCapturing || showCheckmark)
                    .accessibilityLabel("Log headache")
                    .accessibilityIdentifier("logHeadacheButton")
                    .overlay {
                        if showCheckmark {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.ultraThinMaterial)
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.green)
                                Text("Logged")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }
                            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: showCheckmark)

                    if !captureCoordinator.isCapturing, let statusLine = captureCoordinator.bannerMessage {
                        CaptureStatusLine(text: statusLine, isError: captureCoordinator.bannerIsError) {
                            captureCoordinator.bannerMessage = nil
                        }
                        .id("status-\(statusLine)")
                    }
                }

                if let latestEvent {
                    LatestEventCard(event: latestEvent, useCelsius: useCelsius)
                        .id("\(latestEvent.id)-\(latestEvent.captureStatus.rawValue)-\(latestEvent.captureCompletedAt?.timeIntervalSince1970 ?? 0)")

                    if latestEvent.captureStatus == .partial || latestEvent.captureStatus == .failed {
                        CaptureRecoveryCard(
                            event: latestEvent,
                            isRetrying: captureCoordinator.isCapturing,
                            onRetry: {
                                captureCoordinator.retryCapture(eventID: latestEvent.id, in: modelContext)
                            }
                        )
                        .id("recovery-\(latestEvent.id)-\(latestEvent.captureStatus.rawValue)-\(captureCoordinator.isCapturing)")
                    }
                }

                if let milestone = activeMilestone {
                    MilestoneProPrompt(milestone: milestone, showPaywall: $showPaywall, onDismiss: markMilestoneShown)
                        .onAppear { captureCoordinator.proPromptShownThisSession = true }
                }

                if !recentEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Previous entries")
                                .font(.headline)
                            Spacer()
                            Text("See all in History")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(recentEvents, id: \.id) { event in
                            RecentEventRow(event: event)
                                .id("recent-\(event.id)-\(event.captureStatus.rawValue)")
                        }
                    }
                }

                if events.count < Self.captureExplainerLogThreshold {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What Gets Captured")
                            .font(.headline)
                        Text("Press once when a headache starts; the app records the moment and fills in as much health and environmental context as it can.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        CaptureItem(
                            icon: "clock",
                            title: "Time context",
                            subtitle: "Date, weekday, hour, minute, timezone, and part of day."
                        )
                        CaptureItem(
                            icon: "heart.text.square",
                            title: "Apple Health context",
                            subtitle: "Activity (including stand time and flights), sleep duration plus inferred wake time, heart metrics (including SpO₂ and VO₂ max when logged), audio exposure, mindful minutes, barometric change, breathing, and recent workouts, all without typing."
                        )
                        CaptureItem(
                            icon: "cloud.sun",
                            title: "Weather and environment",
                            subtitle: "Location-based weather, pressure, air quality, UV, and pollen-style signals when available."
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("One Tap Headache Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("homeView")
        .safeAreaInset(edge: .bottom) {
            if undoSnackbarVisible, let eventID = captureCoordinator.lastCapturedEventID {
                UndoSnackbar(
                    onAddDetails: { showDetails(for: eventID) },
                    onUndo: {
                        captureCoordinator.undoLastCapture(in: modelContext)
                        dismissUndoSnackbar()
                    },
                    onDismiss: { dismissUndoSnackbar() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: captureCoordinator.isCapturing) { _, isCapturing in
            if !isCapturing, captureCoordinator.lastCapturedEventID != nil {
                showCheckmark = true
                Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showCheckmark = false
                    }
                }
                showUndoSnackbar()
            }
        }
        .onChange(of: captureCoordinator.lastCapturedEventID) { _, newValue in
            if newValue == nil { dismissUndoSnackbar() }
        }
        .sheet(isPresented: $showSeverityNotesSheet, onDismiss: { severityNotesEventID = nil }) {
            if let eventID = severityNotesEventID {
                SeverityNotesSheet(eventID: eventID)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
                .task { store.trackPaywallImpression(id: "headache_home_sheet") }
        }
    }

    private func showDetails(for eventID: UUID) {
        severityNotesEventID = eventID
        showSeverityNotesSheet = true
    }

    private func showUndoSnackbar() {
        undoDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            undoSnackbarVisible = true
        }
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.undoSnackbarTTLSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                undoSnackbarVisible = false
            }
        }
    }

    private func dismissUndoSnackbar() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            undoSnackbarVisible = false
        }
    }

    fileprivate enum ProMilestone: Int, Equatable {
        case threeLogs = 3
        case fiveLogs = 5
        case tenLogs = 10

        var title: String {
            switch self {
            case .threeLogs: return "You've logged \(rawValue) headaches"
            case .fiveLogs: return "\(rawValue) headaches logged, enough for patterns"
            case .tenLogs: return "\(rawValue) headaches, meaningful data"
            }
        }

        var detail: String {
            switch self {
            case .threeLogs: return "Great start! Pro reveals the patterns hiding in your logs: time, sleep, weather, and more."
            case .fiveLogs: return "You have enough data for personalized pattern analysis. Pro finds what's triggering your headaches."
            case .tenLogs: return "You've built enough history for meaningful patterns. Unlock Pro to see your personalized patterns and get proactive alerts."
            }
        }

        var icon: String {
            switch self {
            case .threeLogs: return "chart.bar"
            case .fiveLogs: return "sparkles"
            case .tenLogs: return "bolt.fill"
            }
        }
    }

    private var activeMilestone: ProMilestone? {
        guard !store.isProUnlocked else { return nil }
        // One Pro moment per session: if a trial offer already fired, skip the milestone.
        guard !captureCoordinator.proPromptShownThisSession else { return nil }
        let count = events.count
        if count >= 10, !milestone10PromptShown { return .tenLogs }
        if count >= 5, !milestone5PromptShown { return .fiveLogs }
        if count >= 3, !milestone3PromptShown { return .threeLogs }
        return nil
    }

    private func markMilestoneShown(_ milestone: ProMilestone) {
        switch milestone {
        case .threeLogs: milestone3PromptShown = true
        case .fiveLogs: milestone5PromptShown = true
        case .tenLogs: milestone10PromptShown = true
        }
    }
}

private struct LatestEventCard: View {
    let event: HeadacheEvent
    var useCelsius: Bool
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Event")
                    .font(.headline)
                Spacer()
                if let severity = event.severity {
                    StatusBadge(label: severity.rawValue.capitalized, tint: severityColor(severity))
                }
            }

            Text(plainSummary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("latestEventSummary")

            HStack(spacing: 12) {
                MetricChip(
                    title: "Steps",
                    value: event.stepsToday?.formatted(.number) ?? "—",
                    tint: .teal
                )
                MetricChip(
                    title: "Sleep",
                    value: event.sleepHoursLastNight.map { String(format: "%.1f h", $0) } ?? "—",
                    tint: .indigo
                )
                MetricChip(
                    title: "AQI",
                    value: event.usAQI.map { String(format: "%.0f", $0) } ?? "—",
                    tint: .mint
                )
            }

            if hasMissingContext {
                DisclosureGroup(isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusBadge(label: "Health: \(event.healthStatus.rawValue)", tint: event.healthStatus == .captured ? .green : .orange)
                        StatusBadge(label: "Environment: \(event.environmentStatus.rawValue)", tint: event.environmentStatus == .captured ? .blue : .orange)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Why is something missing?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("latestEventDetailsDisclosure")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("latestEventCard")
    }

    private var plainSummary: String {
        var parts: [String] = []

        let weekday = event.weekdayName
        let timeString = event.timestamp.formatted(date: .omitted, time: .shortened)
        parts.append("\(weekday) \(timeString) · \(event.partOfDay.rawValue.capitalized)")

        if let weather = weatherHeadline { parts.append(weather) }
        else if !event.locationLabel.isEmpty { parts.append(event.locationLabel) }

        if let pressureWord = pressureSummary { parts.append(pressureWord) }
        if let sleep = event.sleepHoursLastNight {
            parts.append("slept \(String(format: "%.1f", sleep))h")
        }
        return parts.joined(separator: " · ")
    }

    private var weatherHeadline: String? {
        HeadacheTemperatureFormatting.weatherSummaryWithTemperature(
            summary: event.weatherSummary,
            celsius: event.temperatureC,
            useCelsius: useCelsius
        )
    }

    private var pressureSummary: String? {
        switch event.pressureTrend {
        case .falling: return "pressure falling"
        case .rising: return "pressure rising"
        case .steady, .unavailable: return nil
        }
    }

    private var hasMissingContext: Bool {
        event.healthStatus != .captured || event.environmentStatus != .captured
    }

    private func severityColor(_ severity: HeadacheSeverity) -> Color {
        switch severity {
        case .slight: .yellow
        case .medium: .orange
        case .extreme: .red
        }
    }
}

private struct RecentEventRow: View {
    let event: HeadacheEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(event.partOfDay.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(event.locationLabel.isEmpty ? "Location unavailable" : event.locationLabel, systemImage: "location")
                Spacer()
                Label(event.weatherSummary ?? "No weather", systemImage: "cloud")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("recentEventRow")
    }
}

private struct CaptureItem: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CaptureRecoveryCard: View {
    let event: HeadacheEvent
    var isRetrying: Bool
    var onRetry: () -> Void
    @Environment(\.openURL) private var openURL

    private var healthIssue: String? {
        guard event.healthStatus != .captured else { return nil }
        let detail = event.healthStatusMessage ?? "no detail"
        return "Health \(event.healthStatus.rawValue): \(detail)"
    }

    private var environmentIssue: String? {
        guard event.environmentStatus != .captured else { return nil }
        let detail = event.environmentStatusMessage ?? "no detail"
        return "Environment \(event.environmentStatus.rawValue): \(detail)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Some context couldn't be captured", systemImage: "exclamationmark.bubble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                if let healthIssue {
                    Text(healthIssue)
                }
                if let environmentIssue {
                    Text(environmentIssue)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                onRetry()
            } label: {
                if isRetrying {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Try Again")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isRetrying)
            .accessibilityIdentifier("captureRetryButton")

            DisclosureGroup("Still stuck?") {
                Button {
                    if let url = mailURL() {
                        openURL(url)
                    }
                } label: {
                    Text("Email Developer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
                .accessibilityIdentifier("captureReportButton")
            }
            .font(.footnote)
            .tint(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .accessibilityIdentifier("captureRecoveryCard")
    }

    private func mailURL() -> URL? {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model

        let tsFormatter = ISO8601DateFormatter()
        let bodyLines: [String] = [
            "Hi Jack,",
            "",
            "Context capture hit an issue after logging a headache. Details below.",
            "",
            "- App version: \(version) (\(build))",
            "- iOS: \(iosVersion) on \(deviceModel)",
            "- Event ID: \(event.id.uuidString)",
            "- Event time: \(tsFormatter.string(from: event.timestamp))",
            "- Capture status: \(event.captureStatus.rawValue)",
            "- Health status: \(event.healthStatus.rawValue)\(event.healthStatusMessage.map { ": \($0)" } ?? "")",
            "- Environment status: \(event.environmentStatus.rawValue)\(event.environmentStatusMessage.map { ": \($0)" } ?? "")",
            "",
            "Anything else you want to add:",
            "",
        ]

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "jackwallner@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "One Tap Headache Tracker: capture failed"),
            URLQueryItem(name: "body", value: bodyLines.joined(separator: "\n")),
        ]
        return components.url
    }
}

private struct SeverityNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let eventID: UUID
    @State private var selectedSeverity: HeadacheSeverity?
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Severity")
                        .font(.headline)
                    Picker("Severity", selection: $selectedSeverity) {
                        Text("Not set").tag(Optional<HeadacheSeverity>.none)
                        ForEach(HeadacheSeverity.allCases, id: \.self) { severity in
                            Text(severity.rawValue.capitalized).tag(Optional(severity))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Headache Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        var descriptor = FetchDescriptor<HeadacheEvent>(predicate: #Predicate { $0.id == eventID })
        descriptor.fetchLimit = 1
        guard let event = try? modelContext.fetch(descriptor).first else { return }
        event.severity = selectedSeverity
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.userNotes = trimmed.isEmpty ? nil : trimmed
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("SeverityNotesSheet: save failed | \(error)")
            #endif
        }
    }
}

private struct MilestoneProPrompt: View {
    let milestone: HomeView.ProMilestone
    @Binding var showPaywall: Bool
    var onDismiss: (HomeView.ProMilestone) -> Void

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: milestone.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(brandColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(milestone.title)
                        .font(.subheadline.weight(.semibold))
                    Text(milestone.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            showPaywall = true
                        } label: {
                            Text("Show me")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(brandColor, in: Capsule())
                                .foregroundStyle(.white)
                        }

                        Button {
                            withAnimation {
                                dismissed = true
                                onDismiss(milestone)
                            }
                        } label: {
                            Text("Not now")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(brandColor.opacity(0.25), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

private struct StatusBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct CaptureStatusLine: View {
    let text: String
    var isError: Bool = false
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("captureStatusLine")
    }
}

private struct UndoSnackbar: View {
    var onAddDetails: () -> Void
    var onUndo: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onAddDetails) {
                Label("Add Details", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("addDetailsButton")

            Spacer(minLength: 8)

            Button(role: .destructive, action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("undoLastTapButton")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityIdentifier("undoSnackbar")
    }
}
