// Repro suite for state-machines-2026-11-06.md. Not part of any target.
// To run: copy into HeadacheLoggerTests/StateMachineAuditRepro.swift, run `xcodegen generate`, then
// gh-sim test --scheme HeadacheLogger --only HeadacheLoggerTests/StateMachineAuditRepro
// Expected: 1 pass (control), 5 fail (B1 to B5).
import ObjectiveC
import SwiftData
import UserNotifications
import XCTest
@testable import OneTapHeadacheTracker

/// State machine audit repro suite (2026-11-06). Failing tests are expected: each
/// failure is a claim in project-docs/audits/state-machines-2026-11-06.md.
/// Run 1 showed the real UNUserNotificationCenter rejects add() while permission is
/// undecided (0 pending after every schedule). So the scheduling tests put a recording
/// fake behind the center (ObjC method replacement, inside this test file only); the
/// permission test uses the real center. Also uses the DEBUG Pro override on
/// StoreService.shared, an in-memory SwiftData store and the real
/// CaptureCoordinator.undoLastCapture.
final class NotificationFake: @unchecked Sendable {
    static let shared = NotificationFake()
    private let lock = NSLock()
    private var stored: [UNNotificationRequest] = []
    private var originals: [(Method, IMP)] = []

    var requests: [UNNotificationRequest] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func install() {
        uninstall()
        lock.lock(); stored = []; lock.unlock()
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
        replace(cls, "addNotificationRequest:withCompletionHandler:", add)
        replace(cls, "getPendingNotificationRequestsWithCompletionHandler:", pending)
        replace(cls, "removePendingNotificationRequestsWithIdentifiers:", remove)
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

@MainActor
final class StateMachineAuditRepro: XCTestCase {
    private let defaults = HeadacheAppGroup.userDefaults
    private var saved: [String: Any?] = [:]
    private let cal = Calendar.current

    private var touchedKeys: [HeadacheStorageKey] {
        [.patternAlertsEnabled, .patternAlertSensitivity, .proAlertQuietHoursEnabled,
         .proAlertQuietStartHour, .proAlertQuietEndHour]
    }

    override func setUp() async throws {
        try await super.setUp()
        for key in touchedKeys { saved[key.rawValue] = defaults.object(forKey: key.rawValue) }
    }

    override func tearDown() async throws {
        NotificationFake.shared.uninstall()
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

    private func useFakeCenter() { NotificationFake.shared.install() }

    private func pendingPatternRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("pattern-alert-") }
    }

    private func fireDate(_ request: UNNotificationRequest) -> Date? {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }

    private func describe(_ date: Date?) -> String {
        guard let date else { return "nil" }
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return "\(f.string(from: date)) (weekday \(cal.component(.weekday, from: date)), hour \(cal.component(.hour, from: date)))"
    }

    private func cluster(weekday: Int, startHour: Int) -> ProactiveAlertsEngine.PatternCluster {
        ProactiveAlertsEngine.PatternCluster(
            weekdayIndex: weekday, weekdayName: "Monday", startHour: startHour,
            endHour: startHour, headacheCount: 4, totalHeadaches: 10
        )
    }

    private func event(day: Int, hour: Int) -> HeadacheEvent {
        // Oct 5 2026 is a Monday.
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 5))!
        return HeadacheEvent(timestamp: date)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([HeadacheEvent.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    /// Seven events where no weekday/hour bucket reaches the 3-event minimum
    /// (Monday 15:00 has two).
    private func insertBaselineEvents(_ context: ModelContext) {
        [(5, 15), (12, 15), (6, 9), (7, 10), (8, 11), (9, 12), (10, 13)].forEach {
            context.insert(event(day: $0.0, hour: $0.1))
        }
    }

    private func enablePatternAlertsAsPro() {
        #if DEBUG
        StoreService.shared.activateScreenshotPro()
        #endif
        defaults.set(true, forKey: HeadacheStorageKey.patternAlertsEnabled.rawValue)
        defaults.set(1.0, forKey: HeadacheStorageKey.patternAlertSensitivity.rawValue)
    }

    // MARK: B1/B2 trigger time

    func testControlDaytimeClusterFiresOneHourBeforeWindow() async {
        useFakeCenter()
        await ProactiveAlertsEngine.reschedulePatternNotifications(clusters: [cluster(weekday: 2, startHour: 12)])
        let pending = await pendingPatternRequests()
        XCTAssertEqual(pending.count, 1, "precondition: one pending pattern request")
        let fire = pending.first.flatMap(fireDate)
        XCTAssertNotNil(fire, "precondition: calendar trigger has a next date")
        guard let fire else { return }
        XCTAssertEqual(cal.component(.weekday, from: fire), 2, describe(fire))
        XCTAssertEqual(cal.component(.hour, from: fire), 11, describe(fire))
    }

    /// Promise: ProactiveAlertsEngine.swift:667 "Notifications fire 1 hour before the predicted headache window."
    func testMidnightClusterFiresOneHourBeforeWindow() async {
        useFakeCenter()
        await ProactiveAlertsEngine.reschedulePatternNotifications(clusters: [cluster(weekday: 2, startHour: 0)])
        let pending = await pendingPatternRequests()
        XCTAssertEqual(pending.count, 1, "precondition: one pending pattern request")
        let fire = pending.first.flatMap(fireDate)
        XCTAssertNotNil(fire, "precondition: calendar trigger has a next date")
        guard let fire else { return }
        // One hour after the fire time must be Monday 00:00 (weekday 2).
        let windowStart = fire.addingTimeInterval(3600)
        XCTAssertEqual(
            cal.component(.weekday, from: windowStart), 2,
            "Monday 00:xx window notified at \(describe(fire)); window start would be \(describe(windowStart))"
        )
    }

    /// Promise: ProAlertsConfigView.swift Quiet hours section, toggle "Don't alert at night".
    func testPatternAlertRespectsQuietHours() async {
        useFakeCenter()
        defaults.set(true, forKey: HeadacheStorageKey.proAlertQuietHoursEnabled.rawValue)
        defaults.set(22, forKey: HeadacheStorageKey.proAlertQuietStartHour.rawValue)
        defaults.set(7, forKey: HeadacheStorageKey.proAlertQuietEndHour.rawValue)
        let prefs = ProAlertPreferenceValues.current()
        XCTAssertTrue(prefs.quietHoursEnabled, "precondition")

        await ProactiveAlertsEngine.reschedulePatternNotifications(clusters: [cluster(weekday: 3, startHour: 3)])
        let pending = await pendingPatternRequests()
        XCTAssertEqual(pending.count, 1, "precondition: one pending pattern request")
        guard let fire = pending.first.flatMap(fireDate) else {
            return XCTFail("precondition: trigger has a next date")
        }
        XCTAssertFalse(prefs.isQuietHour(at: fire), "pattern alert scheduled for \(describe(fire)) inside quiet hours 22:00-07:00")
    }

    // MARK: B3 stale notification after undo / delete

    /// Promise: pattern body states "N% of your headaches fall on ..."; the log that created the
    /// pattern was undone (CaptureCoordinator.undoLastCapture).
    func testUndoRemovesPatternNotificationTheLogCreated() async throws {
        useFakeCenter()
        enablePatternAlertsAsPro()
        XCTAssertTrue(StoreService.shared.isProUnlocked, "precondition: Pro override active (DEBUG build)")
        let context = try makeContext()
        insertBaselineEvents(context)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let before = await pendingPatternRequests()
        XCTAssertEqual(before.count, 0, "precondition: 7 events, no cluster, nothing pending")

        // The 3rd Monday 15:00 log, then what CaptureCoordinator runs at the end of a capture.
        let captured = event(day: 19, hour: 15)
        context.insert(captured)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let afterLog = await pendingPatternRequests()
        XCTAssertEqual(afterLog.count, 1, "precondition: the log created a pattern notification")

        let coordinator = CaptureCoordinator()
        coordinator.lastCapturedEventID = captured.id
        coordinator.undoLastCapture(in: context)
        let remaining = try context.fetch(FetchDescriptor<HeadacheEvent>())
        XCTAssertEqual(remaining.count, 7, "precondition: undo deleted the log")
        XCTAssertTrue(
            ProactiveAlertsEngine.analyzeTimePatterns(events: remaining, sensitivity: 1.0).isEmpty,
            "precondition: remaining data supports no pattern"
        )

        let afterUndo = await pendingPatternRequests()
        XCTAssertEqual(
            afterUndo.count, 0,
            "pending after undo: \(afterUndo.map { "\($0.identifier): \(($0.content.body))" })"
        )

        // Control: the engine itself reconciles when it is called again (what a foreground does).
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let afterForeground = await pendingPatternRequests()
        XCTAssertEqual(afterForeground.count, 0, "control: rerun clears it")
    }

    /// Same, via History swipe-delete (HistoryView.commitDelete: context.delete + save).
    func testHistoryDeleteRemovesPatternNotificationItNoLongerSupports() async throws {
        useFakeCenter()
        enablePatternAlertsAsPro()
        XCTAssertTrue(StoreService.shared.isProUnlocked, "precondition: Pro override active (DEBUG build)")
        let context = try makeContext()
        insertBaselineEvents(context)
        let third = event(day: 19, hour: 15)
        context.insert(third)
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let before = await pendingPatternRequests()
        XCTAssertEqual(before.count, 1, "precondition: pattern notification pending")

        context.delete(third)
        try context.save()
        let remaining = try context.fetch(FetchDescriptor<HeadacheEvent>())
        XCTAssertEqual(remaining.count, 7, "precondition: delete committed")
        XCTAssertTrue(ProactiveAlertsEngine.analyzeTimePatterns(events: remaining, sensitivity: 1.0).isEmpty,
                      "precondition: remaining data supports no pattern")

        let after = await pendingPatternRequests()
        XCTAssertEqual(after.count, 0, "pending after delete: \(after.map { $0.content.body })")
    }

    // MARK: B4 permission

    /// Promise: ProAlertsConfigView footer "...sends a heads-up about an hour before you'd typically get one."
    /// Real center (no fake): shows what the OS does while permission is undecided.
    func testEnablingPatternAlertsAsksForNotificationPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let initial = await center.notificationSettings().authorizationStatus
        XCTAssertEqual(initial, .notDetermined, "precondition: permission undecided (raw \(initial.rawValue))")

        // Control: what the OS itself does with a direct add while undecided.
        let probe = UNMutableNotificationContent()
        probe.title = "probe"
        let probeRequest = UNNotificationRequest(
            identifier: "pattern-alert-probe", content: probe,
            trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 3, minute: 0), repeats: false)
        )
        var addError: Error?
        do { try await center.add(probeRequest) } catch { addError = error }
        NSLog("AUDIT direct add while undecided: error=%@", String(describing: addError))
        center.removePendingNotificationRequests(withIdentifiers: ["pattern-alert-probe"])

        enablePatternAlertsAsPro()
        let context = try makeContext()
        insertBaselineEvents(context)
        context.insert(event(day: 19, hour: 15))
        try context.save()
        let events = try context.fetch(FetchDescriptor<HeadacheEvent>())
        XCTAssertEqual(
            ProactiveAlertsEngine.analyzeTimePatterns(events: events, sensitivity: 1.0).count, 1,
            "precondition: data supports one pattern"
        )
        // ProAlertsConfigView's "Predict from your patterns" toggle runs exactly this.
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let pending = await pendingPatternRequests()
        let status = await center.notificationSettings().authorizationStatus
        XCTAssertNotEqual(status, .notDetermined, "toggle on, \(pending.count) alert(s) pending, direct add error \(String(describing: addError)), permission still undecided")
        XCTAssertEqual(pending.count, 1, "alert pending after toggle on (permission raw \(status.rawValue), direct add error \(String(describing: addError)))")
    }
}
