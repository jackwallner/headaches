import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator
    @AppStorage(HeadacheStorageKey.useCelsiusTemperature.rawValue, store: HeadacheAppGroup.userDefaults) private var useCelsius = false
    @Query(sort: \HeadacheEvent.timestamp, order: .reverse) private var events: [HeadacheEvent]

    private var latestEvent: HeadacheEvent? { events.first }
    // C18: skip the latest event so it doesn't duplicate between LatestEventCard and Recent Logs.
    private var recentEvents: [HeadacheEvent] { Array(events.dropFirst().prefix(3)) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Press once when a headache starts — the app records the moment and fills in as much health and environmental context as it can.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let bannerMessage = captureCoordinator.bannerMessage {
                    Text(bannerMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("captureBanner")
                }

                VStack(spacing: 14) {
                    Button {
                        captureCoordinator.captureHeadache(in: modelContext)
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 36, weight: .bold))
                            Text("Headache")
                                .font(.title2.bold())
                            Text(captureCoordinator.isCapturing ? "Saving and collecting context..." : "Tap once to log right now")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.95, green: 0.25, blue: 0.36), Color(red: 0.86, green: 0.16, blue: 0.43)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(captureCoordinator.isCapturing)
                    .accessibilityLabel("Log headache")
                    .accessibilityIdentifier("logHeadacheButton")

                    if captureCoordinator.lastCapturedEventID != nil {
                        Button("Undo Last Tap") {
                            captureCoordinator.undoLastCapture(in: modelContext)
                        }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("undoLastTapButton")
                    }
                }

                if let latestEvent {
                    LatestEventCard(event: latestEvent, useCelsius: useCelsius)

                    if latestEvent.captureStatus == .partial || latestEvent.captureStatus == .failed {
                        CaptureRecoveryCard(
                            event: latestEvent,
                            isRetrying: captureCoordinator.isCapturing,
                            onRetry: {
                                captureCoordinator.retryCapture(eventID: latestEvent.id, in: modelContext)
                            }
                        )
                    }
                }

                if !recentEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Logs")
                            .font(.headline)

                        ForEach(recentEvents, id: \.id) { event in
                            RecentEventRow(event: event)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("What Gets Captured")
                        .font(.headline)

                    CaptureItem(
                        icon: "clock",
                        title: "Time context",
                        subtitle: "Date, weekday, hour, minute, timezone, and part of day."
                    )
                    CaptureItem(
                        icon: "heart.text.square",
                        title: "Apple Health context",
                        subtitle: "Activity (including stand time and flights), sleep duration plus inferred wake time, heart metrics (including SpO₂ and VO₂ max when logged), audio exposure, mindful minutes, barometric change, breathing, and recent workouts — all without typing."
                    )
                    CaptureItem(
                        icon: "cloud.sun",
                        title: "Weather and environment",
                        subtitle: "Location-based weather, pressure, air quality, UV, and pollen-style signals when available."
                    )
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Headache Logger")
        .accessibilityIdentifier("homeView")
    }
}

private struct LatestEventCard: View {
    let event: HeadacheEvent
    var useCelsius: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Event")
                        .font(.headline)
                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadge(label: event.captureStatus.rawValue.capitalized, tint: statusColor)
            }

            HStack(spacing: 8) {
                StatusBadge(label: "Health: \(event.healthStatus.rawValue)", tint: event.healthStatus == .captured ? .green : .orange)
                StatusBadge(label: "Environment: \(event.environmentStatus.rawValue)", tint: event.environmentStatus == .captured ? .blue : .orange)
            }

            if !event.locationLabel.isEmpty || event.weatherSummary != nil {
                Text([event.locationLabel.isEmpty ? nil : event.locationLabel, weatherHeadline]
                    .compactMap { $0 }
                    .joined(separator: " • "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("latestEventCard")
    }

    private var weatherHeadline: String? {
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
        return "Health \(event.healthStatus.rawValue) — \(detail)"
    }

    private var environmentIssue: String? {
        guard event.environmentStatus != .captured else { return nil }
        let detail = event.environmentStatusMessage ?? "no detail"
        return "Environment \(event.environmentStatus.rawValue) — \(detail)"
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

            HStack(spacing: 10) {
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

                Button {
                    if let url = mailURL() {
                        openURL(url)
                    }
                } label: {
                    Text("Email Developer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("captureReportButton")
            }
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
            "— App version: \(version) (\(build))",
            "— iOS: \(iosVersion) on \(deviceModel)",
            "— Event ID: \(event.id.uuidString)",
            "— Event time: \(tsFormatter.string(from: event.timestamp))",
            "— Capture status: \(event.captureStatus.rawValue)",
            "— Health status: \(event.healthStatus.rawValue)\(event.healthStatusMessage.map { " — \($0)" } ?? "")",
            "— Environment status: \(event.environmentStatus.rawValue)\(event.environmentStatusMessage.map { " — \($0)" } ?? "")",
            "",
            "Anything else you want to add:",
            "",
        ]

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "jackwallner@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Headache Logger: capture failed"),
            URLQueryItem(name: "body", value: bodyLines.joined(separator: "\n")),
        ]
        return components.url
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
