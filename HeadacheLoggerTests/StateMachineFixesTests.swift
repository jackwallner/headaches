import CoreLocation
import ObjectiveC
import RevenueCat
import SwiftData
import UserNotifications
import XCTest
@testable import OneTapHeadacheTracker

/// Records notification requests in place of the real center, which rejects `add` while
/// permission is undecided on the test simulator. Uses ObjC method replacement on
/// `UNUserNotificationCenter`, restored in `uninstall()`.
final class RecordingNotificationCenter: @unchecked Sendable {
    static let shared = RecordingNotificationCenter()
    private let lock = NSLock()
    private var stored: [UNNotificationRequest] = []
    private var authorizationCalls = 0
    private var originals: [(Method, IMP)] = []

    var requests: [UNNotificationRequest] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    var authorizationRequests: Int {
        lock.lock(); defer { lock.unlock() }
        return authorizationCalls
    }

    func install() {
        uninstall()
        lock.lock(); stored = []; authorizationCalls = 0; lock.unlock()
        let cls: AnyClass = UNUserNotificationCenter.self

        let add: @convention(block) (AnyObject, UNNotificationRequest, (@convention(block) (Error?) -> Void)?) -> Void = { [self] _, request, completion in
            lock.lock()
            stored.removeAll { $0.identifier == request.identifier }
            stored.append(request)
            lock.unlock()
            completion?(nil)
        }
        let pending: @convention(block) (AnyObject, @convention(block) ([UNNotificationRequest]) -> Void) -> Void = { [self] _, completion in
            completion(requests)
        }
        let remove: @convention(block) (AnyObject, [String]) -> Void = { [self] _, ids in
            lock.lock()
            stored.removeAll { ids.contains($0.identifier) }
            lock.unlock()
        }
        let authorize: @convention(block) (AnyObject, UInt, @convention(block) (Bool, Error?) -> Void) -> Void = { [self] _, _, completion in
            lock.lock(); authorizationCalls += 1; lock.unlock()
            completion(true, nil)
        }
        replace(cls, "addNotificationRequest:withCompletionHandler:", add)
        replace(cls, "getPendingNotificationRequestsWithCompletionHandler:", pending)
        replace(cls, "removePendingNotificationRequestsWithIdentifiers:", remove)
        replace(cls, "requestAuthorizationWithOptions:completionHandler:", authorize)
    }

    func uninstall() {
        for (method, imp) in originals { method_setImplementation(method, imp) }
        originals = []
    }

    private func replace(_ cls: AnyClass, _ name: String, _ block: Any) {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)) else {
            fatalError("missing selector \(name)")
        }
        originals.append((method, method_getImplementation(method)))
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

/// Regression tests for project-docs/audits/state-machines-2026-11-06-fixes.md.
@MainActor
final class StateMachineFixesTests: XCTestCase {
    private let defaults = HeadacheAppGroup.userDefaults
    private var saved: [String: Any?] = [:]
    private let cal = Calendar.current
    private let fake = RecordingNotificationCenter.shared

    private var touchedKeys: [HeadacheStorageKey] {
        [.patternAlertsEnabled, .patternAlertSensitivity, .proAlertsEnabled, .proAlertQuietHoursEnabled,
         .proAlertQuietStartHour, .proAlertQuietEndHour, .lastKnownLatitude, .lastKnownLongitude,
         .lastKnownLocationCapturedAt]
    }

    override func setUp() async throws {
        try await super.setUp()
        for key in touchedKeys { saved[key.rawValue] = defaults.object(forKey: key.rawValue) }
        fake.install()
    }

    override func tearDown() async throws {
        fake.uninstall()
        StoreService.shared.apply(customerInfo: CustomerInfo(
            entitlements: EntitlementInfos(entitlements: [:]),
            requestDate: .now, firstSeen: .now, originalAppUserId: "fixes-reset"
        ))
        for key in touchedKeys {
            if let value = saved[key.rawValue] ?? nil {
                defaults.set(value, forKey: key.rawValue)
            } else {
                defaults.removeObject(forKey: key.rawValue)
            }
        }
        try await super.tearDown()
    }

    // MARK: helpers

    private func makeContext() throws -> ModelContext {
        let schema = Schema([HeadacheEvent.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func event(day: Int, hour: Int) -> HeadacheEvent {
        // Oct 5 2026 is a Monday.
        HeadacheEvent(timestamp: cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 5))!)
    }

    private func insert(_ pairs: [(Int, Int)], into context: ModelContext) {
        pairs.forEach { context.insert(event(day: $0.0, hour: $0.1)) }
    }

    /// Seven events with no bucket at the 3-event minimum (Monday 15:00 has two).
    private let baseline = [(5, 15), (12, 15), (6, 9), (7, 10), (8, 11), (9, 12), (10, 13)]

    private func pendingPatternRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("pattern-alert-") }
    }

    private func pendingPatternIDs() async -> [String] {
        await pendingPatternRequests().map(\.identifier).sorted()
    }

    /// Waits for a reschedule the code under test started in its own Task.
    private func pendingPatternIDs(settlingTo expected: [String]) async -> [String] {
        for _ in 0..<150 {
            let ids = await pendingPatternIDs()
            if ids == expected { return ids }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await pendingPatternIDs()
    }

    private func fireDate(_ request: UNNotificationRequest) -> Date? {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }

    private func cluster(weekday: Int, startHour: Int) -> ProactiveAlertsEngine.PatternCluster {
        ProactiveAlertsEngine.PatternCluster(
            weekdayIndex: weekday, weekdayName: "Monday", startHour: startHour,
            endHour: startHour, headacheCount: 4, totalHeadaches: 10
        )
    }

    private func setQuietHours(enabled: Bool, start: Int = 22, end: Int = 7) {
        defaults.set(enabled, forKey: HeadacheStorageKey.proAlertQuietHoursEnabled.rawValue)
        defaults.set(start, forKey: HeadacheStorageKey.proAlertQuietStartHour.rawValue)
        defaults.set(end, forKey: HeadacheStorageKey.proAlertQuietEndHour.rawValue)
    }

    private func enablePatternAlertsAsPro() {
        StoreService.shared.activateScreenshotPro()
        defaults.set(true, forKey: HeadacheStorageKey.patternAlertsEnabled.rawValue)
        defaults.set(1.0, forKey: HeadacheStorageKey.patternAlertSensitivity.rawValue)
        setQuietHours(enabled: true)
    }

    // MARK: B1 pattern toggle asks for notification permission

    func testPatternToggleAsksForNotificationPermission() async throws {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        XCTAssertEqual(status, .notDetermined, "precondition: permission undecided on the test simulator")
        enablePatternAlertsAsPro()
        let context = try makeContext()
        insert(baseline + [(19, 15)], into: context)
        try context.save()

        await ProactiveAlertsEngine.patternAlertSettingsChanged(in: context)
        XCTAssertEqual(fake.authorizationRequests, 1, "turning the pattern toggle on asks for notification permission")
        let pending = await pendingPatternIDs()
        XCTAssertEqual(pending, ["pattern-alert-2-15"])

        defaults.set(false, forKey: HeadacheStorageKey.patternAlertsEnabled.rawValue)
        await ProactiveAlertsEngine.patternAlertSettingsChanged(in: context)
        XCTAssertEqual(fake.authorizationRequests, 1, "turning it off never asks")
        let afterOff = await pendingPatternIDs()
        XCTAssertEqual(afterOff, [])
    }

    // MARK: B2 quiet hours

    func testPatternAlertsNeverFireInsideQuietHours() async {
        setQuietHours(enabled: true, start: 22, end: 7)
        let prefs = ProAlertPreferenceValues.current()
        await ProactiveAlertsEngine.reschedulePatternNotifications(clusters: [
            cluster(weekday: 3, startHour: 3),  // would fire Tue 02:00
            cluster(weekday: 2, startHour: 7),  // would fire Mon 06:00
            cluster(weekday: 2, startHour: 12), // fires Mon 11:00
        ])
        let pending = await pendingPatternRequests()
        for request in pending {
            let fire = fireDate(request)
            XCTAssertNotNil(fire)
            if let fire { XCTAssertFalse(prefs.isQuietHour(at: fire), "\(request.identifier) fires at \(fire) inside quiet hours") }
        }
        XCTAssertEqual(pending.map(\.identifier), ["pattern-alert-2-12"], "a daytime pattern still schedules")
    }

    func testQuietHoursOffKeepsNightPatternAlerts() async {
        setQuietHours(enabled: false)
        await ProactiveAlertsEngine.reschedulePatternNotifications(clusters: [cluster(weekday: 3, startHour: 3)])
        let pending = await pendingPatternRequests()
        XCTAssertEqual(pending.count, 1)
        let fire = pending.first.flatMap(fireDate)
        XCTAssertEqual(fire.map { cal.component(.weekday, from: $0) }, 3)
        XCTAssertEqual(fire.map { cal.component(.hour, from: $0) }, 2)
    }

    // MARK: B5 midnight window

    func testMidnightClusterFiresOneHourBeforeWindow() async {
        setQuietHours(enabled: false)
        await ProactiveAlertsEngine.reschedulePatternNotifications(clusters: [
            cluster(weekday: 2, startHour: 0),
            cluster(weekday: 1, startHour: 0),
        ])
        let pending = await pendingPatternRequests()
        XCTAssertEqual(pending.count, 2)
        for request in pending {
            guard let fire = fireDate(request) else { return XCTFail("no trigger date for \(request.identifier)") }
            let windowStart = fire.addingTimeInterval(3600)
            let expectedWeekday = request.identifier == "pattern-alert-2-0" ? 2 : 1
            XCTAssertEqual(cal.component(.weekday, from: windowStart), expectedWeekday, "\(request.identifier) fires at \(fire)")
            XCTAssertEqual(cal.component(.hour, from: windowStart), 0, "\(request.identifier) fires at \(fire)")
        }
    }

    // MARK: B3 undo

    func testUndoRemovesPatternNotificationTheLogCreated() async throws {
        enablePatternAlertsAsPro()
        let context = try makeContext()
        insert(baseline, into: context)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let before = await pendingPatternIDs()
        XCTAssertEqual(before, [], "precondition: 7 events, no pattern")

        let captured = event(day: 19, hour: 15)
        context.insert(captured)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let afterLog = await pendingPatternIDs()
        XCTAssertEqual(afterLog, ["pattern-alert-2-15"], "precondition: the log created a pattern alert")

        let coordinator = CaptureCoordinator()
        coordinator.lastCapturedEventID = captured.id
        coordinator.undoLastCapture(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HeadacheEvent>()).count, 7, "precondition: undo deleted the log")
        let afterUndo = await pendingPatternIDs(settlingTo: [])
        XCTAssertEqual(afterUndo, [], "undo leaves no alert for the pattern it removed")
    }

    func testUndoOfSeventhLogRemovesAlertForAnotherDay() async throws {
        enablePatternAlertsAsPro()
        let context = try makeContext()
        insert([(5, 15), (12, 15), (19, 15), (6, 9), (7, 10), (8, 11)], into: context)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let beforeLog = await pendingPatternIDs()
        XCTAssertEqual(beforeLog, [], "precondition: 6 events, analysis off")

        let seventh = event(day: 22, hour: 20) // Thursday 20:05
        context.insert(seventh)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let afterLog = await pendingPatternIDs()
        XCTAssertEqual(afterLog, ["pattern-alert-2-15"], "precondition: the Thursday log scheduled the Monday alert")

        let coordinator = CaptureCoordinator()
        coordinator.lastCapturedEventID = seventh.id
        coordinator.undoLastCapture(in: context)
        let afterUndo = await pendingPatternIDs(settlingTo: [])
        XCTAssertEqual(afterUndo, [], "alert built on 7 logs is gone with 6 logs left")
    }

    // MARK: B4 History delete

    func testHistoryDeleteRemovesPatternNotificationItNoLongerSupports() async throws {
        enablePatternAlertsAsPro()
        let context = try makeContext()
        insert(baseline, into: context)
        let third = event(day: 19, hour: 15)
        context.insert(third)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let before = await pendingPatternIDs()
        XCTAssertEqual(before, ["pattern-alert-2-15"], "precondition: pattern alert pending")

        XCTAssertTrue(HistoryView.delete([third], in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<HeadacheEvent>()).count, 7, "precondition: delete committed")
        let after = await pendingPatternIDs(settlingTo: [])
        XCTAssertEqual(after, [], "delete leaves no alert for the pattern it removed")
    }

    // MARK: B9 Pro lapse

    func testBackgroundRunAfterLapseCancelsPatternAlert() async throws {
        enablePatternAlertsAsPro()
        defaults.set(true, forKey: HeadacheStorageKey.proAlertsEnabled.rawValue)
        let context = try makeContext()
        insert([(5, 15), (12, 15), (19, 15), (6, 9), (7, 10), (8, 11), (9, 12), (10, 13)], into: context)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let scheduled = await pendingPatternIDs()
        XCTAssertEqual(scheduled, ["pattern-alert-2-15"], "precondition: Pro schedules the Monday alert")

        let expired = EntitlementInfo(
            identifier: RevenueCatConfig.proEntitlement, isActive: false, willRenew: false, periodType: .normal,
            latestPurchaseDate: .now.addingTimeInterval(-40 * 86_400), originalPurchaseDate: .now.addingTimeInterval(-40 * 86_400),
            expirationDate: .now.addingTimeInterval(-3_600), store: .appStore, productIdentifier: HeadacheProProduct.monthly,
            isSandbox: true, ownershipType: .purchased
        )
        StoreService.shared.apply(customerInfo: CustomerInfo(
            entitlements: EntitlementInfos(entitlements: [RevenueCatConfig.proEntitlement: expired]),
            requestDate: .now, firstSeen: .now, originalAppUserId: "fixes-lapse"
        ))
        XCTAssertFalse(StoreService.shared.isProUnlocked, "precondition: Pro lapsed")
        XCTAssertFalse(StoreService.shared.entitlementCheckFailed, "precondition: the check did not fail")

        let fired = await ProactiveAlertsEngine.runIfEligible()
        XCTAssertFalse(fired)
        let afterBackground = await pendingPatternIDs()
        XCTAssertEqual(afterBackground, [], "the background run that sees non-Pro cancels pattern alerts")
    }

    // MARK: B7 forecast location

    private func clearCachedLocation() {
        [HeadacheStorageKey.lastKnownLatitude, .lastKnownLongitude, .lastKnownLocationCapturedAt]
            .forEach { defaults.removeObject(forKey: $0.rawValue) }
    }

    func testForecastLocationIsCachedWhenAllowedButMissing() async {
        clearCachedLocation()
        await EnvironmentService.cacheForecastLocationIfMissing(isAuthorized: true) {
            CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        }
        let cached = CachedLocation.current()
        XCTAssertEqual(cached?.latitude, 47.6)
        XCTAssertEqual(cached?.longitude, -122.3)
    }

    func testForecastLocationKeepsExistingAndNeedsPermission() async {
        clearCachedLocation()
        var calls = 0
        await EnvironmentService.cacheForecastLocationIfMissing(isAuthorized: false) {
            calls += 1
            return CLLocationCoordinate2D(latitude: 1, longitude: 1)
        }
        XCTAssertNil(CachedLocation.current(), "no permission, no fetch")

        CachedLocation.save(latitude: 10, longitude: 20)
        await EnvironmentService.cacheForecastLocationIfMissing(isAuthorized: true) {
            calls += 1
            return CLLocationCoordinate2D(latitude: 1, longitude: 1)
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(CachedLocation.current()?.latitude, 10, "a stored coordinate is kept")
    }
}
