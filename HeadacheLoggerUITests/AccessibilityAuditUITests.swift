import XCTest

/// Runtime evidence for the accessibility persona audit (larger text, imperfect
/// vision, limited one-handed reach). Every flow keeps going after a failed
/// expectation and attaches screenshots plus plain-text `measure:` and
/// `audit:` attachments so the report can quote what actually happened.
/// Reduce Motion cannot be switched on from XCUITest; motion is judged from
/// source. Frame rate is not measured here.
final class AccessibilityAuditUITests: XCTestCase {

    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let ax3 = "UICTContentSizeCategoryAccessibilityXL"

    private var app: XCUIApplication!
    private var step = 0

    override func setUp() {
        continueAfterFailure = true
        step = 0
    }

    private func launch(pro: Bool, size: String? = nil, seeded: Bool = true, extra: [String] = []) {
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.headachelogger")
        if seeded {
            app.launchArguments += ["-uitesting", "-HeadacheScreenshotSeed"]
        }
        if pro { app.launchArguments += ["-HeadacheProOverride"] }
        if let size {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launchArguments += extra
        app.launch()
    }

    private func launchHome(pro: Bool, size: String? = nil) {
        launch(pro: pro, size: size)
        XCTAssertTrue(app.buttons["logHeadacheButton"].waitForExistence(timeout: 30), "Home never showed the log button")
        sleep(2)
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
        attachment.name = "measure: \(text.prefix(70))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Runs the system accessibility audit and records every issue as text
    /// without failing the test, so one finding never hides the rest.
    private func audit(_ screen: String) {
        var lines: [String] = []
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id=\($0.identifier) frame=\($0.frame)" } ?? "no element"
                lines.append("\(issue.auditType) | \(issue.compactDescription) | \(issue.detailedDescription) | \(element)")
                return true
            }
        } catch {
            lines.append("audit threw: \(error)")
        }
        let body = "screen=\(screen) issues=\(lines.count)\n" + lines.joined(separator: "\n")
        let attachment = XCTAttachment(string: body)
        attachment.name = "audit: \(screen) (\(lines.count) issues)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Records an element's size against the 44 x 44 pt minimum.
    private func target(_ element: XCUIElement, _ name: String) {
        guard element.exists else {
            note("target \(name): not found")
            return
        }
        let f = element.frame
        let screen = app.windows.firstMatch.frame
        let ok = f.width >= 44 && f.height >= 44
        let reach = screen.height > 0 ? String(format: "%.0f%%", (f.midY / screen.height) * 100) : "?"
        note("target \(name): \(Int(f.width))x\(Int(f.height)) pt at y=\(Int(f.minY))..\(Int(f.maxY)) (centre \(reach) down the screen) meets44=\(ok) hittable=\(element.isHittable)")
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

    /// Scrolls until `element` is hittable and returns how many swipes it took.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, max: Int = 12) -> Int {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < max {
            app.swipeUp()
            swipes += 1
        }
        return swipes
    }

    // MARK: 1. System audit at the default text size

    func testAuditDefaultSizeEveryTab() {
        launchHome(pro: false)
        shot("home-default")
        audit("home default size")
        tab("History")
        sleep(1)
        shot("history-default")
        audit("history default size")
        tab("Patterns")
        sleep(2)
        shot("patterns-locked-default")
        audit("patterns locked default size")
        tab("Settings")
        shot("settings-default")
        audit("settings default size")
    }

    // MARK: 2. Touch targets and one-handed reach (default size)

    func testTouchTargetsAndReach() {
        launchHome(pro: false)
        let screen = app.windows.firstMatch.frame
        note("screen \(Int(screen.width))x\(Int(screen.height)) pt")
        target(app.buttons["logHeadacheButton"], "Log Headache")
        for name in ["One Tap Headache Tracker", "History", "Patterns", "Settings"] {
            target(app.tabBars.buttons[name], "tab \(name)")
        }
        let nav = app.navigationBars.firstMatch
        note("home nav bar frame=\(nav.frame)")

        // Free tier with 11 seeded logs: the milestone card is up.
        target(app.buttons["Show me"], "milestone 'Show me'")
        target(app.buttons["Not now"], "milestone 'Not now'")
        shot("home-free-milestone")

        let dismissLine = app.buttons.matching(identifier: "Dismiss").firstMatch
        target(dismissLine, "Dismiss (status line / snackbar)")
        target(app.staticTexts["See all in History"], "'See all in History'")

        tab("History")
        let pencil = app.buttons["historyEntryNotesButton"].firstMatch
        scrollTo(pencil, max: 6)
        target(pencil, "History row edit pencil")
        shot("history-pencil-visible")
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        sleep(1)
        target(app.buttons["Import or Export"], "History toolbar Import/Export")
        let year = app.buttons["All Years"].firstMatch
        target(year, "History year filter")
        shot("history-toolbar-top")

        tab("Patterns")
        sleep(2)
        target(app.buttons["See Pro plans"], "Patterns 'See Pro plans'")
        shot("patterns-locked")

        tab("Settings")
        let toggle = app.switches["Prompt for severity and notes"]
        target(toggle, "Settings 'Prompt for severity' switch")
        target(app.buttons["Restore Purchases"].firstMatch, "Settings 'Restore Purchases'")
        shot("settings")
    }

    // MARK: 3. Home at the largest text sizes: log, snackbar, details sheet

    func testHomeLargestText() {
        launchHome(pro: true, size: Self.ax5)
        shot("ax5-home-top")
        let log = app.buttons["logHeadacheButton"]
        note("AX5 log button frame=\(log.frame) hittable=\(log.isHittable)")
        audit("home AX5")
        app.swipeUp()
        sleep(1)
        shot("ax5-home-scrolled")
        app.swipeDown()
        sleep(1)

        log.tap()
        usleep(400_000)
        shot("ax5-log-plus-0.4s")
        allowLocationIfShown()
        let undo = app.buttons["undoLastTapButton"]
        let appeared = undo.waitForExistence(timeout: 40)
        note("AX5 undo snackbar appeared=\(appeared)")
        sleep(1)
        shot("ax5-snackbar")
        if undo.exists {
            note("AX5 snackbar Undo frame=\(undo.frame) hittable=\(undo.isHittable)")
        }
        let add = app.buttons["addDetailsButton"]
        if add.exists {
            note("AX5 snackbar Add Details frame=\(add.frame) hittable=\(add.isHittable)")
        }
        let bar = app.otherElements["undoSnackbar"]
        note("AX5 snackbar container frame=\(bar.frame) screenHeight=\(Int(app.windows.firstMatch.frame.height))")
        audit("home AX5 with snackbar")

        if add.exists {
            add.tap()
            sleep(1)
            shot("ax5-details-sheet")
            audit("details sheet AX5")
            let notes = app.textViews.firstMatch
            if notes.waitForExistence(timeout: 3) {
                note("AX5 details notes frame=\(notes.frame) hittable=\(notes.isHittable)")
                notes.tap()
                notes.typeText("Blurry left eye, light hurts")
                sleep(1)
                shot("ax5-details-keyboard")
                note("AX5 details Save hittable with keyboard=\(app.buttons["Save"].isHittable) frame=\(app.buttons["Save"].frame)")
            }
            let seg = app.segmentedControls.firstMatch
            note("AX5 severity segmented frame=\(seg.frame) hittable=\(seg.isHittable)")
            if app.buttons["Save"].exists { app.buttons["Save"].tap() }
            sleep(1)
            shot("ax5-home-after-save")
        }
    }

    // MARK: 4. Other screens at the largest text sizes

    func testHistoryPatternsSettingsLargestText() {
        launchHome(pro: true, size: Self.ax5)
        tab("History")
        sleep(1)
        shot("ax5-history-top")
        audit("history AX5")
        let pencil = app.buttons["historyEntryNotesButton"].firstMatch
        let swipes = scrollTo(pencil, max: 10)
        note("AX5 history swipes to reach first edit pencil=\(swipes)")
        shot("ax5-history-first-entry")
        target(pencil, "AX5 history pencil")
        if pencil.exists, pencil.isHittable {
            pencil.tap()
            if app.navigationBars["Edit Event"].waitForExistence(timeout: 5) {
                sleep(1)
                shot("ax5-edit-sheet")
                audit("edit sheet AX5")
                app.swipeUp()
                shot("ax5-edit-sheet-scrolled")
                note("AX5 edit sheet Save hittable=\(app.buttons["Save"].isHittable) Cancel hittable=\(app.buttons["Cancel"].isHittable)")
                app.buttons["Cancel"].tap()
                sleep(1)
            }
        }
        for _ in 0..<12 { app.swipeUp() }
        sleep(1)
        shot("ax5-history-bottom")

        tab("Patterns")
        sleep(3)
        shot("ax5-patterns-top")
        audit("patterns AX5")
        app.swipeUp()
        sleep(1)
        shot("ax5-patterns-scrolled")
        let link = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Evening' OR label CONTAINS[c] 'Sleep' OR label CONTAINS[c] 'pressure'")).firstMatch
        if link.exists {
            link.tap()
            sleep(2)
            shot("ax5-pattern-detail")
            audit("pattern detail AX5")
            app.swipeUp()
            sleep(1)
            shot("ax5-pattern-detail-scrolled")
        }

        tab("Settings")
        shot("ax5-settings-top")
        audit("settings AX5")
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        shot("ax5-settings-bottom")
    }

    // MARK: 5. Paywall and free tier at the largest text sizes

    func testPaywallLargestText() {
        launchHome(pro: false, size: Self.ax5)
        shot("ax5-home-free")
        tab("Patterns")
        sleep(2)
        shot("ax5-patterns-locked")
        let plans = app.buttons["See Pro plans"]
        if plans.waitForExistence(timeout: 3) {
            scrollTo(plans, max: 6)
            shot("ax5-patterns-see-plans")
            if plans.isHittable { plans.tap() }
            sleep(4)
            shot("ax5-paywall-top")
            audit("paywall AX5")
            let restore = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Restore'")).firstMatch
            let swipes = scrollTo(restore, max: 10)
            note("AX5 paywall swipes to reach Restore=\(swipes) exists=\(restore.exists) hittable=\(restore.isHittable)")
            target(restore, "AX5 paywall Restore")
            shot("ax5-paywall-restore")
            for _ in 0..<6 { app.swipeUp() }
            shot("ax5-paywall-bottom")
            note("AX5 paywall close control exists=\(app.buttons["Close"].exists || app.buttons["xmark"].exists)")
        }
    }

    // MARK: 6. Paywall at a mid accessibility size (AX3) plus audit

    func testPaywallDefaultSizeAudit() {
        launchHome(pro: false)
        tab("Patterns")
        sleep(2)
        let plans = app.buttons["See Pro plans"]
        if plans.waitForExistence(timeout: 3) {
            plans.tap()
            sleep(4)
            shot("paywall-default")
            audit("paywall default size")
            for name in ["Restore Purchases", "Close"] {
                target(app.buttons[name].firstMatch, "paywall \(name)")
            }
            for link in ["Terms", "Privacy Policy"] {
                target(app.links[link].firstMatch.exists ? app.links[link].firstMatch : app.buttons[link].firstMatch, "paywall link \(link)")
            }
        }
    }

    // MARK: 7. First run at the largest text size

    func testOnboardingLargestText() {
        launch(pro: false, size: Self.ax5, seeded: false)
        sleep(6)
        shot("ax5-onboarding-welcome")
        audit("onboarding welcome AX5")
        let start = app.buttons["Get Started"]
        note("AX5 onboarding 'Get Started' exists=\(start.exists) hittable=\(start.isHittable) frame=\(start.frame)")
        if start.exists, start.isHittable {
            start.tap()
            sleep(2)
            shot("ax5-onboarding-health")
            audit("onboarding health AX5")
            let buttons = app.buttons.allElementsBoundByIndex.map { "\($0.label)@\(Int($0.frame.minY))" }
            note("AX5 onboarding health buttons=\(buttons)")
        }
    }

    // MARK: 8. First run at the default size, touch targets and audit

    func testOnboardingDefaultSize() {
        launch(pro: false, seeded: false)
        sleep(6)
        shot("onboarding-welcome")
        audit("onboarding welcome default")
        target(app.buttons["Get Started"], "onboarding Get Started")
    }

    // MARK: 9. Element labels a VoiceOver user hears

    func testVoiceOverLabels() {
        launchHome(pro: true)
        func dump(_ screen: String) {
            var lines: [String] = []
            let all = app.descendants(matching: .any).allElementsBoundByIndex
            for el in all.prefix(120) {
                let label = el.label
                let value = (el.value as? String) ?? ""
                if label.isEmpty && value.isEmpty && el.identifier.isEmpty { continue }
                lines.append("\(el.elementType.rawValue) label='\(label)' value='\(value)' id=\(el.identifier) traitsEnabled=\(el.isEnabled)")
            }
            let a = XCTAttachment(string: "screen=\(screen)\n" + lines.joined(separator: "\n"))
            a.name = "voiceover-tree: \(screen)"
            a.lifetime = .keepAlways
            add(a)
        }
        dump("home")
        tab("History")
        dump("history")
        let rows = app.descendants(matching: .any).matching(identifier: "historyEventRow")
        note("history rows as VoiceOver elements=\(rows.count)")
        tab("Patterns")
        sleep(3)
        dump("patterns")
        let link = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Evening' OR label CONTAINS[c] 'Sleep' OR label CONTAINS[c] 'pressure'")).firstMatch
        if link.exists {
            link.tap()
            sleep(2)
            dump("pattern detail (bar chart)")
        }
    }
}
