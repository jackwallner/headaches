import XCTest

/// The release gate's journeys (`qa-gate run`): the first onboarding pages, a
/// one-tap log on seeded data, History and Patterns, the Pro paywall shown and
/// closed, and a return visit with an interruption, plus the core loop (a log
/// is counted and survives a relaunch). Each step ends in `QA.checkpoint`,
/// which runs the fleet oracles on the screen. The other journeys assert
/// reachability only.
///
/// Onboarding stops before the Apple Health page's button: it raises the
/// HealthKit and location prompts, which belong to the system, not the app.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {

    private static let bundle = "com.jackwallner.headachelogger"
    private static let seededPro = ["-uitesting", "-HeadacheScreenshotSeed", "-HeadacheProOverride"]

    func test01FirstRunOnboarding() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app)
        let start = app.buttons["Get Started"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "welcome never rendered")
        QA.checkpoint(app, "welcome")

        start.tap()
        XCTAssertTrue(app.staticTexts["Apple Health"].waitForExistence(timeout: 15), "Health page never rendered")
        QA.checkpoint(app, "health-intro")
    }

    func test02LogHistoryAndPatterns() {
        continueAfterFailure = false
        let app = launch(Self.seededPro)
        QA.checkpoint(app, "home")

        app.buttons["logHeadacheButton"].tap()
        answerLocationPrompt()
        XCTAssertTrue(app.descendants(matching: .any)["latestEventCard"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "logged")

        openHistory(in: app)
        QA.checkpoint(app, "history")

        tapTab("Patterns", symbol: Self.patternsSymbol, in: app)
        QA.checkpoint(app, "patterns")
    }

    func test03ProPaywallShownAndClosed() {
        continueAfterFailure = false
        let app = launch(["-uitesting", "-HeadacheScreenshotSeed"])
        tapTab("Settings", symbol: Self.settingsSymbol, in: app)
        let pro = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", L("Proactive Alerts"))).firstMatch
        XCTAssertTrue(pro.waitForExistence(timeout: 15), "Pro row missing for a free user")
        QA.checkpoint(app, "settings")

        pro.tap()
        XCTAssertTrue(app.staticTexts[L("Know before the headache hits")].waitForExistence(timeout: 20), "paywall never rendered")
        QA.checkpoint(app, "pro-paywall", paywall: true)

        // At large text sizes the Close button can sit above the scrolled
        // content; swiping down scrolls back to it, then dismisses the sheet.
        let close = app.buttons[L("Close")]
        _ = close.waitForExistence(timeout: 5)
        let title = app.staticTexts[L("Know before the headache hits")]
        for _ in 0..<3 where title.exists {
            if close.exists && close.isHittable {
                close.tap()
                break
            }
            QA.swipe(app, .down)
        }
        XCTAssertTrue(pro.waitForExistence(timeout: 15), "paywall never closed")
        QA.checkpoint(app, "settings-after-paywall", paywall: false)
    }

    func test04ReturnVisitWithInterruption() {
        continueAfterFailure = false
        let app = launch(Self.seededPro)
        openHistory(in: app)
        QA.checkpoint(app, "history-before-interruption")

        QA.interrupt(app)
        QA.checkpoint(app, "history-after-interruption")

        QA.relaunch(app)
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "home-after-relaunch")
    }

    /// The core loop: one tap logs a headache, History counts it, and the count
    /// is the same after a relaunch. The seed rewrites the log on every launch,
    /// so the relaunch drops it and reads what the first run saved.
    func testCoreLoopOneTapLogIsCountedAndSurvivesRelaunch() {
        continueAfterFailure = false
        let app = launch(Self.seededPro)
        QA.checkpoint(app, "core-home")
        openHistory(in: app)
        let seeded = totalLogs(in: app)
        XCTAssertGreaterThan(seeded, 0, "the seeded log is empty")
        QA.checkpoint(app, "core-history-before-log")

        tapTab("One Tap Headache Tracker", symbol: Self.homeSymbol, in: app)
        let log = app.buttons["logHeadacheButton"]
        XCTAssertTrue(log.waitForExistence(timeout: 15), "the log button is missing")
        log.tap()
        answerLocationPrompt(timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["captureStatusLine"].waitForExistence(timeout: 30), "the tap never registered")
        QA.checkpoint(app, "core-logged")

        openHistory(in: app)
        XCTAssertEqual(totalLogs(in: app), seeded + 1, "History did not count the new log")
        QA.checkpoint(app, "core-history-after-log")

        app.launchArguments.removeAll { $0 == "-HeadacheScreenshotSeed" }
        QA.relaunch(app)
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 25), "Home never rendered")
        QA.checkpoint(app, "core-home-after-relaunch")
        openHistory(in: app)
        XCTAssertEqual(totalLogs(in: app), seeded + 1, "the log was gone after a relaunch")
        QA.checkpoint(app, "core-history-after-relaunch")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, arguments: arguments)
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 25), "Home never rendered")
        return app
    }

    /// The German strings the journeys look for, from Localizable.xcstrings;
    /// other personas see the English source.
    private static let german = [
        "History": "Verlauf", "Patterns": "Muster", "Settings": "Einstellungen",
        "Proactive Alerts": "Wetterhinweise", "Know before the headache hits": "Wetterhinweise rechtzeitig erhalten",
        "Close": "Schließen",
    ]

    /// The tab icons, which the unfolded Duo's tab pill exposes as identifiers.
    private static let homeSymbol = "brain.head.profile"
    private static let historySymbol = "clock.arrow.circlepath"
    private static let patternsSymbol = "chart.bar.xaxis"
    private static let settingsSymbol = "slider.horizontal.3"

    private func L(_ english: String) -> String {
        QA.persona == "german" ? Self.german[english] ?? english : english
    }

    private func tabButton(_ english: String, symbol: String, in app: XCUIApplication) -> XCUIElement {
        let match = NSPredicate(format: "label == %@ OR identifier == %@", L(english), symbol)
        let bar = app.tabBars.buttons.matching(match).firstMatch
        if bar.exists { return bar }
        let pill = app.buttons.matching(match).firstMatch
        return pill.exists ? pill : bar
    }

    /// A tap can miss the unfolded Duo's tab pill; a short press on the
    /// button's own coordinate selects it there too.
    private func tapTab(_ english: String, symbol: String, in app: XCUIApplication) {
        let button = tabButton(english, symbol: symbol, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 15), "\(english) tab missing")
        button.tap()
        let selected = NSPredicate(format: "isSelected == true")
        let wait = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: selected, object: button)], timeout: 3)
        if wait != .completed {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
        }
    }

    /// History is a tab on a phone and its own pane beside One Tap on the unfolded Duo.
    private func openHistory(in app: XCUIApplication) {
        let total = app.descendants(matching: .any)["totalLogsValue"]
        if tabButton("History", symbol: Self.historySymbol, in: app).waitForExistence(timeout: 5) {
            tapTab("History", symbol: Self.historySymbol, in: app)
        }
        XCTAssertTrue(total.waitForExistence(timeout: 15), "History never rendered")
    }

    private func totalLogs(in app: XCUIApplication) -> Int {
        let total = app.descendants(matching: .any)["totalLogsValue"]
        XCTAssertTrue(total.waitForExistence(timeout: 15), "Total Logs missing")
        return Int(total.label) ?? -1
    }

    /// The first log raises the system location prompt; later ones do not.
    private func answerLocationPrompt(timeout: TimeInterval = 10) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["Don\u{2019}t Allow", "Don't Allow", "Nicht erlauben"])
        ).firstMatch
        if deny.waitForExistence(timeout: timeout) { deny.tap() }
    }
}
