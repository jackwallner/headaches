import HealthKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(HeadacheStorageKey.useCelsiusTemperature.rawValue, store: HeadacheAppGroup.userDefaults) private var useCelsius = false
    @AppStorage(HeadacheStorageKey.promptForSeverityNotes.rawValue, store: HeadacheAppGroup.userDefaults) private var promptForSeverityNotes = false
    @State private var locationStatus = EnvironmentService.shared.locationAuthorizationSummary()

    private let privacyPolicyURL = URL(string: "https://jackwallner.github.io/headaches/privacy-policy.html")
    private let supportURL = URL(string: "https://jackwallner.github.io/headaches/support.html")

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Color scheme", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Temperature") {
                Toggle("Show Celsius", isOn: $useCelsius)
                Text("Off (default): Fahrenheit (°F). On: Celsius (°C). Exported CSV always includes both °C and °F columns.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Logging") {
                Toggle("Prompt for severity and notes", isOn: $promptForSeverityNotes)
                Text("When on, each tap shows a quick sheet to rate severity (slight, medium, extreme) and add notes before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("How Logging Works") {
                Text("The main screen is intentionally a one-tap logger. When you press Headache, the app saves the event immediately and then enriches it with whatever context it can collect.")
                Text("Nothing about the headache itself is typed in during logging. The goal is to make capture fast enough that you actually use it.")
            }

            Section("Permissions") {
                PermissionRow(
                    label: "Apple Health",
                    value: HKHealthStore.isHealthDataAvailable() ? "Available on this device" : "Unavailable",
                    valueIdentifier: "healthPermissionValue"
                )
                PermissionRow(
                    label: "Location",
                    value: locationStatus,
                    valueIdentifier: "locationPermissionValue"
                )
                Button("Open iPhone Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }

            Section("Captured Context") {
                Text("Time: weekday, hour, minute, timezone, part of day.")
                Text("Health: steps, active energy, walking distance, exercise minutes, sleep, heart data, breathing, recent workouts.")
                Text("Environment: local weather, humidity, pressure, precipitation, wind, cloud cover, UV, air quality, and pollen-style signals when available.")
            }

            Section("Sharing") {
                Text("The History tab can export all logged events as a CSV so you can email it, AirDrop it, or share it directly with your doctor.")
            }

            Section("Privacy and Support") {
                Button("Privacy Policy") {
                    guard let privacyPolicyURL else { return }
                    openURL(privacyPolicyURL)
                }
                Button("Support") {
                    guard let supportURL else { return }
                    openURL(supportURL)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
        }
    }
}

private struct PermissionRow: View {
    let label: String
    let value: String
    let valueIdentifier: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(valueIdentifier)
        }
    }
}
