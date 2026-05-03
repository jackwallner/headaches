import Foundation

/// App group shared by iPhone app and Watch companion (onboarding flags, etc.).
enum HeadacheAppGroup {
    static let identifier = "group.com.jackwallner.headachelogger"

    /// `UserDefaults` is documented as thread-safe, so `nonisolated(unsafe)` is correct under
    /// Swift 6 strict concurrency. The suite pointer itself never changes after launch.
    nonisolated(unsafe) static let userDefaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}

enum HeadacheStorageKey: String {
    case hasCompletedOnboarding = "hasCompletedHeadacheOnboarding"
    case declinedHealthRead = "headacheDeclinedHealthRead"
    case declinedLocation = "headacheDeclinedLocation"
    /// When false (default), UI shows **Fahrenheit**. When true, UI shows Celsius. SwiftData still stores °C.
    case useCelsiusTemperature = "headacheUseCelsiusTemperature"
    /// Timestamp of the most recent widget quick-log, for brief confirmation UI.
    case widgetLastLoggedAt = "headacheWidgetLastLoggedAt"
    /// When true, the app prompts for severity and notes after each one-tap log.
    case promptForSeverityNotes = "headachePromptForSeverityNotes"

    // MARK: - Pro / Proactive Alerts
    case proAlertsEnabled = "headacheProAlertsEnabled"
    case proAlertPressureDropThreshold = "headacheProAlertPressureDropThreshold"
    case proAlertAirQualityEnabled = "headacheProAlertAirQualityEnabled"
    case proAlertAirQualityThreshold = "headacheProAlertAirQualityThreshold"
    case proAlertQuietHoursEnabled = "headacheProAlertQuietHoursEnabled"
    case proAlertQuietStartHour = "headacheProAlertQuietStartHour"
    case proAlertQuietEndHour = "headacheProAlertQuietEndHour"
    case proAlertLastFiredAt = "headacheProAlertLastFiredAt"
    case proAlertLastFiredKind = "headacheProAlertLastFiredKind"
    /// Cached last-known coordinates so the background task can fetch a forecast without "Always" auth.
    case lastKnownLatitude = "headacheLastKnownLatitude"
    case lastKnownLongitude = "headacheLastKnownLongitude"
    case lastKnownLocationCapturedAt = "headacheLastKnownLocationCapturedAt"
}

enum HeadacheOnboardingStore {
    static var hasCompletedOnboarding: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.hasCompletedOnboarding.rawValue) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: HeadacheStorageKey.hasCompletedOnboarding.rawValue) }
    }

    static var declinedHealthRead: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.declinedHealthRead.rawValue) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: HeadacheStorageKey.declinedHealthRead.rawValue) }
    }

    static var declinedLocation: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.declinedLocation.rawValue) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: HeadacheStorageKey.declinedLocation.rawValue) }
    }

    static var promptForSeverityNotes: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.promptForSeverityNotes.rawValue) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: HeadacheStorageKey.promptForSeverityNotes.rawValue) }
    }

    /// Reset for UI tests / previews only.
    static func resetForTesting() {
        hasCompletedOnboarding = false
        declinedHealthRead = false
        declinedLocation = false
        promptForSeverityNotes = false
    }
}

/// Markers left on events created by the widget before Health/weather are captured in the main app.
enum HeadacheWidgetQuickLog {
    public static let healthMessagePending = "Open the app to capture Health context."
    public static let environmentMessagePending = "Open the app to capture weather."
}
