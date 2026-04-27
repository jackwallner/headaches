import AppIntents
import SwiftData
import WidgetKit

/// One-tap log from the Home Screen widget. Runs in the widget extension: no HealthKit or location here;
/// the event is stored at tap time; the main app enriches Health + weather using **that** timestamp when it opens.
struct LogHeadacheIntent: AppIntent {
    static let title: LocalizedStringResource = "Log headache"
    static let description: IntentDescription = "Records a headache in One Tap Headache Tracker."

    /// Keep the user on the Home Screen after tapping.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard HeadacheOnboardingStore.hasCompletedOnboarding else {
            // C20: the banner dialog is easy to miss. Surface a clearer call-to-action so users
            // understand why the tap didn't log and what to do. (Changing `openAppWhenRun` to
            // open the app on this path would require divergent return types across branches,
            // which AppIntent cannot express; opening the app remains a manual step.)
            return .result(dialog: IntentDialog("Open One Tap Headache Tracker and finish setup to enable one-tap logging."))
        }

        do {
            try await MainActor.run {
                try Self.insertQuickLog()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            print("LogHeadacheIntent: save failed | error=\(String(describing: error))")
            throw error
        }

        HeadacheAppGroup.userDefaults.set(Date().timeIntervalSince1970,
                                          forKey: HeadacheStorageKey.widgetLastLoggedAt.rawValue)

        return .result(dialog: IntentDialog("Headache logged."))
    }

    @MainActor
    private static func insertQuickLog() throws {
        let container = HeadacheModelStore.sharedModelContainer
        let context = ModelContext(container)
        let event = HeadacheEvent()
        context.insert(event)
        event.apply(
            HealthCaptureResult(
                status: .unavailable,
                message: HeadacheWidgetQuickLog.healthMessagePending,
                snapshot: nil
            )
        )
        event.apply(
            EnvironmentCaptureResult(
                status: .unavailable,
                message: HeadacheWidgetQuickLog.environmentMessagePending,
                snapshot: nil
            )
        )
        event.finalizeCapture()
        try context.save()
    }
}
