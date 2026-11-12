import XCTest

/// iPad layout proof: every main screen plus onboarding and the paywall, in
/// portrait and landscape, attached as `<orientation>__<screen>`. Skipped on
/// iPhone. Run with `gh-sim test --device "iPad Pro 13-inch (M5)" --only
/// HeadacheLoggerUITests/IPadLayoutUITests`.
@MainActor
final class IPadLayoutUITests: XCTestCase {

    private static let bundle = "com.jackwallner.headachelogger"
    private static let seeded = ["-uitesting", "-HeadacheScreenshotSeed", "-HeadacheScreenshotBrand", "-HeadacheProOverride"]

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        continueAfterFailure = true
    }

    func testPortrait() {
        captureAll(orientation: .portrait, label: "portrait")
    }

    func testLandscape() {
        captureAll(orientation: .landscapeLeft, label: "landscape")
    }

    private func captureAll(orientation: UIDeviceOrientation, label: String) {
        XCUIDevice.shared.orientation = orientation

        let welcome = launch([], orientation: orientation)
        _ = welcome.buttons["Get Started"].waitForExistence(timeout: 20)
        attach(welcome, label, "onboarding-welcome")
        if welcome.buttons["Get Started"].exists {
            welcome.buttons["Get Started"].tap()
            _ = welcome.staticTexts["Apple Health"].waitForExistence(timeout: 15)
            Thread.sleep(forTimeInterval: 1)
            attach(welcome, label, "onboarding-health")
        }

        let home = launch(Self.seeded, orientation: orientation)
        _ = home.descendants(matching: .any)["latestEventCard"].waitForExistence(timeout: 20)
        attach(home, label, "home")

        let tour: [(String, [String])] = [
            ("history", ["-HeadacheDuoScreen", "history"]),
            ("patterns", ["-HeadacheDuoScreen", "patterns"]),
            ("pattern-detail", ["-HeadacheDuoScreen", "pattern"]),
            ("settings", ["-HeadacheDuoScreen", "settings"]),
            ("history-entry", ["-HeadacheDuoScreen", "history", "-HeadacheScreenshotHistoryEntry"]),
        ]
        for (name, args) in tour {
            let app = launch(Self.seeded + args, orientation: orientation)
            Thread.sleep(forTimeInterval: 2)
            attach(app, label, name)
            if name == "history-entry" {
                let edit = app.buttons.matching(identifier: "historyEntryNotesButton").firstMatch
                if edit.waitForExistence(timeout: 10), edit.isHittable {
                    edit.tap()
                    _ = app.descendants(matching: .any)["editEventSheet"].waitForExistence(timeout: 15)
                    Thread.sleep(forTimeInterval: 1)
                    attach(app, label, "edit-sheet")
                }
            }
        }

        for mode in ["yearly", "trial"] {
            let app = launch(Self.seeded + ["-PaywallSnapshot", mode], orientation: orientation)
            Thread.sleep(forTimeInterval: 4)
            attach(app, label, "paywall-\(mode)")
        }

        let gated = launch(["-uitesting", "-HeadacheScreenshotSeed", "-HeadacheDuoScreen", "settings"], orientation: orientation)
        Thread.sleep(forTimeInterval: 2)
        let pro = gated.buttons["proAlertsRow"]
        if pro.waitForExistence(timeout: 10) {
            pro.tap()
            Thread.sleep(forTimeInterval: 3)
            attach(gated, label, "paywall-sheet")
        }
    }

    private func launch(_ arguments: [String], orientation: UIDeviceOrientation) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        app.terminate()
        app.launchArguments = arguments
        XCUIDevice.shared.orientation = orientation
        app.launch()
        XCUIDevice.shared.orientation = orientation
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    private func attach(_ app: XCUIApplication, _ orientation: String, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(orientation)__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
