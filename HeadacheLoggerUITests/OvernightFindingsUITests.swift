import XCTest

/// UI guards for the 2026-10-30 bug hunt: the Home milestone card must stay on
/// screen, and onboarding must end on Home (no trial step since 2026-11-24).
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
    func test01OnboardingEndsOnHome() {
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

        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 30), "onboarding did not end on Home")
        XCTAssertFalse(app.staticTexts["Get ahead of your headaches"].exists, "the onboarding trial step is back")
        attachScreenshot(app, "onboarding-home")

        // The trial is pitched after the first log, and it bills the yearly plan.
        app.buttons["logHeadacheButton"].tap()
        let trial = app.buttons["Start My Free Trial"]
        XCTAssertTrue(trial.waitForExistence(timeout: 30), "the first-log trial sheet never rose")
        let billed = app.staticTexts["trialOfferBilledAmount"]
        XCTAssertTrue(billed.waitForExistence(timeout: 10), "the billed amount is missing")
        XCTAssertTrue(billed.label.contains("year"), "the trial sheet bills \(billed.label), not the yearly plan")
        attachScreenshot(app, "first-log-trial-sheet")
    }

    /// The simulator's Health sheet: turn everything on and allow, or give up quietly.
    /// iOS 27.2 lists one "Turn On All" per category and may need a scroll, so
    /// keep answering until the sheet is gone or the Location page shows.
    private func answerHealthSheet(_ app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if app.staticTexts["Location"].exists { return }
            let allow = app.navigationBars.buttons["Allow"]
            if allow.exists, allow.isEnabled {
                allow.tap()
                continue
            }
            // Declining raises a "turn on later in Health" alert.
            let ok = app.buttons["OK"].firstMatch
            if ok.exists, ok.isHittable {
                ok.tap()
                continue
            }
            // iOS 27.2: the sheet ends in Continue / Don't Allow. Declining is
            // enough here; the app proceeds either way.
            let decline = ["Don’t Allow", "Don't Allow"].map { app.buttons[$0].firstMatch }.first { $0.exists && $0.isHittable }
            if let decline {
                decline.tap()
                continue
            }
            let turnOnAll = app.buttons["Turn On All"].firstMatch
            if turnOnAll.exists, turnOnAll.isHittable {
                turnOnAll.tap()
                continue
            }
            sleep(1)
        }
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
