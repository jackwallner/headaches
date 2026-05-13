import CoreLocation
import SwiftData
import SwiftUI
import UserNotifications

struct ProAlertsConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @StateObject private var prefs = ProAlertPreferences.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
    @State private var permissionsBanner: String?
    @State private var testAlertMessage: String?
    @State private var personalProfile = ProactiveAlertsEngine.PersonalAlertProfile.current()

    var body: some View {
        Form {
            Section {
                Toggle("Enable Proactive Alerts", isOn: $prefs.alertsEnabled)
                    .onChange(of: prefs.alertsEnabled) { _, newValue in
                        if newValue {
                            Task { await requestPermissionsIfNeeded() }
                            BackgroundRefreshService.shared.scheduleNextCheck()
                        }
                    }
            } footer: {
                Text("When enabled, the app checks your local forecast every few hours and only notifies you when your own daily history shows a clear link between headaches and pressure drops or air quality.")
            }

            if let permissionsBanner {
                Section {
                    Text(permissionsBanner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open iPhone Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            }

            Section {
                ProAlertStatusRow(
                    icon: notificationIcon,
                    title: "Notifications",
                    value: notificationLabel
                )
                ProAlertStatusRow(
                    icon: "location.fill",
                    title: "Forecast location",
                    value: friendlyLocationStatus
                )
                ProAlertStatusRow(
                    icon: "clock.arrow.circlepath",
                    title: "Last proactive alert",
                    value: lastAlertText
                )
                Button {
                    Task { await sendTestAlert() }
                } label: {
                    Label("Send Test Alert", systemImage: "paperplane.fill")
                }
                .disabled(!prefs.alertsEnabled)
            } header: {
                Text("Status")
            } footer: {
                Text(prefs.alertsEnabled ? "Use a test alert to confirm notifications are working before waiting for real headache weather." : "Enable Proactive Alerts first, then send a test notification.")
            }

            Section {
                ProAlertStatusRow(
                    icon: "barometer",
                    title: "Pressure signal",
                    value: signalStatus(personalProfile.pressure)
                )
                ProAlertStatusRow(
                    icon: "aqi.medium",
                    title: "Air-quality signal",
                    value: prefs.airQualityEnabled ? signalStatus(personalProfile.airQuality) : "Off"
                )
            } header: {
                Text("Personalization")
            } footer: {
                Text(personalProfile.pressure.isSupported || (prefs.airQualityEnabled && personalProfile.airQuality.isSupported)
                     ? "Alert text includes the probability lift and breakdown so you know why it fired."
                     : "Keep logging. Forecast alerts stay quiet until your daily history shows a clear weather-pattern link across at least \(ProactiveAlertsEngine.personalSignalMinimumSampleSize) days.")
            }

            Section("Pressure drop") {
                VStack(alignment: .leading) {
                    Text("Alert when pressure is forecast to drop by")
                    HStack {
                        Slider(value: $prefs.pressureDropThresholdHpa, in: 2...10, step: 0.5)
                        Text(String(format: "%.1f hPa", prefs.pressureDropThresholdHpa))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                Text("Most barometric-trigger studies use 3–6 hPa over 12–24 hours.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Air quality") {
                Toggle("Alert on poor air quality", isOn: $prefs.airQualityEnabled)
                if prefs.airQualityEnabled {
                    Stepper(value: $prefs.airQualityThreshold, in: 50...300, step: 25) {
                        HStack {
                            Text("Threshold")
                            Spacer()
                            Text("AQI \(prefs.airQualityThreshold)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("US AQI 100 is \"unhealthy for sensitive groups\". 150+ is unhealthy for everyone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Quiet hours") {
                Toggle("Don't alert at night", isOn: $prefs.quietHoursEnabled)
                if prefs.quietHoursEnabled {
                    Stepper(value: $prefs.quietHoursStart, in: 0...23) {
                        HStack {
                            Text("From")
                            Spacer()
                            Text(formatHour(prefs.quietHoursStart))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $prefs.quietHoursEnd, in: 0...23) {
                        HStack {
                            Text("Until")
                            Spacer()
                            Text(formatHour(prefs.quietHoursEnd))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("How this works") {
                Text("Alerts use Open-Meteo's free public forecast, your most recent location, and your local headache history. Location and pattern analysis stay on your device.")
                    .font(.footnote)
            }

            Section {
                Toggle("Predict from your patterns", isOn: $prefs.patternAlertsEnabled)
                    .onChange(of: prefs.patternAlertsEnabled) { _, _ in
                        schedulePatterns()
                    }
                if prefs.patternAlertsEnabled {
                    Picker("Sensitivity", selection: $prefs.patternAlertSensitivity) {
                        Text("High chance only").tag(0.0)
                        Text("Any chance").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: prefs.patternAlertSensitivity) { _, _ in
                        schedulePatterns()
                    }
                }
            } header: {
                Text("Prediction")
            } footer: {
                Text(prefs.patternAlertsEnabled
                    ? "Analyzes your headache history on-device for recurring time patterns, then notifies you ~1 hour before a headache is likely. All analysis runs locally — nothing leaves your phone."
                    : "When enabled, the app analyzes your personal headache patterns and sends a heads-up about an hour before you'd typically get one."
                )
            }
        }
        .navigationTitle("Proactive Alerts")
        .task {
            ProactiveAlertsEngine.refreshPersonalAlertProfile(in: modelContext)
            personalProfile = ProactiveAlertsEngine.PersonalAlertProfile.current()
            await refreshPermissionStatuses()
        }
        .alert("Test Alert", isPresented: testAlertBinding) {
            Button("OK", role: .cancel) { testAlertMessage = nil }
        } message: {
            Text(testAlertMessage ?? "")
        }
    }

    @MainActor private func schedulePatterns() {
        Task { await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: modelContext) }
    }

    private var testAlertBinding: Binding<Bool> {
        Binding(
            get: { testAlertMessage != nil },
            set: { if !$0 { testAlertMessage = nil } }
        )
    }

    private var notificationIcon: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell.fill"
        @unknown default: return "bell.fill"
        }
    }

    private var notificationLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "Ready"
        case .denied: return "Off in Settings"
        case .notDetermined: return "Needs permission"
        @unknown default: return "Unknown"
        }
    }

    private var friendlyLocationStatus: String {
        switch locationStatus {
        case "Allowed": return "Ready"
        case "Denied": return "Off in Settings"
        case "Off": return "Location Services off"
        case "Not asked": return "Needs permission"
        default: return locationStatus
        }
    }

    private var lastAlertText: String {
        let defaults = HeadacheAppGroup.userDefaults
        guard let date = defaults.object(forKey: HeadacheStorageKey.proAlertLastFiredAt.rawValue) as? Date else {
            return "None yet"
        }
        let kind = defaults.string(forKey: HeadacheStorageKey.proAlertLastFiredKind.rawValue)
        let prefix = kind == ProactiveAlertsEngine.AlertKind.airQuality.rawValue ? "AQI" : "Pressure"
        return "\(prefix) • \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func signalStatus(_ signal: ProactiveAlertsEngine.PersonalSignalProfile) -> String {
        if signal.isSupported {
            let risk = Int((signal.relativeRisk * 100).rounded())
            return "\(risk)% risk • \(signal.headacheConditionDays)/\(signal.conditionDays)"
        }
        if signal.totalDays < ProactiveAlertsEngine.personalSignalMinimumSampleSize {
            return "Learning \(signal.totalDays)/\(ProactiveAlertsEngine.personalSignalMinimumSampleSize)"
        }
        return "No clear pattern"
    }

    private func refreshPermissionStatuses() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
        locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
        updateBanner()
    }

    private func updateBanner() {
        guard prefs.alertsEnabled else {
            permissionsBanner = nil
            return
        }
        var issues: [String] = []
        switch notificationStatus {
        case .denied:
            issues.append("Notifications are off — alerts can't be delivered until you enable them in Settings.")
        case .notDetermined:
            issues.append("Notification permission hasn't been granted yet.")
        default:
            break
        }
        if locationStatus == "Denied" || locationStatus == "Off" {
            issues.append("Location is off — without it the app can't fetch your local forecast.")
        }
        permissionsBanner = issues.isEmpty ? nil : issues.joined(separator: " ")
    }

    private func requestPermissionsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        await EnvironmentService.shared.prepareLocationAuthorizationDuringOnboarding()
        await refreshPermissionStatuses()
    }

    private func sendTestAlert() async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            await refreshPermissionStatuses()
            testAlertMessage = "Notifications are not enabled. Open iPhone Settings and allow notifications for One Tap Headache Tracker."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Test Headache Pro Alert"
        content.body = "Notifications are working. Real alerts fire only when a forecast matches a supported personal trigger from your logs."
        content.sound = .default
        content.threadIdentifier = "pro-alerts"
        let request = UNNotificationRequest(identifier: "pro-alert-test-\(UUID().uuidString)", content: content, trigger: nil)

        do {
            try await center.add(request)
            await refreshPermissionStatuses()
            testAlertMessage = "Test alert sent."
        } catch {
            testAlertMessage = "Could not send the test alert. Please try again."
        }
    }

    private func formatHour(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }
}

private struct ProAlertStatusRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
