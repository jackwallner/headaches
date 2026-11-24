import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: StoreService
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false
    @AppStorage(HeadacheStorageKey.hasSeenProIntro.rawValue, store: HeadacheAppGroup.userDefaults) private var hasSeenProIntro = false

    @State private var step = 0
    @State private var isWorking = false

    private static let totalSteps = 3
    private static let brandColor = AppTheme.brandText

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
                    default: welcomePage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padReadableColumn(maxWidth: 560, maxHeight: 720)
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Unified onboarding page. Every step routes through this so the primary
    /// button lands at a pixel-identical frame and the thumb never moves.
    ///
    /// Onboarding ends at Location, as before 1.4.8. The trial is pitched after
    /// the first logged headache (`TrialOfferSheet` in `HeadacheLoggerApp`): the
    /// onboarding trial step that 1.4.8 added took Migraine from $2.27 to $0.00
    /// per new customer (2026-11-24 change-impact read), so it is gone.
    private func page<Icon: View, Content: View>(
        icon: Icon,
        title: String,
        @ViewBuilder body: () -> Content,
        primaryLabel: String,
        busy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Scrolls rather than truncates. A plain VStack hands its flexible Text
            // children whatever height is left over, and on a short container (iPad
            // Split View, a resized window, landscape) that is one line each, so
            // every paragraph renders clipped mid-word. App Review hit exactly
            // that. The button stays outside the ScrollView so its frame is
            // unchanged from step to step.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    icon
                    Text(title)
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    body()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button {
                action()
            } label: {
                Group {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text(primaryLabel)
                    }
                }
                // Inside the label, so the button is the same width on every step.
                .frame(maxWidth: .infinity)
            }
            .disabled(busy)
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.brand)
            .controlSize(.large)
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
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
                .foregroundStyle(AppTheme.pink),
            title: "Apple Health",
            body: {
                Text("Next, iOS will ask whether to allow read access to metrics like activity, sleep, heart rate, and workouts. Nothing is written to Health, and you can change this anytime in Settings.")
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
                .foregroundStyle(AppTheme.blue),
            title: "Location",
            body: {
                Text("Next, iOS will ask whether to share your location. It's used only to fetch approximate weather and place labels when you log. We don't track you in the background.")
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            },
            primaryLabel: "Continue",
            busy: isWorking,
            action: { Task { await enableLocationTapped() } }
        )
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
        await MainActor.run { finishOnboarding() }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        // The "Headache Pro is here" intro is a catch-up for users who finished onboarding
        // before Pro shipped. Net-new users learn about Pro through the first-log trial
        // sheet, so mark the intro seen here or it presents right after onboarding.
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

/// The pane beside onboarding on the unfolded iPhone Duo: the Log Headache
/// button the setup leads to, so the second half of the display previews the
/// app rather than sitting empty.
struct OnboardingFoldPanel: View {
    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 56, weight: .bold))
                Text("Log Headache")
                    .font(.system(size: 28, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 320)
            .padding(.vertical, 44)
            .background(
                LinearGradient(
                    colors: [AppTheme.brand, AppTheme.brandEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: AppTheme.brandEnd.opacity(0.30), radius: 18, x: 0, y: 10)
            VStack(spacing: 8) {
                Text("One tap. Logged.")
                    .font(.title2.weight(.semibold))
                Text("Weather, sleep and steps are saved with every entry.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}
