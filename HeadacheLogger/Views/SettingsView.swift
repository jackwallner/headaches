import HealthKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: StoreKitService
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(HeadacheStorageKey.useCelsiusTemperature.rawValue, store: HeadacheAppGroup.userDefaults) private var useCelsius = false
    @AppStorage(HeadacheStorageKey.promptForSeverityNotes.rawValue, store: HeadacheAppGroup.userDefaults) private var promptForSeverityNotes = false
    @State private var locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
    @State private var showPaywall = false

    private let privacyPolicyURL = URL(string: "https://jackwallner.github.io/headaches/privacy-policy.html")
    private let supportURL = URL(string: "https://jackwallner.github.io/headaches/support.html")
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

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

            Section {
                if store.isProUnlocked {
                    NavigationLink {
                        ProAlertsConfigView()
                    } label: {
                        proRowLabel(unlocked: true)
                    }
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        proRowLabel(unlocked: false)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Pro")
            } footer: {
                Text("Pro adds a daily background forecast check. The app pings you when a sharp barometric pressure drop or air-quality spike is on the way.")
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
                Button("Terms of Use") {
                    guard let termsURL else { return }
                    openURL(termsURL)
                }
                Button("Support") {
                    guard let supportURL else { return }
                    openURL(supportURL)
                }
                if store.isProUnlocked {
                    Button("Restore Purchases") {
                        Task { await store.restorePurchases() }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func proRowLabel(unlocked: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: unlocked ? "bell.badge.fill" : "lock.fill")
                .foregroundStyle(unlocked ? Color(red: 0.95, green: 0.25, blue: 0.36) : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Proactive Alerts")
                    .foregroundStyle(.primary)
                Text(unlocked ? "Configure thresholds and quiet hours" : "Unlock Pro to get headache-weather warnings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !unlocked {
                Text("Pro")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.95, green: 0.25, blue: 0.36).opacity(0.15), in: Capsule())
                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
            }
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
