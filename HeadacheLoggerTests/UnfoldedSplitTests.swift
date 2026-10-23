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

    func testFoldedHidesNothing() {
        XCTAssertNil(TabBarClearance.edge(isSplit: false, safeBottom: 592, rows: [560...600]))
    }

    func testEdgeSitsAGapAboveTheBar() {
        XCTAssertEqual(TabBarClearance.edge(isSplit: true, safeBottom: 592, rows: []), 592 - TabBarClearance.gap)
    }

    func testRowCrossingTheEdgeIsHiddenWhole() {
        // A pattern row from 520 would be sliced at 570: it is hidden, and the
        // edge sits halfway back to the row above, over the separator's gap.
        let edge = TabBarClearance.edge(isSplit: true, safeBottom: 586, rows: [440...496, 520...596])
        XCTAssertEqual(edge, 507)
    }

    func testFirstRowCrossingTheEdgeHidesFromItsTop() {
        XCTAssertEqual(TabBarClearance.edge(isSplit: true, safeBottom: 586, rows: [548...648]), 548)
    }

    func testTightGapNeverCutsTheRowAbove() {
        let edge = TabBarClearance.edge(isSplit: true, safeBottom: 586, rows: [500...519.5, 520...600])
        XCTAssertEqual(edge, 519.5)
    }

    func testRowsClearOfTheEdgeLeaveIt() {
        let line = 592 - TabBarClearance.gap
        // One row ends exactly on the line, one starts there: neither is sliced.
        let edge = TabBarClearance.edge(isSplit: true, safeBottom: 592, rows: [500...line, line...(line + 80)])
        XCTAssertEqual(edge, line)
    }

    func testEdgeInAGapSitsHalfwayBetweenTheRows() {
        // A card ends at 549 and the next block starts at 573, under the 569 line.
        let edge = TabBarClearance.edge(isSplit: true, safeBottom: 585, rows: [400...549, 573...640])
        XCTAssertEqual(edge, 560)
    }

    func testNestedRowsHideTheirOuterBlock() {
        let edge = TabBarClearance.edge(isSplit: true, safeBottom: 592, rows: [520...640, 560...600])
        XCTAssertEqual(edge, 520)
    }

    func testTallRowIsCutAtTheLineInsteadOfEmptyingTheScreen() {
        let line = 592 - TabBarClearance.gap
        let tallTop = line - TabBarClearance.maximumSnap - 1
        XCTAssertEqual(TabBarClearance.edge(isSplit: true, safeBottom: 592, rows: [tallTop...700]), line)
    }

    func testLastRowCanScrollClearOfTheEdge() {
        XCTAssertGreaterThan(TabBarClearance.contentPadding, TabBarClearance.gap)
    }
}
