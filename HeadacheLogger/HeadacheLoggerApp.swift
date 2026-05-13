import RevenueCatUI
import SwiftData
import SwiftUI
import UIKit

@main
struct HeadacheLoggerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var captureCoordinator = CaptureCoordinator()
    @StateObject private var storeService = StoreService.shared

    init() {
        StoreService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            HeadacheLoggerRootContent()
                .environmentObject(captureCoordinator)
                .environmentObject(storeService)
        }
        .modelContainer(HeadacheModelStore.sharedModelContainer)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundRefreshService.shared.registerTasks()
        return true
    }
}

/// Hosts onboarding vs main UI and always wires Watch → phone capture so the watch can log before iPhone onboarding finishes.
private struct HeadacheLoggerRootContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator
    @EnvironmentObject private var storeService: StoreService
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false
    @AppStorage(HeadacheStorageKey.hasSeenProIntro.rawValue, store: HeadacheAppGroup.userDefaults) private var hasSeenProIntro = false
    @State private var showProIntro = false

    var body: some View {
        Group {
            if AppEnvironment.bypassOnboarding || hasCompletedOnboarding {
                RootTabView()
                    .sheet(isPresented: $showProIntro) {
                        ProIntroSheet(onDismiss: { hasSeenProIntro = true })
                            .environmentObject(storeService)
                    }
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            #if os(iOS)
            PhoneWatchSession.shared.onWatchRequestedCapture = { [captureCoordinator] tapDate in
                captureCoordinator.captureHeadache(
                    in: modelContext,
                    fromWatch: true,
                    watchTapDate: tapDate
                )
            }
            if !AppEnvironment.isUITesting {
                PhoneWatchSession.shared.start()
            }
            #endif
            runWidgetEnrichmentIfReady()
            scheduleBackgroundIfNeeded()
            ensureUndecidedPermissionsAreRequested()
            offerProIntroIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                runWidgetEnrichmentIfReady()
                schedulePatterns()
                maintainDailyRecordsIfNeeded()
            } else if phase == .background {
                scheduleBackgroundIfNeeded()
            }
        }
        .onChange(of: storeService.isProUnlocked) { _, _ in
            scheduleBackgroundIfNeeded()
        }
    }

    private func runWidgetEnrichmentIfReady() {
        guard AppEnvironment.bypassOnboarding || hasCompletedOnboarding else { return }
        captureCoordinator.enrichPendingCapturesIfNeeded(in: modelContext)
    }

    private func scheduleBackgroundIfNeeded() {
        guard storeService.isProUnlocked else { return }
        let prefs = ProAlertPreferenceValues.current()
        guard prefs.alertsEnabled else { return }
        BackgroundRefreshService.shared.scheduleNextCheck()
    }

    @MainActor private func schedulePatterns() {
        Task { await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: modelContext) }
    }

    /// Ensure yesterday's record exists so the denominator stays accurate. Backfills
    /// weather when location is available.
    private func maintainDailyRecordsIfNeeded() {
        guard hasCompletedOnboarding else { return }
        DailyRecordStore.ensureYesterdayRecord()

        let records = DailyRecordStore.load()
        let missingWeather = records.filter { !$0.weatherFetched }
        guard !missingWeather.isEmpty,
              missingWeather.count >= 2,
              let coord = CachedLocation.current() else { return }

        Task.detached {
            let updated = await DailyWeatherBackfillService.backfill(
                for: records,
                latitude: coord.latitude,
                longitude: coord.longitude
            )
            DailyRecordStore.save(updated)
        }
    }

    /// Catch the case where onboarding completed without recording a decision (skipped step,
    /// killed mid-prompt, etc.) so the OS sheet doesn't fire mid–"Headache" tap later on.
    private func ensureUndecidedPermissionsAreRequested() {
        guard hasCompletedOnboarding else { return }
        Task {
            try? await HealthKitService.shared.prepareAuthorizationDuringOnboarding()
            await EnvironmentService.shared.prepareLocationAuthorizationDuringOnboarding()
        }
    }

    /// One-time intro for users who finished onboarding before Pro shipped.
    /// Net-new users have `hasSeenProIntro` set as the last step of onboarding, so they
    /// don't get hit twice. Also gated on Pro not being already unlocked.
    private func offerProIntroIfNeeded() {
        guard hasCompletedOnboarding, !hasSeenProIntro, !storeService.isProUnlocked else { return }
        // Defer slightly so the root tab is on screen before the sheet animates up.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !hasSeenProIntro, !storeService.isProUnlocked else { return }
            showProIntro = true
        }
    }
}

private struct ProIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreService
    @State private var showPaywall = false
    var onDismiss: () -> Void

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(brandColor)

                    Text("Headache Pro is here")
                        .font(.title.bold())

                    Text("Forecast checks stay quiet until your logs support a personal pressure, AQI, or timing pattern. When an alert fires, it explains the matching trigger and personal lift.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        ProBullet(icon: "barometer", text: "Pressure-drop and AQI alerts based on your own logs")
                        ProBullet(icon: "chart.bar.xaxis", text: "Personalized patterns from your existing logs")
                        ProBullet(icon: "lock.shield", text: "All processing stays on-device")
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        showPaywall = true
                    } label: {
                        Text("See Pro plans")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(brandColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    Button("Not now") {
                        onDismiss()
                        dismiss()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPaywall, onDismiss: {
                onDismiss()
                dismiss()
            }) {
                PaywallView()
            }
        }
    }
}

private struct ProBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(width: 26)
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
        }
    }
}
