import XCTest
@testable import OneTapHeadacheTracker

/// The funnel record that answers "where did this customer convert, how early
/// were they asked, and how many pitches did it take". Every assertion here is a
/// claim that will be read off a RevenueCat customer record later, so wrong
/// values are worse than no values.
final class ConversionDiagnosticsTests: XCTestCase {

    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite per test: these counters live in the App Group and
        // would otherwise carry between tests and into the real container.
        let name = "conv.tests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: name)!
        ConversionDiagnostics.defaultsOverride = suite
    }

    override func tearDown() {
        ConversionDiagnostics.defaultsOverride = nil
        suite = nil
        super.tearDown()
    }

    func testImpressionIDsAreReducedToSurfaces() {
        XCTAssertEqual(
            ConversionDiagnostics.surface(fromImpressionID: "headache_insights_sheet"),
            "insights_sheet"
        )
        // An id from somewhere that did not follow the convention is kept whole
        // rather than mangled.
        XCTAssertEqual(
            ConversionDiagnostics.surface(fromImpressionID: "legacy_sheet"),
            "legacy_sheet"
        )
    }

    func testCountsPitchesPerSurfaceAndInTotal() {
        ConversionDiagnostics.recordPitchView(impressionID: "headache_home_sheet")
        ConversionDiagnostics.recordPitchView(impressionID: "headache_home_sheet")
        ConversionDiagnostics.recordPitchView(impressionID: "headache_insights_sheet")

        XCTAssertEqual(ConversionDiagnostics.totalPitchViews, 3)
        XCTAssertEqual(ConversionDiagnostics.viewsBySurface["home_sheet"], 2)
        XCTAssertEqual(ConversionDiagnostics.viewsBySurface["insights_sheet"], 1)
        XCTAssertEqual(ConversionDiagnostics.lastSurface, "insights_sheet")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["pitch_views_total"], "3")
        XCTAssertEqual(attributes["pitch_views_home_sheet"], "2")
        XCTAssertEqual(attributes["pitch_last"], "insights_sheet")
    }

    func testNoAttributesBeforeAnyPitchIsSeen() {
        // Someone who has never been shown a paywall has nothing to say about
        // paywalls. Zeros would make them look like a funnel failure.
        ConversionDiagnostics.recordAppOpen()
        XCTAssertTrue(ConversionDiagnostics.subscriberAttributes.isEmpty)
    }

    func testCountsAppOpensAndStampsAnInstallDate() {
        XCTAssertNil(ConversionDiagnostics.installDate)
        ConversionDiagnostics.recordAppOpen()
        let stamped = ConversionDiagnostics.installDate
        XCTAssertNotNil(stamped)

        ConversionDiagnostics.recordAppOpen()
        XCTAssertEqual(ConversionDiagnostics.appOpens, 2)
        // The install date is stamped once and never moves.
        XCTAssertEqual(ConversionDiagnostics.installDate, stamped)
    }

    func testRecordsHowEarlyTheFirstPitchArrived() {
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "headache_home_sheet")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["opens_before_first_pitch"], "3")
        XCTAssertEqual(attributes["days_since_install"], "0")
    }

    func testTheEarlinessPairIsFrozenOnTheFirstPitchOnly() {
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "headache_home_sheet")
        // Later launches and later pitches must not rewrite how early the ask
        // actually was.
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "headache_settings_sheet")

        XCTAssertEqual(
            ConversionDiagnostics.subscriberAttributes["opens_before_first_pitch"],
            "1"
        )
    }

    func testAnInstallThatPredatesThisCodeReportsNoAge() {
        // No recorded app open, so no install stamp. Absent is the honest
        // answer; zero would claim they were asked on their first day.
        ConversionDiagnostics.recordPitchView(impressionID: "headache_home_sheet")
        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertNil(attributes["days_since_install"])
        XCTAssertNotNil(attributes["pitch_views_total"])
    }

    func testConversionFreezesTheSurfaceAndCountAtTheMomentOfSale() {
        ConversionDiagnostics.recordPitchView(impressionID: "headache_home_sheet")
        ConversionDiagnostics.recordPitchView(impressionID: "headache_insights_sheet")
        ConversionDiagnostics.recordConversion(
            plan: "com.jackwallner.headachelogger.yearly",
            startedTrial: true,
            offeringID: "default"
        )
        // A pitch seen after the sale must not rewrite the story of how they
        // converted.
        ConversionDiagnostics.recordPitchView(impressionID: "headache_settings_sheet")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_surface"], "insights_sheet")
        XCTAssertEqual(attributes["pitch_views_at_convert"], "2")
        XCTAssertEqual(attributes["converted_plan"], "com.jackwallner.headachelogger.yearly")
        XCTAssertEqual(attributes["converted_with_trial"], "true")
        XCTAssertEqual(attributes["converted_offering"], "default")
        XCTAssertEqual(attributes["days_to_convert"], "0")
    }

    func testOnlyTheFirstConversionIsRecorded() {
        ConversionDiagnostics.recordPitchView(impressionID: "headache_home_sheet")
        ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: true)
        ConversionDiagnostics.recordPitchView(impressionID: "headache_settings_sheet")
        // A renewal or plan change is not a new answer to "what sold this
        // person".
        ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: false)

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_plan"], "monthly")
        XCTAssertEqual(attributes["converted_with_trial"], "true")
        XCTAssertEqual(attributes["converted_surface"], "home_sheet")
    }

    func testAttributeKeysStayInsideRevenueCatsLimit() {
        // RevenueCat drops a key over 40 characters, silently. A long surface
        // name must be truncated rather than lost.
        let longSurface = String(repeating: "a", count: 80)
        ConversionDiagnostics.recordPitchView(impressionID: "headache_\(longSurface)")
        for key in ConversionDiagnostics.subscriberAttributes.keys {
            XCTAssertLessThanOrEqual(key.count, 40, "attribute key too long: \(key)")
        }
    }

    func testNoAttributeCarriesFreeTextOrHealthData() {
        // The whole record must stay counts, dates, and short surface names.
        // Anything a user typed, or anything about their symptoms, would turn a
        // funnel label into a privacy problem.
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "headache_home_sheet")
        ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: false)

        for (key, value) in ConversionDiagnostics.subscriberAttributes {
            XCTAssertFalse(value.contains(" "), "\(key) looks like free text: \(value)")
            XCTAssertLessThanOrEqual(value.count, 64, "\(key) is too long to be a label")
        }
    }
}
