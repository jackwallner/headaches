import XCTest

/// Runtime evidence for the experienced-user persona audit. Every flow keeps
/// going after a failed expectation and attaches screenshots plus a plain-text
/// `measure:` attachment, so the report can quote what actually happened.
/// Frame rate is not measured here.
final class ExperiencedUserAuditUITests: XCTestCase {

    private var app: XCUIApplication!
    private var step = 0

    override func setUp() {
        continueAfterFailure = true
        step = 0
    }

    private func launch(pro: Bool, extra: [String] = []) {
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.headachelogger")
        app.launchArguments += ["-uitesting", "-HeadacheScreenshotSeed"]
        if pro { app.launchArguments += ["-HeadacheProOverride"] }
        app.launchArguments += extra
        app.launch()
        XCTAssertTrue(app.buttons["logHeadacheButton"].waitForExistence(timeout: 30), "Home never showed the log button")
    }

    private func shot(_ name: String) {
        step += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%02d-%@", step, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "measure: \(text.prefix(60))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tab(_ title: String) {
        let bar = app.tabBars.buttons[title]
        if bar.waitForExistence(timeout: 5) { bar.tap() } else { app.buttons[title].firstMatch.tap() }
        sleep(1)
    }

    // MARK: Home: repeat logging

    func testHomeRepeatLogging() {
        launch(pro: true)
        sleep(2)
        shot("home-seeded")

        // "See all in History" reads like a link. Does tapping it do anything?
        let seeAll = app.staticTexts["See all in History"]
        note("seeAllInHistory exists=\(seeAll.exists) hittable=\(seeAll.exists && seeAll.isHittable)")
        if seeAll.exists {
            seeAll.tap()
            sleep(1)
            note("after tapping 'See all in History': historyView exists=\(app.otherElements["historyView"].exists || app.collectionViews["historyView"].exists)")
            shot("after-tap-see-all-in-history")
        }

        let log = app.buttons["logHeadacheButton"]
        note("log button frame=\(log.frame)")
        let start = Date()
        log.tap()
        usleep(300_000)
        shot("log-plus-0.3s")
        note("log button enabled 0.3s after tap=\(log.isEnabled)")

        let undo = app.buttons["undoLastTapButton"]
        let appeared = undo.waitForExistence(timeout: 40)
        let elapsed = Date().timeIntervalSince(start)
        note("undo snackbar appeared=\(appeared) after \(String(format: "%.1f", elapsed))s")
        shot("undo-snackbar-visible")

        // Second tap straight after the first log: how long is the button blocked?
        note("log button enabled with snackbar up=\(log.isEnabled)")
        usleep(1_500_000)
        note("log button enabled 1.5s later=\(log.isEnabled)")
        shot("log-button-state-after-1.5s")
        let blockedStart = Date()
        var freed = false
        while Date().timeIntervalSince(blockedStart) < 8 {
            if log.isEnabled { freed = true; break }
            usleep(250_000)
        }
        note("log button re-enabled=\(freed) after another \(String(format: "%.1f", Date().timeIntervalSince(blockedStart)))s")

        // Add details: sheet, keyboard.
        let add = app.buttons["addDetailsButton"]
        if add.exists {
            add.tap()
            sleep(1)
            shot("details-sheet")
            let notes = app.textViews.firstMatch
            if notes.waitForExistence(timeout: 3) {
                note("notes field frame=\(notes.frame) hittable=\(notes.isHittable)")
                notes.tap()
                notes.typeText("Aura before onset, left eye")
                sleep(1)
                shot("details-sheet-keyboard")
                note("Save hittable with keyboard up=\(app.buttons["Save"].isHittable)")
            }
            let seg = app.segmentedControls.firstMatch
            note("severity segmented control exists=\(seg.exists) hittable=\(seg.exists && seg.isHittable)")
            if app.buttons["Save"].exists { app.buttons["Save"].tap() }
            sleep(1)
            shot("home-after-save-details")
        } else {
            note("Add Details button not available (snackbar gone)")
        }

        // Snackbar lifetime.
        let wait = Date()
        while Date().timeIntervalSince(wait) < 20, app.buttons["undoLastTapButton"].exists { usleep(500_000) }
        note("undo snackbar still present after \(String(format: "%.1f", Date().timeIntervalSince(wait)))s of watching=\(app.buttons["undoLastTapButton"].exists)")
        shot("home-after-snackbar")
    }

    // MARK: History: finding, correcting and removing entries

    func testHistoryExperienced() {
        launch(pro: true)
        tab("History")
        sleep(1)
        shot("history-top")

        let rows = app.descendants(matching: .any).matching(identifier: "historyEventRow")
        var swipes = 0
        while !(rows.count > 0 && rows.firstMatch.isHittable), swipes < 8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        note("swipes of the list needed before the first entry row is hittable=\(swipes)")
        shot("history-first-entry-visible")

        let first = rows.firstMatch
        note("first row frame=\(first.frame)")

        let pencil = app.buttons["historyEntryNotesButton"].firstMatch
        if pencil.exists {
            note("edit pencil frame=\(pencil.frame) (44x44 is the minimum target)")
        }

        // Does tapping the entry body open it?
        if first.exists {
            let p = first.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            p.tap()
            sleep(1)
            note("tapping the row body opened edit sheet=\(app.otherElements["editEventSheet"].exists || app.navigationBars["Edit Event"].exists)")
            shot("after-tap-row-body")
        }

        // Edit sheet.
        if pencil.exists && pencil.isHittable { pencil.tap() }
        if app.navigationBars["Edit Event"].waitForExistence(timeout: 5) {
            sleep(1)
            shot("edit-sheet-top")
            let notes = app.textViews.firstMatch
            note("edit sheet: notes field exists=\(notes.exists) hittable without scrolling=\(notes.exists && notes.isHittable)")
            note("edit sheet: severity control hittable without scrolling=\(app.segmentedControls.firstMatch.isHittable)")
            app.swipeUp()
            sleep(1)
            shot("edit-sheet-scrolled")
            if notes.exists, notes.isHittable {
                notes.tap()
                sleep(1)
                shot("edit-sheet-keyboard")
            }
            // Can the user pick a time in the future?
            app.swipeDown()
            let next = app.buttons["Next Month"]
            if next.exists {
                next.tap()
                sleep(1)
                shot("edit-sheet-next-month-selectable")
                note("graphical picker lets you page to next month (future dates not limited)=true")
            }
            if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
            sleep(1)
        }

        // Swipe delete a recent entry: confirm? undo?
        let recent = rows.firstMatch
        if recent.exists, recent.isHittable {
            recent.swipeLeft()
            sleep(1)
            shot("history-swipe-actions")
            let delete = app.buttons["Delete"].firstMatch
            note("swipe action 'Delete' exists=\(delete.exists)")
            if delete.exists {
                delete.tap()
                sleep(1)
                shot("history-after-delete-of-recent-entry")
                note("confirmation dialog shown for recent entry=\(app.sheets.count > 0 || app.alerts.count > 0)")
                note("Undo affordance shown after delete=\(app.buttons["Undo"].exists)")
            }
        }

        // Bottom of the list: import and export.
        for _ in 0..<6 { app.swipeUp() }
        sleep(1)
        shot("history-bottom-import-export")

        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        sleep(1)
        let menu = app.buttons["Import or Export"]
        if menu.exists {
            menu.tap()
            sleep(1)
            shot("history-toolbar-menu")
            app.otherElements.firstMatch.tap()
        }
        let year = app.buttons["All Years"].firstMatch
        if year.exists {
            year.tap()
            sleep(1)
            shot("history-year-filter")
        }
    }

    // MARK: Patterns (Pro)

    func testPatternsPro() {
        launch(pro: true)
        tab("Patterns")
        sleep(3)
        shot("patterns-pro")
        let firstRow = app.cells.firstMatch
        let links = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Evening' OR label CONTAINS[c] 'Sleep' OR label CONTAINS[c] 'pressure'")).firstMatch
        if links.exists {
            links.tap()
            sleep(2)
            shot("pattern-detail")
            app.swipeUp()
            sleep(1)
            shot("pattern-detail-scrolled")
            note("pattern detail has any date-range or filter control=\(app.segmentedControls.count > 0)")
        } else if firstRow.exists {
            firstRow.tap()
            sleep(2)
            shot("pattern-detail-fallback")
        }
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        shot("patterns-pro-lower")
    }

    // MARK: Free tier and exits

    func testFreeTierGatesAndRestore() {
        launch(pro: false)
        sleep(2)
        shot("home-free")
        tab("History")
        shot("history-free")
        tab("Patterns")
        sleep(2)
        shot("patterns-free-locked")
        let plans = app.buttons["See Pro plans"]
        if plans.waitForExistence(timeout: 3) {
            plans.tap()
            sleep(4)
            shot("paywall-from-patterns")
            note("paywall Restore button exists=\(app.buttons["Restore Purchases"].exists) Restore label buttons=\(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Restore'")).count)")
            note("paywall close control exists=\(app.buttons["Close"].exists || app.buttons["xmark"].exists)")
            app.swipeDown(velocity: .fast)
            sleep(1)
        }
        tab("Settings")
        shot("settings-top")
        let restore = app.buttons["Restore Purchases"].firstMatch
        if restore.exists {
            restore.tap()
            sleep(3)
            shot("settings-restore-result")
            if app.alerts.buttons["OK"].exists { app.alerts.buttons["OK"].tap() }
        }
        app.swipeUp()
        sleep(1)
        shot("settings-bottom")
    }

    // MARK: Prompt for severity and notes

    func testPromptForSeverityPath() {
        launch(pro: true)
        tab("Settings")
        let toggle = app.switches["Prompt for severity and notes"]
        note("settings toggle exists=\(toggle.exists)")
        if toggle.exists { toggle.tap() }
        shot("settings-prompt-on")
        tab("One Tap Headache Tracker")
        sleep(1)
        let start = Date()
        app.buttons["logHeadacheButton"].tap()
        let sheet = app.navigationBars["Headache Details"]
        let shown = sheet.waitForExistence(timeout: 20)
        note("details sheet shown=\(shown) after \(String(format: "%.1f", Date().timeIntervalSince(start)))s from tap while context capture is still running")
        shot("details-sheet-prompted")
        let seg = app.segmentedControls.firstMatch
        if seg.exists {
            seg.buttons["Medium"].tap()
            shot("severity-medium-picked")
        }
        if app.buttons["Save"].exists { app.buttons["Save"].tap() }
        sleep(2)
        shot("home-after-prompted-save")
    }
}
