import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false

    @State private var step = 0
    @State private var isWorking = false

    private static let totalSteps = 3
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
                    default: welcomePage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func page<Icon: View, Content: View>(
        icon: Icon,
        title: String,
        @ViewBuilder body: () -> Content,
        primaryLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            icon
            Text(title)
                .font(.title.bold())
            body()
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                action()
            } label: {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(primaryLabel)
                }
            }
            .disabled(isWorking)
            .buttonStyle(.borderedProminent)
            .tint(Self.brandColor)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
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
            },
            primaryLabel: "Get Started",
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
            },
            primaryLabel: "Continue",
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
            },
            primaryLabel: "Continue",
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
