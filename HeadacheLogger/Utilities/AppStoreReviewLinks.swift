import Foundation

/// App Store review deep links for One Tap Headache Tracker.
enum AppStoreReviewLinks {
    static let appStoreID = "6762074561"

    /// Opens the App Store write-review page (use for explicit user-initiated rating CTAs).
    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }
}
