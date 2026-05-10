import CoreLocation
import SwiftUI
import UserNotifications

struct ProAlertsConfigView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var prefs = ProAlertPreferences.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
    @State private var permissionsBanner: String?
    @State private var testAlertMessage: String?

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
                Text("When enabled, the app checks your local forecast every few hours and notifies you if a pressure drop or air-quality spike is coming.")
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
                Text("Alerts use Open-Meteo's free public forecast and your most recent location. Location is stored only on your device and never uploaded.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Proactive Alerts")
        .task {
            await refreshPermissionStatuses()
        }
        .alert("Test Alert", isPresented: testAlertBinding) {
            Button("OK", role: .cancel) { testAlertMessage = nil }
        } message: {
            Text(testAlertMessage ?? "")
        }
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
        content.body = "Notifications are working. Real alerts fire when a pressure drop or AQI spike is forecast near you."
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
