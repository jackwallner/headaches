import SwiftData
import SwiftUI
import RevenueCatUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false

    @State private var step = 0
    @State private var isWorking = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0:
                    welcomePage
                case 1:
                    healthPage
                case 2:
                    locationPage
                case 3:
                    severityNotesPage
                case 4:
                    proPitchPage
                case 5:
                    quizPage
                default:
                    welcomePage
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall, onDismiss: { step = 5 }) {
                PaywallView()
            }
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("One Tap Headache Tracker")
                .font(.largeTitle.bold())
            Text("Log headaches with one tap. The app enriches each entry with time, optional Apple Health context, and optional local weather — so you and your clinician can spot patterns.")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") {
                step = 1
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var healthPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Apple Health", systemImage: "heart.text.square.fill")
                .font(.title2.bold())
                .foregroundStyle(.pink)
            Text("Next, iOS will ask whether to allow read access to metrics like activity, sleep, heart rate, and workouts. Nothing is written to Health, and you can change this anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task { await enableHealthTapped() }
            } label: {
                if isWorking {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Continue")
                }
            }
            .disabled(isWorking)
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var locationPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Location", systemImage: "location.fill")
                .font(.title2.bold())
                .foregroundStyle(.blue)
            Text("Next, iOS will ask whether to share your location. It is used only to fetch approximate weather and place labels when you log. We don’t track you in the background.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task { await enableLocationTapped() }
            } label: {
                if isWorking {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Continue")
                }
            }
            .disabled(isWorking)
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var severityNotesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Event Details", systemImage: "note.text")
                .font(.title2.bold())
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
            Text("Would you like to record severity and notes each time you log a headache? You can change this in Settings later.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    HeadacheOnboardingStore.promptForSeverityNotes = true
                    step = 4 // Pro pitch
                } label: {
                    Text("Enable")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(maxWidth: .infinity)

                Button("Skip") {
                    HeadacheOnboardingStore.promptForSeverityNotes = false
                    step = 4 // Pro pitch
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private func enableHealthTapped() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await HealthKitService.shared.prepareAuthorizationDuringOnboarding()
        } catch {
            // OS prompt was presented (or HealthKit is unavailable). Either way advance —
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

    private var proPitchPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Headache Pro", systemImage: "sparkles")
                    .font(.title2.bold())
                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))

                Text("Find what's actually triggering your headaches")
                    .font(.title3.bold())

                Text("Pro analyses every headache you log against the time, sleep, weather, pressure and air-quality context already attached to it — then keeps alerts quiet until your own data supports a trigger.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    ProPitchBullet(
                        icon: "chart.bar.xaxis",
                        title: "Personalized pattern recognition",
                        detail: "After ~5 logs, Pro starts highlighting things like \"40% of your headaches happen in the evening\" or \"62% follow a barometric pressure drop\" — with a chart for each one."
                    )
                    ProPitchBullet(
                        icon: "barometer",
                        title: "Weather & pressure triggers",
                        detail: "Identifies whether falling pressure, high humidity, or AQI spikes line up with your attacks — backed by a 6-hour pressure-shift histogram."
                    )
                    ProPitchBullet(
                        icon: "bell.badge.fill",
                        title: "Heads-up alerts",
                        detail: "Once a pattern is supported, get notified before forecast conditions match it, with the personal lift shown in the alert."
                    )
                    ProPitchBullet(
                        icon: "lock.shield",
                        title: "On-device only",
                        detail: "Pattern analysis runs locally. Your headache data never leaves your phone."
                    )
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    showPaywall = true
                } label: {
                    Text("See Pro plans")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .controlSize(.large)

                Button("Maybe later") {
                    step = 5
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private var quizPage: some View {
        HeadacheQuizView(hasCompleted: Binding(
            get: { false },
            set: { if $0 { finishOnboarding() } }
        ))
    }

    private func finishOnboarding() {
        HeadacheOnboardingStore.hasSeenProIntro = true
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

private struct ProPitchBullet: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
