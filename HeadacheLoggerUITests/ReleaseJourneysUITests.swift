import XCTest

/// The release gate's journeys (`qa-gate run`): the first onboarding pages, a
/// one-tap log on seeded data, History and Patterns, the Pro paywall shown and
/// closed, and a return visit with an interruption. Each step ends in
/// `QA.checkpoint`, which runs the fleet oracles on the screen. Assert
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
        XCTAssertTrue(app.descendants(matching: .any)["latestEventCard"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "logged")

        app.tabBars.buttons["History"].tap()
        QA.checkpoint(app, "history")

        app.tabBars.buttons["Patterns"].tap()
        QA.checkpoint(app, "patterns")
    }

    func test03ProPaywallShownAndClosed() {
        continueAfterFailure = false
        let app = launch(["-uitesting", "-HeadacheScreenshotSeed"])
        app.tabBars.buttons["Settings"].tap()
        let pro = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Proactive Alerts")).firstMatch
        XCTAssertTrue(pro.waitForExistence(timeout: 15), "Pro row missing for a free user")
        QA.checkpoint(app, "settings")

        pro.tap()
        XCTAssertTrue(app.staticTexts["Know before the headache hits"].waitForExistence(timeout: 20), "paywall never rendered")
        QA.checkpoint(app, "pro-paywall", paywall: true)

        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 5) {
            close.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(pro.waitForExistence(timeout: 15), "paywall never closed")
        QA.checkpoint(app, "settings-after-paywall", paywall: false)
    }

    func test04ReturnVisitWithInterruption() {
        continueAfterFailure = false
        let app = launch(Self.seededPro)
        app.tabBars.buttons["History"].tap()
        QA.checkpoint(app, "history-before-interruption")

        QA.interrupt(app)
        QA.checkpoint(app, "history-after-interruption")

        QA.relaunch(app)
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "home-after-relaunch")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, arguments: arguments)
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 25), "Home never rendered")
        return app
    }
}
