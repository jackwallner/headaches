import SwiftData
import SwiftUI
import UIKit
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator
    @EnvironmentObject private var store: StoreService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HeadacheStorageKey.useCelsiusTemperature.rawValue, store: HeadacheAppGroup.userDefaults) private var useCelsius = false
    @AppStorage(HeadacheStorageKey.promptForSeverityNotes.rawValue, store: HeadacheAppGroup.userDefaults) private var promptForSeverityNotes = false
    @AppStorage(HeadacheStorageKey.milestonePrompt3Shown.rawValue, store: HeadacheAppGroup.userDefaults) private var milestone3PromptShown = false
    @AppStorage(HeadacheStorageKey.milestonePrompt5Shown.rawValue, store: HeadacheAppGroup.userDefaults) private var milestone5PromptShown = false
    @AppStorage(HeadacheStorageKey.milestonePrompt10Shown.rawValue, store: HeadacheAppGroup.userDefaults) private var milestone10PromptShown = false
    @Query(sort: \HeadacheEvent.timestamp, order: .reverse) private var events: [HeadacheEvent]
    /// Item-based so the sheet can only ever present *with* an event id. The old
    /// `.sheet(isPresented:)` + `if let id` pattern could present an empty shell
    /// (a blank white sheet) if the bool and the id ever desynced.
    @State private var severityNotesTarget: SeverityNotesTarget?
    @State private var showPaywall = false
    #if DEBUG
    @State private var didPrepareScreenshotCapture = false
    #endif
    /// True once the milestone card claimed this session's Pro moment, so the claim keeps it on screen.
    @State private var milestoneClaimedSession = false
    @State private var didPresentDebugDetails = false
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
                        // Guarded here, not with .disabled: a disabled button dims, and the whole
                        // button would redraw when the capture ends.
                        guard !captureCoordinator.isCapturing else { return }
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
                                .foregroundStyle(.white)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.brand, AppTheme.brandEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                        .shadow(color: AppTheme.brandEnd.opacity(0.30), radius: 18, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log headache")
                    .accessibilityIdentifier("logHeadacheButton")

                    // Shown from the tap on ("Saving..." becomes "Context saved."), so the
                    // result never lands late and pushes the cards below it down.
                    if let statusLine = captureCoordinator.bannerMessage {
                        CaptureStatusLine(text: statusLine, isError: captureCoordinator.bannerIsError) {
                            captureCoordinator.bannerMessage = nil
                        }
                    }
                }

                if let latestEvent {
                    LatestEventCard(event: latestEvent, useCelsius: useCelsius)
                        .keepsWholeAboveTabBar()
                        .id("\(latestEvent.id)-\(latestEvent.captureStatus.rawValue)-\(latestEvent.captureCompletedAt?.timeIntervalSince1970 ?? 0)")

                    if latestEvent.captureStatus == .partial || latestEvent.captureStatus == .failed {
                        CaptureRecoveryCard(
                            event: latestEvent,
                            isRetrying: captureCoordinator.isCapturing,
                            onRetry: {
                                captureCoordinator.retryCapture(eventID: latestEvent.id, in: modelContext)
                            }
                        )
                        .keepsWholeAboveTabBar()
                        .id("recovery-\(latestEvent.id)-\(latestEvent.captureStatus.rawValue)-\(captureCoordinator.isCapturing)")
                    }
                }

                if let milestone = activeMilestone {
                    MilestoneProPrompt(milestone: milestone, showPaywall: $showPaywall, onDismiss: markMilestoneShown)
                        .keepsWholeAboveTabBar()
                        .onAppear {
                            milestoneClaimedSession = true
                            captureCoordinator.proPromptShownThisSession = true
                        }
                }

                if !recentEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Previous entries")
                                .font(.headline)
                            Spacer()
                            Text("See all in History")
                                .font(.footnote)
                                .foregroundStyle(.primary)
                        }
                        .keepsWholeAboveTabBar()

                        ForEach(recentEvents, id: \.id) { event in
                            RecentEventRow(event: event)
                                .keepsWholeAboveTabBar()
                                .id("recent-\(event.id)-\(event.captureStatus.rawValue)")
                        }
                    }
                }

                if events.count < Self.captureExplainerLogThreshold {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What Gets Captured")
                            .font(.headline)
                            .keepsWholeAboveTabBar()
                        Text("Press once when a headache starts; the app records the moment and fills in as much health and environmental context as it can.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                            .keepsWholeAboveTabBar()

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
        .clearsFloatingTabBar()
        .navigationTitle(HeadacheBrand.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("homeView")
        .onAppear {
            #if DEBUG
            guard !didPresentDebugDetails,
                  ProcessInfo.processInfo.arguments.contains("-HeadacheScreenshotDetails")
            else { return }
            didPresentDebugDetails = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let event = events.first else { return }
                showDetails(for: event.id)
            }
            #endif
        }
        #if DEBUG
        .task(id: events.count) {
            guard ProcessInfo.processInfo.arguments.contains("-HeadacheScreenshotCapture"),
                  !didPrepareScreenshotCapture,
                  let event = events.first
            else { return }
            didPrepareScreenshotCapture = true
            captureCoordinator.lastCapturedEventID = event.id
            captureCoordinator.bannerMessage = String(localized: "Context saved.")
            captureCoordinator.bannerIsError = false
        }
        #endif
        .safeAreaInset(edge: .bottom) {
            if undoSnackbarVisible, let eventID = captureCoordinator.lastCapturedEventID {
                UndoSnackbar(
                    onAddDetails: { showDetails(for: eventID) },
                    onUndo: {
                        // The log is gone, so its rating moment goes with it.
                        ReviewPromptTracker.consumePendingPositiveMoment()
                        captureCoordinator.undoLastCapture(in: modelContext)
                        dismissUndoSnackbar()
                    },
                    onDismiss: { dismissUndoSnackbar() }
                )
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: captureCoordinator.isCapturing) { _, isCapturing in
            if !isCapturing, !captureCoordinator.currentRunIsRetry, captureCoordinator.lastCapturedEventID != nil {
                showUndoSnackbar()
            }
        }
        .onChange(of: captureCoordinator.lastCapturedEventID) { _, newValue in
            if newValue == nil { dismissUndoSnackbar() }
        }
        .sheet(item: $severityNotesTarget, onDismiss: {
            // The notes sheet opens right after a log, so the log's rating ask
            // usually finds it up and stays pending. Ask again once it closes.
            NotificationCenter.default.post(name: .headachePositiveMomentForReview, object: nil)
        }) { target in
            SeverityNotesSheet(eventID: target.id)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
                .task { store.trackPaywallImpression(id: "headache_home_sheet") }
        }
        .onChange(of: severityNotesTarget != nil || showPaywall, initial: true) { _, covered in
            ReviewPromptCoordinator.shared.homeSheetIsPresented = covered
        }
        .onChange(of: undoSnackbarVisible, initial: true) { wasVisible, visible in
            ReviewPromptCoordinator.shared.undoBarIsVisible = visible
            // The log's rating ask waits out the Undo bar. Ask again once it closes.
            if wasVisible, !visible {
                NotificationCenter.default.post(name: .headachePositiveMomentForReview, object: nil)
            }
        }
    }

    private func showDetails(for eventID: UUID) {
        severityNotesTarget = SeverityNotesTarget(id: eventID)
    }

    private func showUndoSnackbar() {
        undoDismissTask?.cancel()
        Motion.animate(reduce: reduceMotion) {
            undoSnackbarVisible = true
        }
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.undoSnackbarTTLSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            Motion.animate(reduce: reduceMotion) {
                undoSnackbarVisible = false
            }
        }
    }

    private func dismissUndoSnackbar() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        Motion.animate(reduce: reduceMotion) {
            undoSnackbarVisible = false
        }
    }

    enum ProMilestone: Int, Equatable {
        case threeLogs = 3
        case fiveLogs = 5
        case tenLogs = 10

        var title: String {
            switch self {
            case .threeLogs: return String(localized: "You've logged \(rawValue) headaches")
            case .fiveLogs: return String(localized: "\(rawValue) headaches logged, enough for patterns")
            case .tenLogs: return String(localized: "\(rawValue) headaches, meaningful data")
            }
        }

        var detail: String {
            switch self {
            case .threeLogs: return String(localized: "Great start! Pro reveals the patterns hiding in your logs: time, sleep, weather, and more.")
            case .fiveLogs: return String(localized: "You have enough data for personalized pattern analysis. Pro shows the patterns in your logs.")
            case .tenLogs: return String(localized: "You've built enough history for meaningful patterns. Unlock Pro to see your personalized patterns and get proactive alerts.")
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
        Self.milestone(
            count: events.count,
            isPro: store.isProUnlocked,
            sessionClaimedElsewhere: captureCoordinator.proPromptShownThisSession && !milestoneClaimedSession,
            shown3: milestone3PromptShown,
            shown5: milestone5PromptShown,
            shown10: milestone10PromptShown
        )
    }

    /// One Pro moment per session: the card yields to a trial offer that already fired,
    /// but its own claim on the session must not hide it again.
    static func milestone(
        count: Int,
        isPro: Bool,
        sessionClaimedElsewhere: Bool,
        shown3: Bool,
        shown5: Bool,
        shown10: Bool
    ) -> ProMilestone? {
        guard !isPro, !sessionClaimedElsewhere else { return nil }
        if count >= 10 { return shown10 ? nil : .tenLogs }
        if count >= 5 { return shown5 ? nil : .fiveLogs }
        if count >= 3 { return shown3 ? nil : .threeLogs }
        return nil
    }

    /// Retiring a milestone retires the lower ones too, so "Not now" on the 10-log card
    /// doesn't bring back the 5-log card.
    private func markMilestoneShown(_ milestone: ProMilestone) {
        milestone3PromptShown = true
        if milestone.rawValue >= ProMilestone.fiveLogs.rawValue { milestone5PromptShown = true }
        if milestone == .tenLogs { milestone10PromptShown = true }
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
                    StatusBadge(label: severity.localizedName, tint: severityColor(severity))
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
                    value: event.stepsToday?.formatted(.number) ?? "No data",
                    tint: AppTheme.teal
                )
                MetricChip(
                    title: "Sleep",
                    value: event.sleepHoursLastNight.map { $0.formatted(.number.precision(.fractionLength(1))) + " h" } ?? "No data",
                    tint: AppTheme.indigo
                )
                MetricChip(
                    title: "AQI",
                    value: event.usAQI.map { String(format: "%.0f", $0) } ?? "No data",
                    tint: AppTheme.cyan
                )
            }

            if hasMissingContext {
                DisclosureGroup(isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusBadge(label: "Health: \(event.healthStatus.rawValue)", tint: event.healthStatus == .captured ? AppTheme.green : AppTheme.orange)
                        StatusBadge(label: "Environment: \(event.environmentStatus.rawValue)", tint: event.environmentStatus == .captured ? AppTheme.blue : AppTheme.orange)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Why is something missing?")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .accessibilityIdentifier("latestEventDetailsDisclosure")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Latest Event")
        .accessibilityIdentifier("latestEventCard")
    }

    private var plainSummary: String {
        var parts: [String] = []

        let dateTime = event.timestamp.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        )
        parts.append("\(dateTime) · \(event.partOfDay.localizedName)")

        if let weather = weatherHeadline { parts.append(weather) }
        else if !event.locationLabel.isEmpty { parts.append(event.locationLabel) }

        if let pressureWord = pressureSummary { parts.append(pressureWord) }
        if let sleep = event.sleepHoursLastNight {
            let sleepText = sleep.formatted(.number.precision(.fractionLength(1)))
            parts.append(String(localized: "slept \(sleepText)h"))
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
        case .slight: AppTheme.slight
        case .medium: AppTheme.orange
        case .extreme: AppTheme.red
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
                Text(event.partOfDay.localizedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            HStack(spacing: 8) {
                Label(event.locationLabel.isEmpty ? "Location unavailable" : event.locationLabel, systemImage: "location")
                Spacer()
                Label(LocalizedStringKey(event.weatherSummary ?? "No weather"), systemImage: "cloud")
            }
            .font(.caption)
            .foregroundStyle(.primary)
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
                .foregroundStyle(AppTheme.brandText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .keepsWholeAboveTabBar()
    }
}

private struct MetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(value))
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
                .foregroundStyle(AppTheme.orange)

            VStack(alignment: .leading, spacing: 6) {
                if let healthIssue {
                    Text(healthIssue)
                }
                if let environmentIssue {
                    Text(environmentIssue)
                }
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)

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
            .tint(AppTheme.orangeFill)
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
            .tint(AppTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.orange.opacity(0.35), lineWidth: 1)
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
        components.path = "jackwallner+ha@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "One Tap Headache Tracker: capture failed"),
            URLQueryItem(name: "body", value: bodyLines.joined(separator: "\n")),
        ]
        return components.url
    }
}

/// Identifiable wrapper so the severity/notes sheet is driven by `.sheet(item:)`.
private struct SeverityNotesTarget: Identifiable {
    let id: UUID
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
                            Text(severity.localizedName).tag(Optional(severity))
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
            .onAppear {
                var descriptor = FetchDescriptor<HeadacheEvent>(predicate: #Predicate { $0.id == eventID })
                descriptor.fetchLimit = 1
                guard let event = try? modelContext.fetch(descriptor).first else { return }
                selectedSeverity = event.severity
                notes = event.userNotes ?? ""
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

    private var brandColor: Color { AppTheme.brandText }
    @State private var dismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .foregroundStyle(AppTheme.secondaryText)

                    HStack(spacing: 10) {
                        Button {
                            showPaywall = true
                        } label: {
                            Text("Show me")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(AppTheme.brand, in: Capsule())
                                .foregroundStyle(.white)
                        }

                        Button {
                            Motion.animate(reduce: reduceMotion, .default) {
                                dismissed = true
                                onDismiss(milestone)
                            }
                        } label: {
                            Text("Not now")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
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
            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
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
                .foregroundStyle(isError ? AppTheme.orange : AppTheme.green)
            Text(LocalizedStringKey(text))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
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
        HStack(spacing: 6) {
            Button(action: onAddDetails) {
                Label("Add Details", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("addDetailsButton")

            Spacer(minLength: 8)

            Button(role: .destructive, action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.red)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("undoLastTapButton")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("undoSnackbarDismiss")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undoSnackbar")
    }
}
