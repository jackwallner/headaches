import HealthKit
import SwiftUI
import UIKit
import RevenueCatUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: StoreService
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(HeadacheStorageKey.useCelsiusTemperature.rawValue, store: HeadacheAppGroup.userDefaults) private var useCelsius = false
    @AppStorage(HeadacheStorageKey.promptForSeverityNotes.rawValue, store: HeadacheAppGroup.userDefaults) private var promptForSeverityNotes = false
    @State private var locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
    @State private var healthStatus = HKHealthStore.isHealthDataAvailable() ? "Checking…" : "Unavailable on this device"
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private let privacyPolicyURL = URL(string: "https://jackwallner.github.io/headaches/privacy-policy.html")
    private let supportURL = URL(string: "https://jackwallner.github.io/headaches/support.html")
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    var body: some View {
        List {
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
                Button {
                    Task { await restorePurchases() }
                } label: {
                    if isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .disabled(isRestoring)
            } header: {
                Text("Headache Pro")
            } footer: {
                Text("Pro checks your local forecast and only pings when your logs support the pressure, AQI, or timing pattern behind the alert.")
            }

            Section("Logging") {
                Toggle("Prompt for severity and notes", isOn: $promptForSeverityNotes)
                if HeadacheQuizStore.hasCompletedQuiz {
                    NavigationLink {
                        HeadacheQuizRetakeView()
                    } label: {
                        Label("Headache Pattern Quiz", systemImage: "questionmark.circle")
                    }
                }
            }

            Section("Display") {
                Picker("Color scheme", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                Toggle("Use Celsius", isOn: $useCelsius)
            }

            Section {
                PermissionRow(
                    label: "Apple Health",
                    value: healthStatus,
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
            } header: {
                Text("Permissions")
            } footer: {
                Text("Health and location are read-only and only used to enrich logs with context.")
            }

            Section("About & Support") {
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
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            refreshLocationStatus()
            refreshHealthStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshLocationStatus()
            refreshHealthStatus()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
        .alert("Restore Purchases", isPresented: restoreBinding) {
            Button("OK", role: .cancel) { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var restoreBinding: Binding<Bool> {
        Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )
    }

    private func refreshLocationStatus() {
        locationStatus = EnvironmentService.shared.locationAuthorizationSummary()
    }

    private func refreshHealthStatus() {
        Task { healthStatus = await HealthKitService.shared.connectionSummary() }
    }

    private func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        await store.restorePurchases()
        if store.isProUnlocked {
            restoreMessage = "Your Headache Pro access is active."
        } else {
            restoreMessage = store.lastError ?? "No previous Headache Pro purchase was found on this Apple ID."
        }
    }

    private func proRowLabel(unlocked: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: unlocked ? "bell.badge.fill" : "lock.fill")
                .foregroundStyle(unlocked ? Color(red: 0.95, green: 0.25, blue: 0.36) : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Proactive Alerts")
                    .foregroundStyle(.primary)
                Text(unlocked ? "Configure personal triggers, thresholds, and quiet hours" : "Unlock Pro to get personalized headache-weather warnings")
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
