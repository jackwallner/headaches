import Foundation

enum AppEnvironment {
    static var isUITesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitesting")
        #else
        return false
        #endif
    }

    /// Treat onboarding as complete during UI tests (no interactive Health/Location sheets).
    static var bypassOnboarding: Bool { isUITesting }
}
