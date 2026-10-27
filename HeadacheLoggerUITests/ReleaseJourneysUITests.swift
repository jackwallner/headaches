import XCTest

@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    private let bundleID = "com.jackwallner.headachelogger"
    private let note = "Core loop note"

    override func setUp() {
        continueAfterFailure = false
    }

    /// The loop a customer opens the app for: one tap logs a headache, it shows
    /// in History, gets a severity and a note, and all of it survives a relaunch.
    func testCoreLoopLogHeadacheListsItAndKeepsItAfterRelaunch() {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        QA.launch(app, arguments: ["-uitesting"])

        XCTAssertTrue(app.buttons["logHeadacheButton"].waitForExistence(timeout: 20), "Log button missing on Home")
        QA.checkpoint(app, "home-fresh")

        openTab(app, "History")
        XCTAssertTrue(app.otherElements["historyEmptyState"].firstMatch.waitForExistence(timeout: 10)
                      || app.staticTexts["No Headaches Logged Yet"].exists, "Fresh install should have an empty history")
        XCTAssertEqual(entryRows(app).count, 0, "Fresh install should list no entries")
        QA.checkpoint(app, "history-empty")

        openTab(app, "One Tap Headache Tracker")
        app.buttons["logHeadacheButton"].tap()
        XCTAssertTrue(app.staticTexts["Latest Event"].firstMatch.waitForExistence(timeout: 20), "Latest event card never appeared after logging")
        QA.checkpoint(app, "home-logged")

        openTab(app, "History")
        XCTAssertTrue(entryRows(app).firstMatch.waitForExistence(timeout: 10), "Logged headache is not listed in History")
        XCTAssertEqual(entryRows(app).count, 1, "History should list exactly the one logged headache")
        QA.checkpoint(app, "history-one-entry")

        entryRows(app).firstMatch.tap()
        XCTAssertTrue(app.buttons["Medium"].waitForExistence(timeout: 10), "Edit sheet did not open")
        app.buttons["Medium"].tap()
        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText(note)
        QA.checkpoint(app, "edit-entry")
        app.buttons["Save"].tap()

        assertEntryDetails(app)
        QA.checkpoint(app, "history-entry-detailed")

        QA.relaunch(app)
        XCTAssertTrue(app.buttons["logHeadacheButton"].waitForExistence(timeout: 20), "Home missing after relaunch")
        XCTAssertTrue(app.staticTexts["Latest Event"].firstMatch.waitForExistence(timeout: 10), "Logged headache missing from Home after relaunch")
        QA.checkpoint(app, "home-after-relaunch")

        openTab(app, "History")
        XCTAssertTrue(entryRows(app).firstMatch.waitForExistence(timeout: 10), "History empty after relaunch")
        XCTAssertEqual(entryRows(app).count, 1, "Entry count changed after relaunch")
        assertEntryDetails(app)
        QA.checkpoint(app, "history-after-relaunch")
    }

    // Tab bar on iPhone, sidebar on larger layouts: both expose a button by label.
    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(name) tab missing")
        tab.tap()
    }

    private func entryRows(_ app: XCUIApplication) -> XCUIElementQuery {
        // One note button per row; the row container's identifier is stamped onto its children.
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Add note", "Edit note"]))
    }

    private func assertEntryDetails(_ app: XCUIApplication) {
        let preview = app.staticTexts[note].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Saved note is not shown in History")
        XCTAssertTrue(app.staticTexts["Medium"].firstMatch.exists, "Saved severity is not shown in History")
    }
}
