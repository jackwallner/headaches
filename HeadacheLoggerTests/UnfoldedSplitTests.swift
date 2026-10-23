import XCTest
@testable import OneTapHeadacheTracker

/// The unfolded iPhone Duo split: One Tap left of the fold, History right of it.
final class UnfoldedSplitTests: XCTestCase {
    func testCompactWidthKeepsOneColumn() {
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil))
        // The folded outer display and the unfolded Duo held in portrait.
        XCTAssertNil(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 455...496))
    }

    func testRegularWidthTooNarrowForTwoPanesKeepsOneColumn() {
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
        XCTAssertNil(UnfoldedSplit.make(width: 719, isRegularWidth: true, fold: nil))
    }

    func testPanesSitAtTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 455...496)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 455, secondaryX: 496, secondaryWidth: 455))
    }

    func testZeroWidthFoldStillMeetsBothPanes() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 475.5...475.5)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475.5, secondaryX: 475.5, secondaryWidth: 475.5))
    }

    func testNoFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testFoldThatLeavesANarrowPaneFallsBackToEvenSplit() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 300...320)
        XCTAssertEqual(split?.primaryWidth, 475)
        XCTAssertEqual(split?.secondaryX, 475)
    }

    func testPanesNeverOverlapOrLeaveTheContainer() {
        for width in stride(from: CGFloat(720), through: 1366, by: 37) {
            let fold = (width / 2 - 20)...(width / 2 + 20)
            for candidate in [fold, nil] {
                guard let split = UnfoldedSplit.make(width: width, isRegularWidth: true, fold: candidate) else {
                    return XCTFail("no split at \(width)")
                }
                XCTAssertGreaterThanOrEqual(split.primaryWidth, UnfoldedSplit.minimumPaneWidth)
                XCTAssertGreaterThanOrEqual(split.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
                XCTAssertLessThanOrEqual(split.primaryWidth, split.secondaryX)
                XCTAssertEqual(split.secondaryX + split.secondaryWidth, width, accuracy: 0.001)
            }
        }
    }

    // MARK: - Tab bar clearance

    func testFoldedKeepsNoClearance() {
        XCTAssertEqual(TabBarClearance.make(isSplit: false, barInset: 83),
                       TabBarClearance(fade: 0, hidden: 0, contentPadding: 0))
    }

    func testSplitHidesEverythingUnderTheBar() {
        let clearance = TabBarClearance.make(isSplit: true, barInset: 83)
        // Content is gone a gap above the bar's top edge and fades out above that.
        XCTAssertEqual(clearance.hidden, 83 + TabBarClearance.gap)
        XCTAssertGreaterThan(clearance.fade, 0)
        // The last row can scroll fully above the fade, so it is never cut.
        XCTAssertGreaterThanOrEqual(clearance.contentPadding, clearance.fade + TabBarClearance.gap)
    }

    func testNegativeInsetNeverUncoversTheBar() {
        XCTAssertEqual(TabBarClearance.make(isSplit: true, barInset: -4).hidden, TabBarClearance.gap)
    }
}
