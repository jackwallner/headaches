import SwiftUI

struct OnboardingView: View {
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false

    @State private var step = 0
    @State private var isWorking = false

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
                default:
                    welcomePage
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
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
                    finishOnboarding()
                } label: {
                    Text("Enable")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .frame(maxWidth: .infinity)

                Button("Skip") {
                    HeadacheOnboardingStore.promptForSeverityNotes = false
                    finishOnboarding()
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
        finishOnboarding()
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
    }
}
