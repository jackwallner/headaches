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
        waitForCapture(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["latestEventCard"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "logged")

        showHistory(app)
        QA.checkpoint(app, "history")

        tapTab(app, symbol: "chart.bar.xaxis", names: ["Patterns", "Muster"])
        QA.checkpoint(app, "patterns")
    }

    func testCoreLoopLogSurvivesRelaunch() {
        continueAfterFailure = false
        let app = launch(Self.seededPro)
        showHistory(app)
        // History is a List, so rows below the fold are not in the hierarchy
        // and counting them cannot show a new entry. The summary card at the
        // top always is.
        let before = totalLogs(app)
        XCTAssertNotNil(before, "Total Logs never rendered")
        QA.checkpoint(app, "core-history-before")

        tapTab(app, symbol: "brain.head.profile", names: ["Logging", "Eintragen", "One Tap Headache Tracker"])
        app.buttons["logHeadacheButton"].tap()
        answerLocationPrompt(timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["latestEventCard"].waitForExistence(timeout: 20), "log never saved")
        // The Undo bar appears once capture ends; checkpoint after, so the card is settled.
        XCTAssertTrue(app.descendants(matching: .any)["undoSnackbar"].waitForExistence(timeout: 30), "capture never finished")
        QA.checkpoint(app, "core-logged")

        showHistory(app)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, (totalLogs(app) ?? 0) <= (before ?? 0) {
            Thread.sleep(forTimeInterval: 0.5)
        }
        let after = totalLogs(app)
        XCTAssertGreaterThan(after ?? 0, before ?? 0, "new entry missing from History")
        XCTAssertTrue(revealHistoryEntry(app).isHittable, "History lost its entries")
        QA.checkpoint(app, "core-history-after")

        // The seed rewrites the log on every launch, so the relaunch drops it
        // and reads what the first run saved.
        app.launchArguments.removeAll { $0 == "-HeadacheScreenshotSeed" }
        QA.relaunch(app)
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["latestEventCard"].waitForExistence(timeout: 20), "entry gone after relaunch")
        QA.checkpoint(app, "core-after-relaunch")
        showHistory(app)
        XCTAssertEqual(totalLogs(app), after, "the log was gone after a relaunch")
        QA.checkpoint(app, "core-history-after-relaunch")
    }

    func test03ProPaywallShownAndClosed() {
        continueAfterFailure = false
        let app = launch(["-uitesting", "-HeadacheScreenshotSeed"])
        tapTab(app, symbol: "slider.horizontal.3", names: ["Settings", "Einstellungen"])
        // By identifier: the row's label is localized ("Wetterhinweise" in German).
        let pro = app.buttons["proAlertsRow"]
        XCTAssertTrue(pro.waitForExistence(timeout: 15), "Pro row missing for a free user")
        QA.checkpoint(app, "settings")

        pro.tap()
        // By identifier: the title and the Close button are localized (German in the german persona).
        let title = app.staticTexts["paywallTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "paywall never rendered")
        QA.checkpoint(app, "pro-paywall", paywall: true)

        // At large text sizes the Close button can sit above the scrolled
        // content, and on the unfolded Duo it sits under the sheet's top edge;
        // a swipe down scrolls back to it or dismisses the sheet itself.
        let close = app.buttons["paywallCloseButton"]
        _ = close.waitForExistence(timeout: 5)
        for _ in 0..<3 where title.exists {
            if close.exists && close.isHittable {
                close.tap()
            } else {
                let scroll = app.scrollViews.firstMatch
                QA.swipe(scroll.exists ? scroll : app, .down)
            }
            if title.waitForNonExistence(timeout: 3) { break }
        }
        XCTAssertFalse(title.exists, "paywall never closed")
        XCTAssertTrue(pro.waitForExistence(timeout: 15), "paywall never closed")
        QA.checkpoint(app, "settings-after-paywall", paywall: false)
    }

    func test04ReturnVisitWithInterruption() {
        continueAfterFailure = false
        let app = launch(Self.seededPro)
        showHistory(app)
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
            let editButton = revealHistoryEntry(app)
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
        let editButton = revealHistoryEntry(app)
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

    /// A tab by its symbol identifier or its English or German label. The
    /// unfolded Duo draws the bar as a rail, so no `tabBars` query.
    private func tapTab(_ app: XCUIApplication, symbol: String, names: [String]) {
        let tab = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label IN %@", symbol, names
        )).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "\(names[0]) tab missing")
        tab.tap()
    }

    /// History is a tab on a phone and its own pane, with no tab, on the unfolded Duo.
    private func showHistory(_ app: XCUIApplication) {
        let tab = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label IN %@", "clock.arrow.circlepath", ["History", "Verlauf"]
        )).firstMatch
        if tab.waitForExistence(timeout: 5) { tab.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["historyView"].waitForExistence(timeout: 15), "History never rendered")
    }

    /// The Total Logs card's count, or nil while it is not on screen.
    private func totalLogs(_ app: XCUIApplication) -> Int? {
        let card = app.descendants(matching: .any)["summaryTotalLogs"]
        guard card.waitForExistence(timeout: 15) else { return nil }
        let digits = String((card.value as? String ?? "").filter(\.isNumber))
        return Int(digits)
    }

    /// Scrolls History until an entry's note button can be tapped.
    private func revealHistoryEntry(_ app: XCUIApplication) -> XCUIElement {
        let buttons = app.buttons.matching(identifier: "historyEntryNotesButton")
        _ = buttons.firstMatch.waitForExistence(timeout: 20)
        let list = app.descendants(matching: .any)["historyView"]
        func hittable() -> XCUIElement? {
            buttons.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
        }
        for _ in 0..<8 where hittable() == nil && list.exists {
            QA.swipe(list, .up)
        }
        return hittable() ?? buttons.firstMatch
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, arguments: arguments)
        XCTAssertTrue(app.descendants(matching: .any)["homeView"].waitForExistence(timeout: 25), "Home never rendered")
        return app
    }

    /// The tap saves at once and fills in weather and Health after; the Undo
    /// bar appears once that ends, so the checkpoint sees the settled screen.
    private func waitForCapture(in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["undoSnackbar"].waitForExistence(timeout: 40), "the tap never finished saving")
    }

    /// The first log raises the system location prompt; later ones do not.
    private func answerLocationPrompt(timeout: TimeInterval = 10) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["Allow While Using App", "Beim Verwenden der App erlauben", "Erlauben"])
        ).firstMatch
        if allow.waitForExistence(timeout: timeout) { allow.tap() }
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
