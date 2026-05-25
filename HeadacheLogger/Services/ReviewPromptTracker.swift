import Foundation

extension Notification.Name {
    /// Posted when the user completes a successful one-tap log — host may present the enjoyment funnel after a short delay.
    static let headachePositiveMomentForReview = Notification.Name("com.jackwallner.headachelogger.positiveMomentForReview")
}

/// How the user last resolved the in-app review / feedback prompt.
enum ReviewPromptOutcome: String, Sendable {
    /// Opened the App Store write-review page (explicit CTA).
    case openedWriteReview
    /// Opened the feedback mail composer with a message.
    case submittedFeedback
}

/// Persists launch counts, positive moments, and review-prompt eligibility in the app group.
@MainActor
enum ReviewPromptTracker {
    private static let defaults = HeadacheAppGroup.userDefaults

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let outcomeKey = "reviewPrompt.outcome"
    private static let positiveMomentCountKey = "reviewPrompt.positiveMomentCount"
    private static let pendingPositiveMomentKey = "reviewPrompt.pendingPositiveMoment"

    /// Minimum cold starts before passive prompts are considered.
    static let minimumLaunchCount = 5
    /// Minimum days since first open.
    static let minimumDaysSinceFirstOpen = 7
    /// Days before "Not now" can surface the enjoyment prompt again.
    static let cooldownDays = 120

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: launchCountKey), 0) }
        set { defaults.set(newValue, forKey: launchCountKey) }
    }

    static var firstAppOpenDate: Date? {
        get { defaults.object(forKey: firstOpenKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: firstOpenKey)
            } else {
                defaults.removeObject(forKey: firstOpenKey)
            }
        }
    }

    static var lastShownDate: Date? {
        get { defaults.object(forKey: lastShownKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: lastShownKey)
            } else {
                defaults.removeObject(forKey: lastShownKey)
            }
        }
    }

    static var outcome: ReviewPromptOutcome? {
        get {
            guard let raw = defaults.string(forKey: outcomeKey) else { return nil }
            return ReviewPromptOutcome(rawValue: raw)
        }
        set {
            if let value = newValue {
                defaults.set(value.rawValue, forKey: outcomeKey)
            } else {
                defaults.removeObject(forKey: outcomeKey)
            }
        }
    }

    static var positiveMomentCount: Int {
        get { max(defaults.integer(forKey: positiveMomentCountKey), 0) }
        set { defaults.set(newValue, forKey: positiveMomentCountKey) }
    }

    /// Set when a positive moment fires; cleared when a passive prompt is shown or consumed.
    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: pendingPositiveMomentKey) }
        set { defaults.set(newValue, forKey: pendingPositiveMomentKey) }
    }

    /// Call once per process launch (e.g. from `HeadacheLoggerApp.init`).
    static func recordAppLaunch(now: Date = .now) {
        if firstAppOpenDate == nil {
            firstAppOpenDate = now
        }
        appLaunchCount += 1
    }

    /// Call after a satisfaction moment (e.g. successful one-tap log with context saved).
    static func recordPositiveMoment() {
        positiveMomentCount += 1
        hasPendingPositiveMoment = true
    }

    static func consumePendingPositiveMoment() {
        hasPendingPositiveMoment = false
    }

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome == nil else { return false }
        guard let last = lastShownDate else { return true }
        let cooldown = TimeInterval(cooldownDays) * 86_400
        return now.timeIntervalSince(last) >= cooldown
    }

    /// Base eligibility for the enjoyment funnel (passive or Settings).
    static func canPresentEnjoymentPrompt(
        hasCompletedOnboarding: Bool,
        now: Date = .now
    ) -> Bool {
        guard !AppEnvironment.isUITesting else { return false }
        guard hasCompletedOnboarding else { return false }
        guard passivePromptAllowed(now: now) else { return false }
        guard appLaunchCount >= minimumLaunchCount else { return false }
        guard let first = firstAppOpenDate else { return false }
        let minInterval = TimeInterval(minimumDaysSinceFirstOpen) * 86_400
        guard now.timeIntervalSince(first) >= minInterval else { return false }
        return true
    }

    /// Passive prompt: eligibility plus a recent positive moment.
    static func shouldShowAfterPositiveMoment(
        hasCompletedOnboarding: Bool,
        now: Date = .now
    ) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canPresentEnjoymentPrompt(hasCompletedOnboarding: hasCompletedOnboarding, now: now)
    }

    static func markShown(now: Date = .now) {
        lastShownDate = now
        consumePendingPositiveMoment()
    }

    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    static func markFeedbackSubmitted() {
        outcome = .submittedFeedback
        markShown()
    }
}
