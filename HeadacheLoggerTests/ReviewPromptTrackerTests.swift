import XCTest
@testable import OneTapHeadacheTracker

/// The rating-ask rules from the fleet policy: ask from the second launch, wait
/// out a 30-day cooldown, stop only when the user opened the review page, and
/// never let feedback stop or restart the asks.
@MainActor
final class ReviewPromptTrackerTests: XCTestCase {
    private var saved: (Int, Date?, Date?, ReviewPromptOutcome?, Int, Bool)!

    override func setUp() async throws {
        saved = (
            ReviewPromptTracker.appLaunchCount,
            ReviewPromptTracker.firstAppOpenDate,
            ReviewPromptTracker.lastShownDate,
            ReviewPromptTracker.outcome,
            ReviewPromptTracker.positiveMomentCount,
            ReviewPromptTracker.hasPendingPositiveMoment
        )
        ReviewPromptTracker.appLaunchCount = 9
        ReviewPromptTracker.firstAppOpenDate = .now
        ReviewPromptTracker.lastShownDate = nil
        ReviewPromptTracker.outcome = nil
        ReviewPromptTracker.positiveMomentCount = 0
        ReviewPromptTracker.hasPendingPositiveMoment = false
    }

    override func tearDown() async throws {
        ReviewPromptTracker.appLaunchCount = saved.0
        ReviewPromptTracker.firstAppOpenDate = saved.1
        ReviewPromptTracker.lastShownDate = saved.2
        ReviewPromptTracker.outcome = saved.3
        ReviewPromptTracker.positiveMomentCount = saved.4
        ReviewPromptTracker.hasPendingPositiveMoment = saved.5
    }

    private func days(_ n: Double) -> Date { Date.now.addingTimeInterval(n * 86_400) }

    func testAsksFromTheSecondLaunch() {
        ReviewPromptTracker.appLaunchCount = 2
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testNeverAsksInTheFirstSession() {
        ReviewPromptTracker.appLaunchCount = 1
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testFirstPositiveMomentIsEnoughOnTheSecondLaunch() {
        ReviewPromptTracker.appLaunchCount = 2
        ReviewPromptTracker.recordPositiveMoment()
        XCTAssertTrue(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: true))
    }

    func testRequiresFinishedOnboarding() {
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: false))
    }

    func testWaitsOutTheCooldown() {
        ReviewPromptTracker.markShown()
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: days(29)))
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: days(31)))
    }

    func testOpeningTheReviewPageEndsTheAsks() {
        ReviewPromptTracker.markOpenedWriteReview()
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: days(400)))
    }

    func testFeedbackDoesNotStopTheAsks() {
        ReviewPromptTracker.markFeedbackSubmitted()
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true))
    }

    func testFeedbackAfterTheReviewPageKeepsTheAsksEnded() {
        ReviewPromptTracker.markOpenedWriteReview()
        ReviewPromptTracker.markFeedbackSubmitted()
        XCTAssertEqual(ReviewPromptTracker.outcome, .openedWriteReview)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: days(400)))
    }

    func testBlockedAskKeepsTheMomentPending() {
        ReviewPromptTracker.recordPositiveMoment()
        XCTAssertTrue(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: true))
        XCTAssertTrue(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: true))
        ReviewPromptTracker.markShown()
        XCTAssertFalse(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: true))
    }
}

/// The clear-screen check behind the rating ask: the Undo / Add Details bar
/// from the log that just finished holds the ask the same way a sheet does.
@MainActor
final class ReviewPromptHomeGuardTests: XCTestCase {
    private let coordinator = ReviewPromptCoordinator.shared
    private var saved: (Bool, Bool, Bool)!

    override func setUp() async throws {
        saved = (coordinator.isOnHomeTab, coordinator.homeSheetIsPresented, coordinator.undoBarIsVisible)
        coordinator.isOnHomeTab = true
        coordinator.homeSheetIsPresented = false
        coordinator.undoBarIsVisible = false
    }

    override func tearDown() async throws {
        coordinator.isOnHomeTab = saved.0
        coordinator.homeSheetIsPresented = saved.1
        coordinator.undoBarIsVisible = saved.2
    }

    func testHomeWithNothingOverItIsClear() {
        XCTAssertTrue(coordinator.homeIsUncovered)
    }

    func testUndoBarHoldsTheAsk() {
        coordinator.undoBarIsVisible = true
        XCTAssertFalse(coordinator.homeIsUncovered)
        coordinator.undoBarIsVisible = false
        XCTAssertTrue(coordinator.homeIsUncovered)
    }

    func testSheetAndOtherTabsStillHoldTheAsk() {
        coordinator.homeSheetIsPresented = true
        XCTAssertFalse(coordinator.homeIsUncovered)
        coordinator.homeSheetIsPresented = false
        coordinator.isOnHomeTab = false
        XCTAssertFalse(coordinator.homeIsUncovered)
    }

    func testUndoBarOutlastsTheNotesSheet() {
        coordinator.undoBarIsVisible = true
        coordinator.homeSheetIsPresented = true
        coordinator.homeSheetIsPresented = false
        XCTAssertFalse(coordinator.homeIsUncovered)
    }
}
