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

        // At large text sizes the Close button can sit above the scrolled
        // content; swiping down scrolls back to it, then dismisses the sheet.
        let close = app.buttons["Close"]
        _ = close.waitForExistence(timeout: 5)
        let title = app.staticTexts["Know before the headache hits"]
        for _ in 0..<3 where title.exists {
            if close.exists && close.isHittable {
                close.tap()
                break
            }
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

    func testLocalizedStoreScreenshots() throws {
        continueAfterFailure = false
        let localeURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "capture-locales", withExtension: "json"))
        let locales = try JSONDecoder().decode([StoreScreenshotLocale].self, from: Data(contentsOf: localeURL))

        for locale in locales {
            captureHome(locale, frame: "01-keep-a-clear-record.png")
            captureHome(locale, frame: "05-save-context-with-one-tap.png", arguments: ["-HeadacheScreenshotCapture"])
            captureHistory(locale, frame: "02-review-a-recorded-headache.png")
            capturePatterns(locale)
            captureHistory(locale, frame: "03-read-your-record-clearly.png", scrollToEntry: true)
            captureHistoryMenu(locale)
            captureEditEvent(locale)
        }
    }

    func testLocalizedHistoryStoreScreenshots() throws {
        continueAfterFailure = false
        let localeURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "capture-locales", withExtension: "json"))
        let locales = try JSONDecoder().decode([StoreScreenshotLocale].self, from: Data(contentsOf: localeURL))

        for locale in locales {
            captureHistory(locale, frame: "02-review-a-recorded-headache.png")
            captureHistory(locale, frame: "03-read-your-record-clearly.png", scrollToEntry: true)
            captureHistoryMenu(locale)
        }
    }

    private func captureHome(_ locale: StoreScreenshotLocale, frame: String, arguments: [String] = []) {
        let app = launchScreenshot(locale, arguments: arguments)
        _ = app.descendants(matching: .any)["latestEventCard"].waitForExistence(timeout: 20)
        if frame == "05-save-context-with-one-tap.png" {
            _ = app.descendants(matching: .any)["captureStatusLine"].waitForExistence(timeout: 20)
        }
        attachScreenshot(app, locale: locale, frame: frame)
    }

    private func captureHistory(_ locale: StoreScreenshotLocale, frame: String, scrollToEntry: Bool = false) {
        let historyArguments = ["-HeadacheDuoScreen", "history"]
            + (scrollToEntry ? ["-HeadacheScreenshotHistoryEntry"] : [])
        let app = launchScreenshot(locale, arguments: historyArguments)
        _ = app.descendants(matching: .any)["historyView"].waitForExistence(timeout: 20)
        if scrollToEntry {
            let editButton = app.buttons.matching(identifier: "historyEntryNotesButton").firstMatch
            _ = editButton.waitForExistence(timeout: 20)
            if !editButton.isHittable { attachHistoryCaptureDiagnostics(app, locale: locale) }
            XCTAssertTrue(editButton.isHittable, "History entry never became visible for \(locale.storeLocale)")
        }
        attachScreenshot(app, locale: locale, frame: frame)
    }

    private func capturePatterns(_ locale: StoreScreenshotLocale) {
        let app = launchScreenshot(locale, arguments: ["-HeadacheScreenshotPatterns"])
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(app, locale: locale, frame: "04-see-your-patterns.png")
    }

    private func captureHistoryMenu(_ locale: StoreScreenshotLocale) {
        let app = launchScreenshot(locale, arguments: ["-HeadacheDuoScreen", "history"])
        _ = app.descendants(matching: .any)["historyView"].waitForExistence(timeout: 20)
        let menu = app.descendants(matching: .any)["historyImportExportMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "History menu missing for \(locale.storeLocale)")
        if menu.exists { menu.tap() }
        _ = app.buttons["exportHistoryButton"].waitForExistence(timeout: 10)
        attachScreenshot(app, locale: locale, frame: "06-review-each-entry.png")
    }

    private func captureEditEvent(_ locale: StoreScreenshotLocale) {
        let app = launchScreenshot(locale, arguments: [
            "-HeadacheDuoScreen", "history", "-HeadacheScreenshotHistoryEntry"
        ])
        _ = app.descendants(matching: .any)["historyView"].waitForExistence(timeout: 20)
        let editButton = app.buttons.matching(identifier: "historyEntryNotesButton").firstMatch
        _ = editButton.waitForExistence(timeout: 20)
        if !editButton.isHittable { attachHistoryCaptureDiagnostics(app, locale: locale) }
        XCTAssertTrue(editButton.isHittable, "History entry never became visible for \(locale.storeLocale)")
        if editButton.isHittable { editButton.tap() }
        _ = app.descendants(matching: .any)["editEventSheet"].waitForExistence(timeout: 15)
        attachScreenshot(app, locale: locale, frame: "07-review-a-completed-entry.png")
    }

    private func launchScreenshot(_ locale: StoreScreenshotLocale, arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        app.launchArguments = [
            "-uitesting", "-HeadacheScreenshotSeed", "-HeadacheScreenshotBrand", "-HeadacheProOverride",
            "-AppleLanguages", "(\(locale.language))", "-AppleLocale", locale.appleLocale
        ] + arguments
        app.launch()
        _ = app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 25)
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    private func attachScreenshot(_ app: XCUIApplication, locale: StoreScreenshotLocale, frame: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(locale.storeLocale)__\(frame)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachHistoryCaptureDiagnostics(_ app: XCUIApplication, locale: StoreScreenshotLocale) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(locale.storeLocale)__history-scroll-debug.png"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(locale.storeLocale)__history-hierarchy.txt"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, arguments: arguments)
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 25), "Home never rendered")
        return app
    }
}

private struct StoreScreenshotLocale: Decodable {
    let storeLocale: String
    let language: String
    let appleLocale: String

    enum CodingKeys: String, CodingKey {
        case storeLocale = "store_locale"
        case language
        case appleLocale = "apple_locale"
    }
}
