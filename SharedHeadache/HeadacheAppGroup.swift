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
    /// True after the existing-user Pro intro sheet has been shown (or dismissed) once.
    case hasSeenProIntro = "headacheHasSeenProIntro"
    /// True after the free-trial offer sheet has been shown (or dismissed) once.
    case hasSeenTrialOffer = "headacheHasSeenTrialOffer"

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
    case proAlertPersonalProfile = "headacheProAlertPersonalProfile"
    /// Cached last-known coordinates so the background task can fetch a forecast without "Always" auth.
    case lastKnownLatitude = "headacheLastKnownLatitude"
    case lastKnownLongitude = "headacheLastKnownLongitude"
    case lastKnownLocationCapturedAt = "headacheLastKnownLocationCapturedAt"

    // MARK: - Pattern-based predictive alerts
    case patternAlertsEnabled = "headachePatternAlertsEnabled"
    /// 0 = high-chance only (conservative, fewer false alarms), 1 = any chance (more alerts)
    case patternAlertSensitivity = "headachePatternAlertSensitivity"

    // MARK: - Usage-based Pro prompts
    /// True after the user has been prompted about Pro at the 3-log milestone.
    case milestonePrompt3Shown = "headacheMilestonePrompt3Shown"
    /// True after the user has been prompted about Pro at the 5-log milestone.
    case milestonePrompt5Shown = "headacheMilestonePrompt5Shown"
    /// True after the user has been prompted about Pro at the 10-log milestone.
    case milestonePrompt10Shown = "headacheMilestonePrompt10Shown"
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

    static var hasSeenProIntro: Bool {
        get { HeadacheAppGroup.userDefaults.bool(forKey: HeadacheStorageKey.hasSeenProIntro.rawValue) }
        set { HeadacheAppGroup.userDefaults.set(newValue, forKey: HeadacheStorageKey.hasSeenProIntro.rawValue) }
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
