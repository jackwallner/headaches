import RevenueCatUI
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

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
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefreshService.shared.registerTasks()
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
    @AppStorage(HeadacheStorageKey.hasSeenTrialOffer.rawValue, store: HeadacheAppGroup.userDefaults) private var hasSeenTrialOffer = false
    @State private var showProIntro = false
    @State private var showTrialOffer = false
    @State private var showTrialPaywall = false

    private var trialOfferLabel: String? {
        storeService.products.compactMap(\.headacheProIntroOfferLabel).first
    }

    private var hasTrialOffer: Bool { trialOfferLabel != nil }

    var body: some View {
        Group {
            if AppEnvironment.bypassOnboarding || hasCompletedOnboarding {
                RootTabView()
                    .sheet(isPresented: $showProIntro) {
                        ProIntroSheet(onDismiss: { hasSeenProIntro = true })
                            .environmentObject(storeService)
                    }
                    .sheet(isPresented: $showTrialOffer, onDismiss: {
                        hasSeenTrialOffer = true
                    }) {
                        TrialOfferSheet(
                            offerLabel: trialOfferLabel,
                            onTry: {
                                hasSeenTrialOffer = true
                                showTrialOffer = false
                                showTrialPaywall = true
                            },
                            onDismiss: {
                                hasSeenTrialOffer = true
                                showTrialOffer = false
                            }
                        )
                        .presentationDetents([.height(420), .large])
                        .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showTrialPaywall) {
                        PaywallView()
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
            evaluateTrialOffer()
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
        .onChange(of: storeService.isProUnlocked) { _, isPro in
            scheduleBackgroundIfNeeded()
            if isPro {
                showProIntro = false
                showTrialOffer = false
            }
        }
        .onChange(of: storeService.products.count) { _, _ in
            evaluateTrialOffer()
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
    /// Skipped when a free-trial offer is available — `evaluateTrialOffer` handles that path.
    private func offerProIntroIfNeeded() {
        guard hasCompletedOnboarding, !hasSeenProIntro, !storeService.isProUnlocked else { return }
        if hasTrialOffer { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !hasSeenProIntro, !storeService.isProUnlocked, !showTrialOffer else { return }
            if hasTrialOffer { return }
            showProIntro = true
        }
    }

    /// One-time free-trial nudge for non-Pro users when an intro offer is available.
    private func evaluateTrialOffer() {
        guard hasCompletedOnboarding,
              !storeService.isProUnlocked,
              !hasSeenTrialOffer,
              hasTrialOffer
        else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !showTrialOffer,
                  !showTrialPaywall,
                  !hasSeenTrialOffer,
                  !storeService.isProUnlocked,
                  hasTrialOffer
            else { return }
            showProIntro = false
            showTrialOffer = true
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

private struct TrialOfferSheet: View {
    let offerLabel: String?
    let onTry: () -> Void
    let onDismiss: () -> Void

    private var brandColor: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }

    private var headline: String {
        if let offerLabel {
            let length = offerLabel.replacingOccurrences(of: " free trial", with: "")
            return "Try Headache Pro free for \(length)"
        }
        return "Try Headache Pro free"
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [brandColor, Color(red: 0.86, green: 0.16, blue: 0.43)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: brandColor.opacity(0.35), radius: 14, x: 0, y: 6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 18)

                VStack(spacing: 8) {
                    Text(headline)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Unlock proactive pressure and AQI alerts, personalized pattern insights, and richer history. No charge until your trial ends — cancel anytime in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 10) {
                    Button(action: onTry) {
                        Text("Start Free Trial")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(brandColor, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
