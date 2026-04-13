import Foundation

/// App group shared by iPhone app and Watch companion (onboarding flags, etc.).
enum HeadacheAppGroup {
    static let identifier = "group.com.jackwallner.headachelogger"

    static var userDefaults: UserDefaults {
        guard let suite = UserDefaults(suiteName: identifier) else {
            fatalError("HeadacheAppGroup: could not open UserDefaults suite \(identifier)")
        }
        return suite
    }
}

enum HeadacheStorageKey: String {
    case hasCompletedOnboarding = "hasCompletedHeadacheOnboarding"
    case declinedHealthRead = "headacheDeclinedHealthRead"
    case declinedLocation = "headacheDeclinedLocation"
    /// When false (default), UI shows **Fahrenheit**. When true, UI shows Celsius. SwiftData still stores °C.
    case useCelsiusTemperature = "headacheUseCelsiusTemperature"
    /// Timestamp of the most recent widget quick-log, for brief confirmation UI.
    case widgetLastLoggedAt = "headacheWidgetLastLoggedAt"
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

    /// Reset for UI tests / previews only.
    static func resetForTesting() {
        hasCompletedOnboarding = false
        declinedHealthRead = false
        declinedLocation = false
    }
}

/// Markers left on events created by the widget before Health/weather are captured in the main app.
enum HeadacheWidgetQuickLog {
    public static let healthMessagePending = "Open the app to capture Health context."
    public static let environmentMessagePending = "Open the app to capture weather."
}
