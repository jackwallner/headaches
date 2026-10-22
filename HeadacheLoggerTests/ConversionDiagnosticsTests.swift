import Foundation
import XCTest

import RevenueCat

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

    func testFunnelStepsAreSentAsFleetKeys() {
        ConversionDiagnostics.recordPitchView(impressionID: "headache_onboarding_trial")
        ConversionDiagnostics.record(.trialOfferReached)
        ConversionDiagnostics.record(.trialCTATapped)
        ConversionDiagnostics.record(.purchaseCancelled)
        ConversionDiagnostics.record(.trialCTATapped)

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["funnel_trialOfferReached"], "1")
        XCTAssertEqual(attributes["funnel_trialCTATapped"], "2")
        XCTAssertEqual(attributes["funnel_purchaseCancelled"], "1")
        XCTAssertNil(attributes["funnel_freeVersionChosen"])
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

@MainActor
private final class MockPurchases: RevenueCatClient {
    var cachedCustomerInfo: CustomerInfo?
    var info = makeInfo(active: false)
    var fetchError: Error?
    var fetchHandler: ((CacheFetchPolicy) async throws -> CustomerInfo)?
    var purchaseCalls = 0
    var restoreCalls = 0
    var cancelPurchase = false
    var policies: [CacheFetchPolicy] = []
    var eligibility: [String: IntroEligibilityStatus] = [:]

    func customerInfo(fetchPolicy: CacheFetchPolicy) async throws -> CustomerInfo {
        policies.append(fetchPolicy)
        if let fetchHandler { return try await fetchHandler(fetchPolicy) }
        if let fetchError { throw fetchError }
        return info
    }
    var offering: Offering?
    func paywallOffering(forceRefresh: Bool) async throws -> Offering? {
        if let fetchError { throw fetchError }
        return offering
    }
    func purchase(package: Package) async throws -> PurchaseResultData {
        purchaseCalls += 1
        return (nil, info, cancelPurchase)
    }
    func restorePurchases() async throws -> CustomerInfo {
        restoreCalls += 1
        if let fetchError { throw fetchError }
        return info
    }
    func introEligibility(productIdentifiers: [String]) async -> [String: IntroEligibilityStatus] { eligibility }
    func setSubscriberAttributes(_ attributes: [String: String]) {}
    func recordImpression(_ params: CustomPaywallImpressionParams) {}
}

@MainActor
private func makeInfo(active: Bool, date: Date = .now, lifetime: Bool = false, identifier: String = RevenueCatConfig.proEntitlement) -> CustomerInfo {
    let entitlement = EntitlementInfo(
        identifier: identifier, isActive: active, willRenew: active && !lifetime,
        periodType: .normal, latestPurchaseDate: date, originalPurchaseDate: date,
        expirationDate: lifetime ? nil : date.addingTimeInterval(active ? 86_400 : -86_400),
        store: .appStore, productIdentifier: lifetime ? HeadacheProProduct.lifetime : HeadacheProProduct.monthly,
        isSandbox: true, ownershipType: .purchased
    )
    return CustomerInfo(entitlements: EntitlementInfos(entitlements: [identifier: entitlement]),
                        requestDate: date, firstSeen: date, originalAppUserId: "purchase-unit-test")
}

@MainActor
private func makePackage() -> Package {
    let product = TestStoreProduct(
        localizedTitle: "Monthly", price: 3.99, currencyCode: "USD",
        localizedPriceString: "$3.99", productIdentifier: HeadacheProProduct.monthly,
        productType: .autoRenewableSubscription, localizedDescription: "Monthly access",
        subscriptionPeriod: .init(value: 1, unit: .month), locale: Locale(identifier: "en_US")
    ).toStoreProduct()
    return Package(identifier: "$rc_monthly", packageType: .monthly, storeProduct: product,
                   offeringIdentifier: "default", webCheckoutUrl: nil)
}

@MainActor
final class PurchaseEntitlementTests: XCTestCase {
    func testDebugAndSimulatorNeverSelectProductionKey() {
        for simulator in [true, false] {
            XCTAssertNil(RevenueCatEnvironment.key(production: "appl_prod", isDebug: true, isSimulator: simulator, testKey: nil))
            XCTAssertNil(RevenueCatEnvironment.key(production: "appl_prod", isDebug: true, isSimulator: simulator, testKey: "appl_prod"))
            XCTAssertEqual(RevenueCatEnvironment.key(production: "appl_prod", isDebug: true, isSimulator: simulator, testKey: "test_qa"), "test_qa")
        }
        XCTAssertNil(RevenueCatEnvironment.key(production: "appl_prod", isDebug: false, isSimulator: true, testKey: "test_qa"))
        XCTAssertEqual(RevenueCatEnvironment.key(production: "appl_prod", isDebug: false, isSimulator: false, testKey: "test_qa"), "appl_prod")
    }

    func testCachedPremiumUnlocksBeforeNetworkRespondsAndSurvivesOffline() async {
        let mock = MockPurchases()
        mock.cachedCustomerInfo = makeInfo(active: true)
        mock.fetchError = URLError(.notConnectedToInternet)
        let service = StoreService(client: mock)
        service.start()
        XCTAssertTrue(service.isProUnlocked)
        await service.updateCustomerProductStatus(fetchPolicy: .fetchCurrent)
        XCTAssertTrue(service.isProUnlocked)
    }

    func testUnresolvedMembershipCannotStartAnotherPurchase() async {
        let mock = MockPurchases()
        mock.fetchError = URLError(.notConnectedToInternet)
        let service = StoreService(client: mock)
        XCTAssertTrue(service.isCheckingEntitlements)
        _ = try? await service.purchase(makePackage())
        XCTAssertEqual(mock.purchaseCalls, 0)
        XCTAssertFalse(service.isCheckingEntitlements)
    }

    func testRestoreUnlocksLifetimeWithoutBuyingAgain() async throws {
        let mock = MockPurchases()
        mock.info = makeInfo(active: true, lifetime: true)
        let service = StoreService(client: mock)
        await service.restorePurchases()
        XCTAssertTrue(service.isProUnlocked)
        XCTAssertEqual(mock.restoreCalls, 1)
        _ = try await service.purchase(makePackage())
        XCTAssertEqual(mock.purchaseCalls, 0)

    }

    func testPurchaseAndCancellationUseRevenueCatResult() async throws {
        let mock = MockPurchases()
        mock.info = makeInfo(active: false)
        let service = StoreService(client: mock)
        await service.updateCustomerProductStatus()
        mock.cancelPurchase = true
        let cancelled = try await service.purchase(makePackage())
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertFalse(service.isProUnlocked)
        mock.cancelPurchase = false
        mock.info = makeInfo(active: true)
        let purchased = try await service.purchase(makePackage())
        XCTAssertEqual(purchased, .purchased)
        XCTAssertTrue(service.isProUnlocked)
        XCTAssertEqual(mock.purchaseCalls, 2)
    }

    func testDelayedFreeFetchCannotRelockACompletedRestore() async throws {
        let mock = MockPurchases()
        let old = makeInfo(active: false, date: Date(timeIntervalSinceNow: -60))
        mock.info = makeInfo(active: true)
        let service = StoreService(client: mock)
        var continuation: CheckedContinuation<CustomerInfo, Never>?
        mock.fetchHandler = { _ in await withCheckedContinuation { continuation = $0 } }
        let fetch = Task { await service.updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
        while continuation == nil { await Task.yield() }
        await service.restorePurchases()
        continuation?.resume(returning: old)
        await fetch.value
        XCTAssertTrue(service.isProUnlocked)
    }

    func testListenerUpdatesItsOwnServiceAndIgnoresOlderRecords() async throws {
        let mock = MockPurchases()
        let now = Date()
        let service = StoreService(client: mock)
        await service.receive(makeInfo(active: true, date: now)).value
        XCTAssertTrue(service.isProUnlocked)
        await service.receive(makeInfo(active: false, date: now.addingTimeInterval(-60))).value
        XCTAssertTrue(service.isProUnlocked)
        await service.receive(makeInfo(active: false, date: now.addingTimeInterval(60))).value
        XCTAssertFalse(service.isProUnlocked)
    }
}
