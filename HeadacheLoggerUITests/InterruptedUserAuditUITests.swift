import XCTest

/// Runtime evidence for the interrupted-user persona audit: someone logs a
/// headache, gets pulled away (backgrounds the app, the app is killed, a sheet
/// is swiped away) and comes back expecting their state to be intact. Every
/// flow keeps going after a failed expectation and attaches screenshots plus a
/// plain-text `measure:` attachment. Frame rate is not measured here.
final class InterruptedUserAuditUITests: XCTestCase {

    private var app: XCUIApplication!
    private var step = 0
    private let bundleID = "com.jackwallner.headachelogger"

    override func setUp() {
        continueAfterFailure = true
        step = 0
    }

    /// `seed` replaces the store with the demo history, so a relaunch that must
    /// keep the user's own data passes `seed: false`.
    private func launch(seed: Bool = true, pro: Bool = true, extra: [String] = []) {
        app = XCUIApplication(bundleIdentifier: bundleID)
        app.launchArguments += ["-uitesting"]
        if seed { app.launchArguments += ["-HeadacheScreenshotSeed"] }
        if pro { app.launchArguments += ["-HeadacheProOverride"] }
        app.launchArguments += extra
        app.launch()
        XCTAssertTrue(app.buttons["logHeadacheButton"].waitForExistence(timeout: 30), "Home never showed the log button")
    }

    private func relaunch() {
        app.terminate()
        launch(seed: false)
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

    @discardableResult
    private func allowLocationIfShown(timeout: TimeInterval = 8) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: timeout) {
            allow.tap()
            return true
        }
        return false
    }

    private func tab(_ title: String) {
        let bar = app.tabBars.buttons[title]
        if bar.waitForExistence(timeout: 5) { bar.tap() } else { app.buttons[title].firstMatch.tap() }
        sleep(1)
    }

    /// Home button, wait, then bring the app back, as someone answering the door would.
    private func awayAndBack(seconds: UInt32) {
        XCUIDevice.shared.press(.home)
        sleep(seconds)
        app.activate()
        sleep(2)
    }

    private func logOnce() {
        app.buttons["logHeadacheButton"].tap()
        allowLocationIfShown()
        _ = app.buttons["undoLastTapButton"].waitForExistence(timeout: 40)
    }

    // MARK: Draft survives a short interruption, not a kill

    func testDetailsDraftAcrossBackgroundAndKill() {
        launch()
        logOnce()
        shot("logged-snackbar")
        let add = app.buttons["addDetailsButton"]
        note("Add Details available right after log=\(add.exists)")
        guard add.exists else { return }
        add.tap()
        let notes = app.textViews.firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("Pounding behind left eye, took ibuprofen at 3")
        app.segmentedControls.firstMatch.buttons["Medium"].tap()
        shot("details-typed")

        awayAndBack(seconds: 20)
        shot("details-after-20s-away")
        let notesAfter = app.textViews.firstMatch
        note("after 20s in background: details sheet still open=\(app.navigationBars["Headache Details"].exists) notes value='\(notesAfter.exists ? (notesAfter.value as? String ?? "") : "<none>")'")

        // Killed (or evicted by iOS) while the draft is only in memory.
        relaunch()
        sleep(2)
        shot("home-after-kill-relaunch")
        note("after kill+relaunch: details sheet open=\(app.navigationBars["Headache Details"].exists) undo snackbar=\(app.buttons["undoLastTapButton"].exists) add details=\(app.buttons["addDetailsButton"].exists)")
        let latest = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'ibuprofen'"))
        note("typed note text visible on Home after relaunch=\(latest.count > 0)")
        tab("History")
        shot("history-after-kill-relaunch")
        note("typed note text visible in History after relaunch=\(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'ibuprofen'")).count > 0)")
    }

    // MARK: Snackbar is the only door to severity/notes

    func testSnackbarGoneAfterAway() {
        launch()
        logOnce()
        shot("logged-snackbar")
        note("snackbar visible before leaving=\(app.buttons["undoLastTapButton"].exists)")
        let start = Date()
        awayAndBack(seconds: 20)
        note("snackbar visible \(String(format: "%.0f", Date().timeIntervalSince(start)))s later=\(app.buttons["undoLastTapButton"].exists) addDetails=\(app.buttons["addDetailsButton"].exists)")
        shot("home-after-20s-away")

        // What does Home offer for the log just made, now that the snackbar is gone?
        let disclosure = app.otherElements["latestEventDetailsDisclosure"]
        note("latest-event details disclosure exists=\(disclosure.exists || app.buttons["latestEventDetailsDisclosure"].exists)")
        let anyEdit = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Edit' OR label CONTAINS[c] 'notes' OR label CONTAINS[c] 'severity'"))
        note("Home buttons mentioning edit/notes/severity=\(anyEdit.count): \((0..<anyEdit.count).map { anyEdit.element(boundBy: $0).label })")
        app.swipeUp()
        sleep(1)
        shot("home-scrolled-after-away")
    }

    // MARK: Swipe-dismiss of a half-written note

    func testEditSheetSwipeDismissDiscards() {
        launch()
        tab("History")
        let pencil = app.buttons["historyEntryNotesButton"].firstMatch
        var swipes = 0
        while !(pencil.exists && pencil.isHittable), swipes < 8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        guard pencil.exists else { note("no edit pencil reachable"); return }
        pencil.tap()
        guard app.navigationBars["Edit Event"].waitForExistence(timeout: 5) else { return }
        let notes = app.textViews.firstMatch
        app.swipeUp()
        sleep(1)
        if notes.isHittable {
            notes.tap()
            notes.typeText(" Woke with it, curtains open.")
        }
        shot("edit-typed")
        if app.keyboards.count > 0 { app.navigationBars["Edit Event"].tap() }
        // A stray downward swipe, the way a tired thumb dismisses a sheet.
        app.navigationBars["Edit Event"].swipeDown(velocity: .fast)
        sleep(1)
        shot("after-swipe-down")
        note("edit sheet closed by swipe with unsaved text, no confirmation=\(!app.navigationBars["Edit Event"].exists && app.alerts.count == 0 && app.sheets.count == 0)")
        pencil.tap()
        sleep(1)
        if app.navigationBars["Edit Event"].waitForExistence(timeout: 5) {
            app.swipeUp()
            let value = app.textViews.firstMatch.value as? String ?? ""
            note("reopened edit sheet notes='\(value)' (contains typed text=\(value.contains("curtains open")))")
            shot("edit-reopened")
        }
    }

    // MARK: Position after a relaunch

    func testTabAndScrollAfterRelaunch() {
        launch()
        tab("History")
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        shot("history-scrolled")
        relaunch()
        sleep(1)
        shot("after-relaunch")
        note("after relaunch History tab selected=\(app.tabBars.buttons["History"].isSelected) Home log button visible=\(app.buttons["logHeadacheButton"].isHittable)")
        tab("Settings")
        relaunch()
        note("after relaunch from Settings: Home first=\(app.buttons["logHeadacheButton"].isHittable)")
    }

    // MARK: Quiz abandoned halfway

    func testQuizAbandonedHalfway() {
        launch()
        tab("History")
        let quizEntry = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'quiz' OR label CONTAINS[c] 'questions'")).firstMatch
        var swipes = 0
        while !(quizEntry.exists && quizEntry.isHittable), swipes < 10 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        note("quiz entry found=\(quizEntry.exists) label='\(quizEntry.exists ? quizEntry.label : "")' after \(swipes) swipes")
        shot("history-quiz-entry")
        guard quizEntry.exists else { return }
        quizEntry.tap()
        sleep(1)
        shot("quiz-q1")
        for index in 0..<3 {
            let options = app.buttons.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.height > 40 && $0.label != "Next" && $0.label != "Close" && !$0.label.hasPrefix("Skip") }
            options.first?.tap()
            if app.buttons["Next"].exists { app.buttons["Next"].tap() }
            sleep(1)
            if index == 1 { shot("quiz-q3") }
        }
        shot("quiz-q4-before-leaving")
        app.buttons["Close"].tap()
        sleep(1)
        quizEntry.tap()
        sleep(1)
        note("reopened quiz step label after Close='\(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Step'")).firstMatch.label)'")
        shot("quiz-reopened")
        relaunch()
        tab("History")
        app.swipeUp()
        sleep(1)
        shot("history-after-relaunch-quiz-state")
    }

    // MARK: Killed right after tapping Log

    func testKilledRightAfterLogTap() {
        launch(seed: false)
        let before = app.descendants(matching: .any).matching(identifier: "historyEventRow").count
        app.buttons["logHeadacheButton"].tap()
        usleep(400_000)
        shot("tap-plus-0.4s")
        app.terminate()
        launch(seed: false)
        sleep(3)
        allowLocationIfShown(timeout: 4)
        shot("home-after-kill-relaunch")
        note("log survives kill 0.4s after tap: undo snackbar=\(app.buttons["undoLastTapButton"].exists) banner texts=\(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'context' OR label CONTAINS[c] 'pending' OR label CONTAINS[c] 'Saved'")).allElementsBoundByIndex.map(\.label))")
        tab("History")
        shot("history-after-kill")
        note("History rows before=\(before) after=\(app.descendants(matching: .any).matching(identifier: "historyEventRow").count)")
    }

    // MARK: Onboarding abandoned halfway (fresh state only)

    func testOnboardingAbandonedHalfway() {
        app = XCUIApplication(bundleIdentifier: bundleID)
        app.launch()
        let start = app.buttons["Get Started"]
        guard start.waitForExistence(timeout: 20) else {
            note("onboarding not shown (already completed in this simulator), skipping")
            shot("not-onboarding")
            return
        }
        shot("onboarding-welcome")
        start.tap()
        sleep(1)
        shot("onboarding-health")
        note("onboarding step 2 title present=\(app.staticTexts["Apple Health"].exists) back control=\(app.buttons["Back"].exists)")
        app.terminate()
        app.launch()
        sleep(3)
        shot("onboarding-after-kill")
        note("after kill on step 2: welcome shown again=\(app.buttons["Get Started"].exists) health step shown=\(app.staticTexts["Apple Health"].exists)")
    }
}
