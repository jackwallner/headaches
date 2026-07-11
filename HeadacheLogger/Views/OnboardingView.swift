import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: StoreService
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false
    @AppStorage(HeadacheStorageKey.hasSeenProIntro.rawValue, store: HeadacheAppGroup.userDefaults) private var hasSeenProIntro = false
    @AppStorage(HeadacheStorageKey.hasSeenTrialOffer.rawValue, store: HeadacheAppGroup.userDefaults) private var hasSeenTrialOffer = false

    @State private var step = 0
    @State private var isWorking = false
    @State private var isPurchasing = false
    @State private var trialError: String?
    @State private var showPaywallFallback = false

    private static let totalSteps = 4
    private static let brandColor = Color(red: 0.95, green: 0.25, blue: 0.36)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(Self.totalSteps))
                    .tint(Self.brandColor)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Group {
                    switch step {
                    case 0: welcomePage
                    case 1: healthPage
                    case 2: locationPage
                    case 3: trialPage
                    default: welcomePage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
        // Prefetch products/offerings early so the trial step has live price and
        // trial copy the moment it appears.
        .task {
            if store.currentOffering == nil {
                await store.fetchProducts()
            }
        }
        .fullScreenCover(isPresented: $showPaywallFallback, onDismiss: { finishOnboarding() }) {
            PaywallView()
                .environmentObject(store)
                .task { store.trackPaywallImpression(id: "headache_onboarding_trial") }
        }
    }

    /// Unified onboarding page. Every step routes through this so the primary
    /// button lands at a pixel-identical frame (Rev A zero-shift CTA):
    ///   - All variable content (soft exit, disclosure, error) is passed via
    ///     `aboveButton` and sits ABOVE the primary, absorbed by the Spacer.
    ///   - A fixed-height legal-footer slot is rendered BELOW the primary on EVERY
    ///     step (real links on the trial step, invisible placeholder elsewhere) so
    ///     the distance from the button to the screen bottom is byte-identical.
    private func page<Icon: View, Content: View, Above: View>(
        icon: Icon,
        title: String,
        @ViewBuilder body: () -> Content,
        @ViewBuilder aboveButton: () -> Above = { EmptyView() },
        primaryLabel: String,
        busy: Bool,
        showLegalFooter: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            icon
            Text(title)
                .font(.title.bold())
            body()
            Spacer()
            VStack(spacing: 12) {
                aboveButton()

                Button {
                    action()
                } label: {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text(primaryLabel)
                    }
                }
                .disabled(busy)
                .buttonStyle(.borderedProminent)
                .tint(Self.brandColor)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                // Fixed-height legal-footer slot on EVERY step. Reserving the space
                // even when empty keeps the primary button's frame identical across
                // the flow so the thumb never moves.
                legalFooter
                    .opacity(showLegalFooter ? 1 : 0)
                    .allowsHitTesting(showLegalFooter)
                    .accessibilityHidden(!showLegalFooter)
            }
        }
        .padding(24)
    }

    private var welcomePage: some View {
        page(
            icon: Image(systemName: "brain.head.profile")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Self.brandColor),
            title: "One Tap Headache Tracker",
            body: {
                Text("Log a headache with a single tap. The app quietly captures time, optional Apple Health context, and optional local weather so you can spot patterns.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            },
            primaryLabel: "Get Started",
            busy: false,
            action: { step = 1 }
        )
    }

    private var healthPage: some View {
        page(
            icon: Image(systemName: "heart.text.square.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.pink),
            title: "Apple Health",
            body: {
                Text("Next, iOS will ask whether to allow read access to metrics like activity, sleep, heart rate, and workouts. Nothing is written to Health, and you can change this anytime in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            },
            primaryLabel: "Continue",
            busy: isWorking,
            action: { Task { await enableHealthTapped() } }
        )
    }

    private var locationPage: some View {
        page(
            icon: Image(systemName: "location.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.blue),
            title: "Location",
            body: {
                Text("Next, iOS will ask whether to share your location. It's used only to fetch approximate weather and place labels when you log. We don't track you in the background.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            },
            primaryLabel: "Continue",
            busy: isWorking,
            action: { Task { await enableLocationTapped() } }
        )
    }

    /// Terms / Privacy / Restore. Rendered on every onboarding step (invisible off
    /// the trial step) so its height reserves the same space under the CTA.
    private var legalFooter: some View {
        HStack(spacing: 12) {
            Link("Terms of Use", destination: PaywallLinks.standardEULA)
            Text("·").foregroundStyle(.tertiary)
            Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
            Text("·").foregroundStyle(.tertiary)
            Button("Restore") {
                Task { await store.restorePurchases() }
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func enableHealthTapped() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await HealthKitService.shared.prepareAuthorizationDuringOnboarding()
        } catch {
            // Apple requires the pre-prompt screen to always proceed to the system flow.
            await HealthKitService.shared.markHealthSkippedInOnboarding()
        }
        await MainActor.run { step = 2 }
    }

    private func enableLocationTapped() async {
        isWorking = true
        defer { isWorking = false }
        await EnvironmentService.shared.prepareLocationAuthorizationDuringOnboarding()
        await MainActor.run { step = 3 }
    }

    // MARK: - Trial step

    /// Fourth onboarding step: the same `page(...)` chrome as Health/Location
    /// (progress bar now 4/4, "Welcome" nav title, pink-red primary). The primary
    /// button is in the exact same frame as the prior Continues; all trial-only
    /// content (soft "Get Started" exit, billing disclosure, error) sits ABOVE it,
    /// and the real Terms/Privacy/Restore footer fills the reserved slot below.
    /// Reads as the next onboarding step, not a paywall sheet.
    private var trialPage: some View {
        page(
            icon: Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Self.brandColor),
            title: "Get ahead of your headaches",
            body: {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Headache Pro turns your logs into a heads-up so you can plan around risky days.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    trialBullet(icon: "chart.bar.xaxis", text: "Spot your personal patterns across sleep, timing, and weather")
                    trialBullet(icon: "barometer", text: "Pressure and air-quality heads-up 12-24h before risky weather")
                    trialBullet(icon: "lock.shield", text: "All processing stays on your device")
                }
            },
            aboveButton: { trialAboveButton },
            primaryLabel: store.yearlyPackage != nil ? store.yearlyCTALabel : "Start 7-day free trial",
            busy: isPurchasing,
            showLegalFooter: true,
            action: { startTrialPurchase() }
        )
        .onAppear(perform: handleTrialStepAppear)
    }

    private func trialBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Self.brandColor)
                .frame(width: 24)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Trial-only content that sits ABOVE the primary CTA (absorbed by the Spacer
    /// so it never shifts the button): soft free exit, billing disclosure, error.
    @ViewBuilder
    private var trialAboveButton: some View {
        VStack(spacing: 12) {
            // Soft free exit sits ABOVE the primary so the trial button lands in the
            // exact spot the user has been tapping "Continue". Rev A: labeled
            // "Get Started" (StatScout soft-exit label), visually secondary.
            Button("Get Started") {
                finishOnboarding()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .disabled(isPurchasing)

            // No disclosure until the package (and its real price) loads — never a
            // placeholder price (Apple 3.1.2).
            if let disclosure = store.yearlyCTADisclosureText {
                Text(disclosure)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let trialError {
                Text(trialError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Stamp the mid-app trial offer as seen so it doesn't double-pitch right
    /// after onboarding, and report the impression.
    private func handleTrialStepAppear() {
        hasSeenTrialOffer = true
        store.trackPaywallImpression(id: "headache_onboarding_trial", oncePerSession: true)
    }

    /// One-tap conversion: buy the yearly plan in place (trial when eligible).
    /// Products failing to load falls back to the full PaywallView rather than a
    /// dead button; a successful purchase or the emergency paywall both finish
    /// onboarding.
    private func startTrialPurchase() {
        guard let yearly = store.yearlyPackage else {
            showPaywallFallback = true
            return
        }
        trialError = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            do {
                switch try await store.purchase(yearly) {
                case .purchased, .pending:
                    finishOnboarding()
                case .cancelled:
                    trialError = "Trial wasn't started. Tap again, or choose Get Started."
                }
            } catch {
                trialError = store.lastError ?? "Couldn't start your trial. Please try again."
            }
        }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        // The "Headache Pro is here" intro is a catch-up for users who finished onboarding
        // before Pro shipped. Net-new users learn about Pro through the trial/milestone
        // paths, so mark the intro seen here or it presents right after onboarding.
        hasSeenProIntro = true
        Task { await initializeDailyRecords() }
    }

    private func initializeDailyRecords() async {
        let allEvents = (try? modelContext.fetch(FetchDescriptor<HeadacheEvent>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        guard let firstEvent = allEvents.first else {
            let today = DailyRecordStore.normalizeDate(Date())
            let record = DailyRecord(date: today, hadHeadache: false, headacheCount: 0, pressureTrendRaw: PressureTrend.unavailable.rawValue, usAQI: nil, weatherFetched: false, sleepHoursLastNight: nil, sleepFetched: false)
            DailyRecordStore.save([record])
            return
        }

        var records = DailyRecordStore.rebuild(from: allEvents)
        let startDate = DailyRecordStore.normalizeDate(firstEvent.timestamp)
        records = DailyRecordStore.fillGapDays(records, from: startDate)

        if let coord = CachedLocation.current() {
            records = await DailyWeatherBackfillService.backfill(for: records, latitude: coord.latitude, longitude: coord.longitude)
        }

        DailyRecordStore.save(records)
    }
}
