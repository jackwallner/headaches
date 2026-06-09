@preconcurrency import RevenueCat
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted when the Patterns (Insights) tab appears, so the root content can
    /// consider the second-touch trial offer.
    static let headachePatternsDidAppear = Notification.Name("headachePatternsDidAppear")
}

@main
struct HeadacheLoggerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var captureCoordinator = CaptureCoordinator()
    @StateObject private var storeService = StoreService.shared

    init() {
        StoreService.shared.start()
        ReviewPromptTracker.recordAppLaunch()
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
    @AppStorage(HeadacheStorageKey.hasSeenInsightsTrialOffer.rawValue, store: HeadacheAppGroup.userDefaults) private var hasSeenInsightsTrialOffer = false
    /// Count-only awareness of logged events. Drives the first-log trial trigger
    /// without paying for a full event hydration on every change.
    @Query private var events: [HeadacheEvent]
    /// Single source of truth for the root-level promo / review sheets. Using one
    /// `.sheet(item:)` instead of four stacked `.sheet(isPresented:)` modifiers
    /// guarantees only one ever presents. Stacked sheets on the same view can race
    /// and present an empty shell (e.g. a blank "trial" card to an already-Pro user).
    @State private var activeSheet: RootPromoSheet?
    @State private var trialPurchaseInFlight = false
    @State private var trialPurchaseError: String?
    /// True once the first-log / existing-user offer has been presented in *this*
    /// app session. Gates the Patterns-tab second touch so the two never fire
    /// back-to-back — Patterns is strictly a later-session second touch when the
    /// first-log path didn't fire (e.g. products failed to load that session).
    @State private var firstLogOfferShownThisSession = false
    /// Which trigger opened the current offer, so dismissal sets the right flag.
    @State private var trialOfferSource: TrialOfferSource = .firstLog
    /// Set when the user opts into the full plan picker from inside the trial-offer
    /// sheet. The `.sheet(onDismiss:)` reads this and presents the paywall *after*
    /// the trial sheet has fully dismissed — presenting both sheets in the same
    /// runloop tick is racy in SwiftUI and frequently drops the second sheet.
    @State private var pendingPaywallAfterTrialDismiss = false
    @StateObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var reviewPromptInitialStep: ReviewPromptSheet.Step = .enjoyment
    @State private var reviewPromptShownThisSession = false
    @State private var pendingNativeReviewAfterDismiss = false
    @Environment(\.requestReview) private var requestReview

    private enum TrialOfferSource {
        case firstLog
        case existingUser
        case insights
    }

    /// The mutually-exclusive root sheet currently presented.
    private enum RootPromoSheet: String, Identifiable {
        case proIntro
        case trialOffer
        case trialPaywall
        case reviewPrompt
        var id: String { rawValue }
    }

    private var trialOfferLabel: String? {
        directTrialPackage?.headacheProIntroOfferLabel
            ?? storeService.products.compactMap(\.headacheProIntroOfferLabel).first
    }

    private var hasTrialOffer: Bool { directTrialPackage != nil }

    /// The package the direct trial purchase buys: prefer eligible yearly trial,
    /// else any eligible trial-bearing package.
    private var directTrialPackage: Package? {
        let trialPackages = storeService.products.filter { storeService.isEligibleForIntroOffer($0) }
        return trialPackages.first { $0.headacheProPackageKind == .yearly } ?? trialPackages.first
    }

    var body: some View {
        Group {
            if AppEnvironment.bypassOnboarding || hasCompletedOnboarding {
                RootTabView()
                    .sheet(item: $activeSheet, onDismiss: handleRootSheetDismiss) { sheet in
                        switch sheet {
                        case .proIntro:
                            ProIntroSheet(onDismiss: { hasSeenProIntro = true })
                                .environmentObject(storeService)
                        case .trialOffer:
                            TrialOfferSheet(
                                offerLabel: trialOfferLabel,
                                priceLabel: directTrialPackage?.headacheProPriceLabel,
                                directPurchase: directTrialPackage != nil,
                                isPurchasing: trialPurchaseInFlight,
                                errorMessage: trialPurchaseError,
                                onStartTrial: {
                                    if directTrialPackage != nil {
                                        startDirectTrialPurchase()
                                    } else {
                                        pendingPaywallAfterTrialDismiss = true
                                        activeSheet = nil
                                    }
                                },
                                onSeeAllPlans: {
                                    pendingPaywallAfterTrialDismiss = true
                                    activeSheet = nil
                                },
                                onDismiss: {
                                    activeSheet = nil
                                }
                            )
                            .presentationDetents([.fraction(0.85), .large])
                            .presentationDragIndicator(.visible)
                            .interactiveDismissDisabled(trialPurchaseInFlight)
                        case .trialPaywall:
                            PaywallView()
                                .environmentObject(storeService)
                                .task { storeService.trackPaywallImpression(id: "headache_trial_sheet") }
                        case .reviewPrompt:
                            ReviewPromptSheet(initialStep: reviewPromptInitialStep, onFinish: handleReviewPromptFinish)
                        }
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
            // Existing-user catch-up: if they already have logs and haven't seen
            // the trial pitch, fire it ~3s after Home appears. New users hit the
            // first-log path via `.onChange(of: events.count)` below.
            evaluateExistingUserTrialOffer()
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
            if isPro, activeSheet == .proIntro || activeSheet == .trialOffer {
                activeSheet = nil
            }
        }
        .onChange(of: storeService.products.count) { _, _ in
            // Products may load after appear — re-evaluate the existing-user path
            // so a returning user with logs but no products yet still gets pitched.
            evaluateExistingUserTrialOffer()
        }
        .onChange(of: storeService.hasResolvedEntitlements) { _, resolved in
            // Entitlements often resolve a beat after the view appears. Re-run the promo paths
            // once we actually know the user isn't Pro — and skip entirely if they are.
            guard resolved else { return }
            offerProIntroIfNeeded()
            evaluateExistingUserTrialOffer()
        }
        .onChange(of: events.count) { oldCount, newCount in
            // First-use trigger: just logged their first headache.
            if oldCount == 0, newCount >= 1 {
                evaluateFirstLogTrialOffer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .headachePatternsDidAppear)) { _ in
            evaluateInsightsTrialOffer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .headachePositiveMomentForReview)) { _ in
            scheduleReviewPromptAfterPositiveMoment()
        }
        .onChange(of: reviewPromptCoordinator.pendingPresentation) { _, presentation in
            guard let presentation else { return }
            defer { reviewPromptCoordinator.clear() }
            guard activeSheet == nil else { return }
            switch presentation {
            case .enjoymentPrompt:
                presentReviewPrompt(step: .enjoyment)
            case .feedbackOnly:
                presentReviewPrompt(step: .feedback)
            }
        }
    }

    /// Passive review ask after a successful log. Waits for the checkmark / snackbar to clear;
    /// never fires on cold launch or alongside trial / Pro intro sheets.
    private func scheduleReviewPromptAfterPositiveMoment() {
        guard hasCompletedOnboarding,
              ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedOnboarding: true),
              !reviewPromptShownThisSession,
              reviewPromptCoordinator.isOnHomeTab,
              activeSheet == nil,
              !captureCoordinator.proPromptShownThisSession
        else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard hasCompletedOnboarding,
                  reviewPromptCoordinator.isOnHomeTab,
                  activeSheet == nil,
                  !captureCoordinator.proPromptShownThisSession,
                  ReviewPromptTracker.shouldShowAfterPositiveMoment(hasCompletedOnboarding: true)
            else { return }
            ReviewPromptTracker.consumePendingPositiveMoment()
            presentReviewPrompt(step: .enjoyment)
        }
    }

    private func handleReviewPromptFinish(_ outcome: ReviewPromptDismissOutcome) {
        // Set the deferred follow-up flag before dismissing so the shared
        // `handleRootSheetDismiss` fires the native review prompt once the sheet closes.
        if outcome == .requestedNativeReview {
            pendingNativeReviewAfterDismiss = true
        }
        activeSheet = nil
    }

    /// Single dismissal handler for the root promo / review sheet. Runs trial-purchase
    /// cleanup and the two deferred follow-ups (chained paywall, native review prompt)
    /// that must fire only after the sheet has fully dismissed. Both follow-ups are
    /// gated on flags that only their own flow sets, so this is safe to run for any sheet.
    private func handleRootSheetDismiss() {
        trialPurchaseInFlight = false
        trialPurchaseError = nil
        if pendingPaywallAfterTrialDismiss {
            pendingPaywallAfterTrialDismiss = false
            activeSheet = .trialPaywall
        }
        if pendingNativeReviewAfterDismiss {
            pendingNativeReviewAfterDismiss = false
            requestReview()
        }
    }

    private func presentReviewPrompt(step: ReviewPromptSheet.Step) {
        reviewPromptInitialStep = step
        reviewPromptShownThisSession = true
        activeSheet = .reviewPrompt
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
    /// Skipped when a free-trial offer is available — the first-log / existing-user trial paths handle that.
    private func offerProIntroIfNeeded() {
        guard hasCompletedOnboarding, !hasSeenProIntro, !storeService.isProUnlocked else { return }
        if hasTrialOffer { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            // Wait until entitlements have resolved so a premium user is never shown the intro.
            guard storeService.hasResolvedEntitlements, !hasSeenProIntro, !storeService.isProUnlocked, activeSheet == nil else { return }
            if hasTrialOffer { return }
            if captureCoordinator.proPromptShownThisSession { return }
            captureCoordinator.proPromptShownThisSession = true
            activeSheet = .proIntro
        }
    }

    /// First-use pitch: just logged their first headache. Waits ~4s so the user
    /// sees the "Context saved" banner and the LatestEventCard populate first —
    /// pitching mid-capture-animation collides with the dashboard and converts worse.
    private func evaluateFirstLogTrialOffer() {
        guard hasCompletedOnboarding,
              !storeService.isProUnlocked,
              !hasSeenTrialOffer,
              hasTrialOffer
        else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            presentTrialOfferIfReady(source: .firstLog)
        }
    }

    /// Existing-user catch-up: already has logs but has never seen the trial pitch.
    /// Fires ~3s after Home appears so the dashboard renders before the sheet.
    private func evaluateExistingUserTrialOffer() {
        guard hasCompletedOnboarding,
              !storeService.isProUnlocked,
              !hasSeenTrialOffer,
              hasTrialOffer,
              events.count > 0
        else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            presentTrialOfferIfReady(source: .existingUser)
        }
    }

    /// Second-touch trial nudge on the Patterns tab. Mirrors vitals' history-load
    /// fallback: uses its own seen-flag so users whose products failed to load
    /// during the first-log path still get a later pitch when Patterns appears.
    /// Gated on the first-log/existing-user path NOT having fired this session,
    /// so the two never stack back-to-back.
    private func evaluateInsightsTrialOffer() {
        guard hasCompletedOnboarding,
              !storeService.isProUnlocked,
              !hasSeenInsightsTrialOffer,
              !firstLogOfferShownThisSession,
              hasTrialOffer,
              activeSheet == nil
        else { return }
        presentTrialOfferIfReady(source: .insights)
    }

    private func presentTrialOfferIfReady(source: TrialOfferSource) {
        // Never pitch before RevenueCat has told us whether the user is already Pro — otherwise a
        // premium user gets a promo (and the sibling-sheet race a blank one) during the launch window.
        guard storeService.hasResolvedEntitlements,
              activeSheet == nil,
              !storeService.isProUnlocked,
              hasTrialOffer
        else { return }
        // If the Home milestone card already claimed this session's Pro moment, don't stack.
        if captureCoordinator.proPromptShownThisSession { return }
        // Gate on the source-specific flag (Insights has its own seen-flag).
        switch source {
        case .firstLog, .existingUser:
            guard !hasSeenTrialOffer else { return }
        case .insights:
            guard !hasSeenInsightsTrialOffer else { return }
        }
        trialPurchaseError = nil
        trialPurchaseInFlight = false
        trialOfferSource = source
        if source != .insights {
            firstLogOfferShownThisSession = true
        }
        // Cap to one Pro moment per session — suppresses the Home milestone card.
        captureCoordinator.proPromptShownThisSession = true
        // Mark the offer seen at present-time (not on dismiss) so it stays a one-shot
        // even if the app is killed while the sheet is up.
        markTrialOfferSeen()
        activeSheet = .trialOffer
    }

    /// Records the one-shot flag for whichever trigger opened the offer.
    /// `hasSeenTrialOffer` always flips so the main path won't re-fire.
    /// `hasSeenInsightsTrialOffer` flips only when source was Insights — leaving
    /// it false after a first-log dismissal lets the Patterns second-touch
    /// still fire in a later session, matching the vitals fallback semantics.
    private func markTrialOfferSeen() {
        hasSeenTrialOffer = true
        if trialOfferSource == .insights {
            hasSeenInsightsTrialOffer = true
        }
    }

    private func startDirectTrialPurchase() {
        guard let package = directTrialPackage else {
            pendingPaywallAfterTrialDismiss = true
            activeSheet = nil
            return
        }
        trialPurchaseError = nil
        trialPurchaseInFlight = true
        Task { @MainActor in
            defer { trialPurchaseInFlight = false }
            do {
                switch try await storeService.purchase(package) {
                case .purchased, .pending:
                    hasSeenTrialOffer = true
                    activeSheet = nil
                case .cancelled:
                    trialPurchaseError = "Trial wasn't started. Tap again, or pick a different plan."
                }
            } catch {
                trialPurchaseError = "Couldn't start your trial. Please try again."
            }
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
                    .environmentObject(store)
                    .task { store.trackPaywallImpression(id: "headache_pro_intro_sheet") }
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
    /// Recurring price after the trial, e.g. "$29.99 / year". Only required in
    /// `directPurchase` mode (Apple 3.1.2 needs price + terms before purchase).
    let priceLabel: String?
    /// When true the primary button buys the trial product directly via StoreKit
    /// and the sheet shows compliant billing disclosure + a "See all plans" link.
    /// When false it chains to the full native paywall via `onSeeAllPlans`.
    let directPurchase: Bool
    let isPurchasing: Bool
    let errorMessage: String?
    let onStartTrial: () -> Void
    let onSeeAllPlans: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject private var store: StoreService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateGlow = false
    @State private var shimmerPhase: CGFloat = -1
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var brandPrimary: Color { Color(red: 0.95, green: 0.25, blue: 0.36) }
    private var brandSecondary: Color { Color(red: 0.86, green: 0.16, blue: 0.43) }
    private var brandGradient: LinearGradient {
        LinearGradient(colors: [brandPrimary, brandSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Extract a clean period phrase from an intro label like `"7-day free trial"` → `"7 days"`.
    /// Falls back to nil when the label doesn't match the expected shape.
    private var trialPeriodPhrase: String? {
        guard let offerLabel else { return nil }
        // Match the leading "N-unit" segment.
        let scanner = Scanner(string: offerLabel)
        var value: Int = 0
        guard scanner.scanInt(&value) else { return nil }
        _ = scanner.scanString("-")
        var unit = ""
        let unitChars = CharacterSet.letters
        guard let scanned = scanner.scanCharacters(from: unitChars) else { return nil }
        unit = scanned
        let plural = value == 1 ? unit : "\(unit)s"
        return "\(value) \(plural)"
    }

    private var headline: String {
        if let period = trialPeriodPhrase {
            return "\(period) of Pro, free."
        }
        return "Try Headache Pro free."
    }

    private var subheadline: String {
        if trialPeriodPhrase != nil {
            return "Personalized patterns, proactive alerts, full exports, no charge until your trial ends."
        }
        return "Personalized patterns, proactive alerts, full exports, free for eligible new subscribers."
    }

    private var trialBullets: [TrialBullet] {
        [
            TrialBullet(
                icon: "barometer",
                tint: .orange,
                title: "Pressure & AQI alerts",
                detail: "Heads-up 12–24h before risky weather matching your personal triggers."
            ),
            TrialBullet(
                icon: "chart.bar.xaxis",
                tint: .indigo,
                title: "Personalized patterns",
                detail: "Sleep, time of day, pressure, weather, surfaced from your own logs."
            ),
            TrialBullet(
                icon: "lock.shield",
                tint: .teal,
                title: "All on-device",
                detail: "Your logs never leave your phone. Forecasts run locally too."
            )
        ]
    }

    private var glowAnimation: Animation {
        .easeInOut(duration: 2.2).repeatForever(autoreverses: true)
    }

    private var shimmerAnimation: Animation {
        .linear(duration: 2.6).repeatForever(autoreverses: false).delay(0.4)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            Circle()
                .fill(brandPrimary.opacity(0.22))
                .frame(width: 220, height: 220)
                .blur(radius: 36)
                .offset(x: animateGlow ? 96 : -96, y: animateGlow ? -220 : -180)
                .animation(glowAnimation, value: animateGlow)
            Circle()
                .fill(brandSecondary.opacity(0.20))
                .frame(width: 180, height: 180)
                .blur(radius: 34)
                .offset(x: animateGlow ? -110 : 110, y: animateGlow ? 250 : 210)
                .animation(glowAnimation, value: animateGlow)
            if !reduceMotion {
                SparkleField(phase: animateGlow ? 1 : 0)
                    .allowsHitTesting(false)
                    .opacity(0.55)
                    .animation(glowAnimation, value: animateGlow)
            }

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(brandGradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: brandPrimary.opacity(0.4), radius: 16, x: 0, y: 6)
                        .scaleEffect(animateGlow ? 1.07 : 0.96)
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 64, height: 64)
                        .scaleEffect(animateGlow ? 1.04 : 0.98)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(animateGlow ? 6 : -6))
                }
                .padding(.top, 18)
                .animation(glowAnimation, value: animateGlow)

                VStack(spacing: 6) {
                    Text(headline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .overlay(shimmerOverlay)
                        .mask(
                            Text(headline)
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .multilineTextAlignment(.center)
                        )
                    Text(subheadline)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                }

                VStack(spacing: 10) {
                    ForEach(trialBullets) { bullet in
                        TrialBulletRow(bullet: bullet)
                    }
                }
                .padding(.horizontal, 4)

                if directPurchase, let priceLabel {
                    Text("Free during your trial, then \(priceLabel). Cancel anytime in Settings, at least 24h before the trial ends to avoid the charge.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                Group {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: errorMessage)

                VStack(spacing: 10) {
                    Button(action: onStartTrial) {
                        ZStack {
                            Text("Start My Free Trial")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(isPurchasing ? 0 : 1)
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(brandGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)

                    Text("Billed through Apple. No charge during the trial.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    if directPurchase {
                        Button(action: onSeeAllPlans) {
                            Text("See all plans")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(brandPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isPurchasing)
                    }

                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)

                    Button(action: startRestore) {
                        Text(isRestoring ? "Restoring…" : "Restore Purchases")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoring || isPurchasing)

                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                HStack(spacing: 4) {
                    Link("Terms", destination: PaywallLinks.standardEULA)
                    Text("·")
                    Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
                }
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            guard !reduceMotion else { return }
            animateGlow = true
            shimmerPhase = 1.4
        }
    }

    private func startRestore() {
        restoreMessage = nil
        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            await store.restorePurchases()
            if !store.isProUnlocked {
                restoreMessage = store.lastError ?? "No previous Headache Pro purchase was found on this Apple ID."
            }
        }
    }

    private var shimmerOverlay: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white.opacity(0.55), location: 0.5),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.5)
            .offset(x: shimmerPhase * width)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .animation(shimmerAnimation, value: shimmerPhase)
        }
    }
}

private struct TrialBullet: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let detail: String
}

private struct TrialBulletRow: View {
    let bullet: TrialBullet

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(bullet.tint.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: bullet.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(bullet.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bullet.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(bullet.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground).opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(bullet.tint.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bullet.title). \(bullet.detail)")
    }
}

/// Lightweight ambient "shine" — a handful of tiny dots that drift + pulse
/// behind the hero icon. Driven by `phase` (0…1) so the parent owns the
/// animation lifecycle.
private struct SparkleField: View {
    let phase: CGFloat

    private struct Sparkle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let driftX: CGFloat
        let driftY: CGFloat
        let opacity: Double
        let phaseOffset: CGFloat
    }

    private static let sparkles: [Sparkle] = (0..<14).map { i in
        // Deterministic pseudo-random so layout doesn't jitter on re-render.
        let seed = Double(i) * 12.9898
        let r1 = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let r2 = (sin(seed + 1) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let r3 = (sin(seed + 2) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let r4 = (sin(seed + 3) * 43758.5453).truncatingRemainder(dividingBy: 1)
        return Sparkle(
            id: i,
            x: CGFloat(abs(r1)) * 320 - 160,
            y: CGFloat(abs(r2)) * 460 - 230,
            size: 2 + CGFloat(abs(r3)) * 3,
            driftX: CGFloat(r4) * 12,
            driftY: CGFloat(r3 - 0.5) * 18,
            opacity: 0.35 + abs(r2) * 0.5,
            phaseOffset: CGFloat(abs(r1))
        )
    }

    var body: some View {
        ZStack {
            ForEach(Self.sparkles) { sparkle in
                Circle()
                    .fill(.white)
                    .frame(width: sparkle.size, height: sparkle.size)
                    .opacity(sparkle.opacity * (0.4 + 0.6 * Double(abs(sin(.pi * (phase + sparkle.phaseOffset))))))
                    .offset(x: sparkle.x + sparkle.driftX * phase,
                            y: sparkle.y + sparkle.driftY * phase)
                    .blur(radius: 0.4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
