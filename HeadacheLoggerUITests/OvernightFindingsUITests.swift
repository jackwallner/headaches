import XCTest

/// UI guards for the 2026-10-30 bug hunt: the Home milestone card must stay on
/// screen, and Restore on onboarding's trial step must answer.
@MainActor
final class OvernightFindingsUITests: XCTestCase {

    private static let bundle = "com.jackwallner.headachelogger"

    func test02MilestoneCardStaysOnHome() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, arguments: ["-uitesting", "-HeadacheScreenshotSeed"])
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 25), "Home never rendered")

        let card = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "meaningful data")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "milestone card never appeared")
        sleep(5)
        XCTAssertTrue(card.exists, "milestone card hid itself")
        attachScreenshot(app, "milestone-card")
    }

    /// Runs first: it needs the fresh install's onboarding.
    func test01RestoreOnTrialStepAnswers() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()

        let start = app.buttons["Get Started"]
        XCTAssertTrue(start.waitForExistence(timeout: 25), "welcome never rendered")
        start.tap()

        XCTAssertTrue(app.staticTexts["Apple Health"].waitForExistence(timeout: 15))
        app.buttons["Continue"].tap()
        answerHealthSheet(app)

        XCTAssertTrue(app.staticTexts["Location"].waitForExistence(timeout: 20), "location page never rendered")
        app.buttons["Continue"].tap()
        for label in ["Allow While Using App", "Allow Once", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: label == "Allow While Using App" ? 8 : 1) {
                button.tap()
                break
            }
        }

        XCTAssertTrue(app.staticTexts["Get ahead of your headaches"].waitForExistence(timeout: 20), "trial step never rendered")
        app.buttons["Restore"].tap()

        let message = app.staticTexts["onboardingTrialError"]
        let home = app.descendants(matching: .any)["homeView"]
        let answered = NSPredicate { _, _ in message.exists || home.exists }
        let expectation = XCTNSPredicateExpectation(predicate: answered, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 30), .completed, "Restore showed nothing")
        attachScreenshot(app, "onboarding-restore")
    }

    /// The simulator's Health sheet: turn everything on and allow, or give up quietly.
    private func answerHealthSheet(_ app: XCUIApplication) {
        let turnOnAll = app.buttons["Turn On All"]
        guard turnOnAll.waitForExistence(timeout: 10) else { return }
        turnOnAll.tap()
        let allow = app.navigationBars.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
