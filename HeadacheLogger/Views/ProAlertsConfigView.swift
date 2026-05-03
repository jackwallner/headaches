import CoreLocation
import SwiftUI
import UserNotifications

struct ProAlertsConfigView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var prefs = ProAlertPreferences.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
    @State private var permissionsBanner: String?

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

    private func formatHour(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }
}
