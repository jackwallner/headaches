# Review of the state machine audit, 2026-11-06

Independent review of `state-machines-2026-11-06.md` and its repro suite. Every claim was re-derived from the code at `b874125` (app code identical to the audited `1bfee47`; `git diff 1bfee47 HEAD` touches only the three audit docs). No app code was changed.

**Summary: 9 claims. 9 CONFIRMED, 0 NOT A BUG, 0 UNVERIFIED. False-positive rate 0/9. One stated route loses nothing and was replaced (B7), three impacts were misjudged (B3 and B9 understated, B7 overstated on its own route), and two repro tests encode a fix choice rather than only the bug (B1, B2). 7 of 9 are proved by a failing test; B6 and B7 rest on code that leaves no other path.**

Test run: `gh-sim test --scheme HeadacheLogger --only HeadacheLoggerTests/StateMachineAuditRepro --only HeadacheLoggerTests/StateMachineReviewChecks`, run id `headaches@20261106-211628-9b57-claude-mbpro30343-1106-212330-29027` (GitHub run 42342538489), Xcode 27.1, iPhone 17, iOS 27.2 simulator. Result: 1 passed, 8 failed, and every failure is the bug assertion, never a precondition or control.

- Audit repro, rerun once: same outcome as recorded. Control `testControlDaytimeClusterFiresOneHourBeforeWindow` passes; B1 fails (status still `notDetermined`, 0 pending, direct add error `UNErrorDomain Code=2003`); B2 fails (alert at Tue 02:00 inside 22:00-07:00); B3 fails (`pattern-alert-2-15` pending after undo, rerun control clears it); B4 fails (alert pending after delete); B5 fails (Monday 00:xx window notified Mon 23:00).
- Review checks: `testB8ProductsPublishBeforeIntroEligibility` fails (products published while eligibility was empty; control shows eligibility lands afterwards); `testB9BackgroundRunAfterLapseLeavesPatternAlert` fails (`runIfEligible` returns at the Pro gate, alert still pending; foreground control cancels it); `testB3UndoOfSeventhLogLeavesAlertForAnotherDay` fails (Monday alert scheduled by a Thursday 7th log stays after its undo).

## Claims

Devices: every claim is on the iPhone app (any iPhone on iOS 17+, folded or unfolded Duo alike). Pattern and forecast alerts are local notifications scheduled on the phone. None needs the watch or the widget, though a widget or watch log ends in the same `CaptureCoordinator` path.

| id | verdict | user route (checked against the views) | impact | evidence |
|---|---|---|---|---|
| B1 | CONFIRMED | Pro user. Settings > Headache Pro row (a NavigationLink only when Pro, SettingsView.swift:35-39) or Patterns > Proactive Alerts card (InsightsView.swift:102, :479) > leave "Enable Proactive Alerts" off > turn on "Predict from your patterns". Notifications never asked. Needs a cluster to exist (default "High chance only": 5 logs in one weekday-hour and 30% of all logs, ProactiveAlertsEngine.swift:604-605; "Any chance": 3 and 15%) | Every Pro user who uses only the pattern toggle. Nothing in onboarding asks for notifications (the only `requestAuthorization` calls are ProAlertsConfigView.swift:277, :287 and ProactiveAlertsEngine.swift:343), so permission is undecided for them by default. The paid feature schedules nothing, forever. Audit overstates "nothing says so": the Status row reads "Needs permission" (ProAlertsConfigView.swift:206-213), but it has no button, the banner needs the master toggle (:254) and Send Test Alert is disabled (:63), so the only way to grant is to also enable forecast alerts | `schedulePatternAlertsIfEnabled` (ProactiveAlertsEngine.swift:737-753) never checks or requests authorization; `try? await center.add` (:703) swallows the refusal. Toggle `onChange` only calls `schedulePatterns` (ProAlertsConfigView.swift:149-152, :186-188). Footer promise at :167. Repro `testEnablingPatternAlertsAsksForNotificationPermission` (see test results) |
| B2 | CONFIRMED | Pro, notifications allowed, pattern toggle on, quiet hours at default (on, 22 to 7, ProAlertPreferences.swift:22-29). Logs cluster in a bucket whose start hour is 23 or 0 to 7. The commonest case is migraine on waking logged at 7:xx, which notifies at 6:00 | Pro pattern-alert users with a night or early-morning cluster: a sound notification inside hours they set as quiet, every week the cluster holds (each foreground schedules the next one). Ranked second | `reschedulePatternNotifications` (ProactiveAlertsEngine.swift:668-705) never calls `isQuietHour`; the forecast path does (:80-81). The promise is the unqualified toggle "Don't alert at night" (ProAlertsConfigView.swift:122) on the same screen. The audit's second citation (:79 "Respect quiet hours at fire time") sits inside the forecast-only `runIfEligible`, so it shows design intent for forecast alerts, not a promise about pattern alerts. Repro `testPatternAlertRespectsQuietHours` |
| B3 | CONFIRMED | Pro, pattern toggle on, notifications allowed. Home > Headache button > wait for the capture to finish (the Undo bar only appears once `isCapturing` goes false, HomeView.swift:229-238, after the reschedule at CaptureCoordinator.swift:172 has run) > Undo within 15 s (HomeView.swift:31) > do not reopen the app before the alert | Audit route (the log that tips its own bucket) leaves an alert about 7 days out, so it fires only if the app stays closed a week. A worse route the audit missed: the 7th log enables analysis at all (`patternMinimumEvents`, ProactiveAlertsEngine.swift:595, :600), so undoing a 7th log on any day leaves an alert for an older cluster that can fire within hours. Cost: a notification quoting a share of "your headaches" the data no longer supports | `undoLastCapture` (CaptureCoordinator.swift:245-267) deletes and saves with no reschedule. Repro `testUndoRemovesPatternNotificationTheLogCreated`; review check `testB3UndoOfSeventhLogLeavesAlertForAnotherDay` |
| B4 | CONFIRMED | History tab > swipe to delete (`.onDelete`, HistoryView.swift:271); entries under 7 days old delete at once, older ones confirm (HistoryView.swift:35, :428-442) > leave the app | Same population as B3, but the deleted entry can be old, so the stale alert can be for any cluster and fire within hours. The Edit sheet (EditEventSheet.swift:73-99) and CSV import have the same gap; the audit lists them in its M1 table but does not count them | `commitDelete` (HistoryView.swift:450-464) saves with no reschedule; the root `onChange(of: events.count)` only syncs daily records (HeadacheLoggerApp.swift:293-302). Repro `testHistoryDeleteRemovesPatternNotificationItNoLongerSupports` calls `context.delete` + `save` directly, which is exactly what `commitDelete` does |
| B5 | CONFIRMED | As B2, with 3+ logs (Any chance) or 5+ (default) between 00:00 and 00:59 on one weekday | Small population (midnight-hour cluster), but every alert they get is wrong: it fires at 23:00 on the cluster's own weekday, 23 hours after the window, and it is also in quiet hours | `triggerHour = ... : 23` keeps `cluster.weekdayIndex` (ProactiveAlertsEngine.swift:675-678); promise in the doc comment :667 and the footer ProAlertsConfigView.swift:167. Repro `testMidnightClusterFiresOneHourBeforeWindow` |
| B6 | CONFIRMED (code leaves no doubt) | Pro. Proactive Alerts > master toggle on > Don't Allow > banner "Notifications are off..." > Open iPhone Settings > allow notifications (granting does not terminate the app) > switch back. The pushed screen is still mounted | One-time per Pro user who denied once; they see "Off in Settings" and the banner after fixing it, and may toggle off and on or give up. Alerts themselves work, since the engine reads live status | Statuses refresh only in `.task` (ProAlertsConfigView.swift:174-178), `requestPermissionsIfNeeded` (:273-281) and `sendTestAlert` (:283-312). `.task` does not rerun on app foreground; the file has no `scenePhase` or `didBecomeActive` observer, unlike SettingsView.swift:194. A UI test (deny, `simctl privacy grant`, foreground, read the banner) would show it, but SwiftUI's `.task` lifecycle settles it |
| B7 | CONFIRMED, route corrected | The audit's route (deny location, log, grant later) loses nothing: with no stored coordinate no day ever gets weather (backfill needs `CachedLocation`, HeadacheLoggerApp.swift:384; events logged without location are not `.captured`), so the personal-signal gate already blocks forecast alerts and the screen says so ("Keep logging...", ProAlertsConfigView.swift:84-86). The route that loses alerts: fresh install, allow location in onboarding, import a CSV whose rows carry weather (`environment_status` defaults to captured, ImportService.swift:219; `DailyRecordStore` credits it, DailyRecordStore.swift:199-206), Pro, master toggle on, no new log yet | Narrow (users who move phones by CSV and then do not log). The screen shows "Forecast location: Ready" and a supported signal, but no forecast alert can fire until the next capture writes a coordinate. Insights "Today's risk" shows the missing location (InsightsView.swift:182-185), so the two screens disagree | Row maps permission to "Ready" (ProAlertsConfigView.swift:215-223); engine returns without a coordinate (ProactiveAlertsEngine.swift:77); the only writer is a capture (EnvironmentService.swift:110). Not run as a test: the import route needs a CSV with enough weather days to clear the signal thresholds; the code path itself has no branch that could make it pass |
| B8 | CONFIRMED | Free user with at least one log who has not seen the trial offer (first log happened while `hasTrialOffer` was false, for example offline or products not loaded) cold-launches the app | The `onChange(of: products.count)` trigger (HeadacheLoggerApp.swift:281-285) can never succeed on a device: `fetchProducts` publishes `products` (StoreService.swift:445) and then awaits eligibility (:447, :581-591) after resetting it to empty (:426), so the trigger always reads `hasTrialOffer == false` (HeadacheLoggerApp.swift:173-181). The pitch then depends on `hasResolvedEntitlements` (:286-292) landing after eligibility; the two fetches are independent tasks (StoreService.swift:411-412), and the product path is the longer one (offerings, StoreKit products, eligibility) against one customer-info request. So the existing-user pitch is likely lost on many launches, not only slow ones. The Patterns tab second touch recovers it later. Revenue path. On the simulator without a key, `fetchSimulatorProducts` sets both in one turn (StoreService.swift:535-556), which is why simulator runs never show it | Review check `testB8ProductsPublishBeforeIntroEligibility` (mock `RevenueCatClient` that holds eligibility) |
| B9 | CONFIRMED, impact understated | Pro subscriber with pattern alerts and a cluster; subscription lapses; app not opened before the pending alert's time | Lapsed Pro users with pattern alerts: one more Pro alert per cluster, up to 7 days. The audit says "until the app is next opened", but the background refresh task keeps running after the lapse (it re-queues itself, BackgroundRefreshService.swift:41), learns the user is not Pro (ProactiveAlertsEngine.swift:72-73) and still leaves the alert. Opening the app may not clear it either: `start()` applies the cached `CustomerInfo` in `App.init` (HeadacheLoggerApp.swift:37, StoreService.swift:409-413) and the `scenePhase == .active` reschedule (HeadacheLoggerApp.swift:253-257) can run on that cached Pro state; no `onChange(of: isProUnlocked)` cancels (:263-280). Whether a cached post-expiry `CustomerInfo` still reads active is UNVERIFIED (RevenueCat computes `isActive` against the response's request date) | `schedulePatternAlertsIfEnabled` is the only canceller for non-Pro (ProactiveAlertsEngine.swift:745-747) and runs only on capture, foreground and the config view. Review check `testB9BackgroundRunAfterLapseLeavesPatternAlert` |

## Ranked list of what survived

1. **B1** pattern alerts silently never schedule for users who never enabled forecast alerts. Largest Pro population, total loss of a paid feature.
2. **B2** pattern alerts ignore quiet hours. Recurs weekly for anyone with a morning-on-waking cluster.
3. **B4** History delete (and Edit, CSV import) leave a stale pattern alert, which can fire within hours.
4. **B3** Undo leaves a stale pattern alert; the 7th-log case fires within hours.
5. **B8** existing-user trial pitch trigger is dead on devices; the pitch survives only when entitlements resolve after eligibility. Free users, revenue.
6. **B5** midnight-hour cluster notified 23 hours late, every week.
7. **B6** stale permission banner after granting in iOS Settings.
8. **B9** pattern alert survives a Pro lapse, including through background runs.
9. **B7** "Forecast location: Ready" without a coordinate; costs alerts only on the import route.

Changes from the audit's order: the audit ranked proved bugs ahead of code-path bugs, which is a ranking by evidence, not by impact. B4 moves above B3 because a deleted entry can be old and its alert near. B8 moves above B5 and B6 because it reaches free users on the revenue path.

## Product calls

All five hold as product calls (no user-facing promise): equal quiet-hour bounds (ProAlertPreferences.swift:77), the 6-hour forecast gap (ProactiveAlertsEngine.swift:21), the self-re-queuing background task (BackgroundRefreshService.swift:41), the Edit sheet keeping original weather and allowing future dates (EditEventSheet.swift:24-28, :76-84), and `.pending` treated as success (OnboardingView.swift:324, PaywallView.swift:338). The background task point is worth more weight than "product call": combined with B9 it is the one process that runs after a lapse and could clean up.

## Method changes

- **Rank by users times cost, not by proof status.** The audit sorted proved bugs first, which put B8 (free users, revenue) below Pro-only edge cases.
- **Write tests that pass after a correct fix.** The B1 test asserts permission is no longer `.notDetermined` and that an alert is pending; no fix can make an unattended test answer a system prompt, so it fails forever. The B2 test requires exactly one pending request, so a fix that skips a quiet-hour alert instead of moving it fails its precondition. Assert the invariant (no pending alert inside quiet hours; the toggle requests authorization through an injected scheduler), not the auditor's preferred fix.
- **Walk the impact of each route, not only its reachability.** B7's stated route loses no alert because another gate already blocks it; B3's stated route needs a week of not opening the app while a nearer route existed; B9's "until next opened" ignored the background task. Each was visible from one more call site.
- **Check simulator-only branches before trusting a sim run.** `StoreService` takes a different product path on an unconfigured simulator, which hides B8 entirely; the existing `RevenueCatClient` seam reaches the device path.
- **Keep labels consistent.** The repro file's MARK headers (`B1/B2 trigger time`, `B4 permission`) do not match the audit's ids.

## Review tests

`StateMachineReviewChecks` (below) and the audit's `StateMachineAuditRepro` were copied into `HeadacheLoggerTests`, run once, then removed. The checks need `NotificationFake` from the repro file in the same target.

```swift
// Temporary review checks for project-docs/audits/state-machines-2026-11-06-review.md.
// Needs StateMachineAuditRepro.swift (NotificationFake) in the same target.
import SwiftData
import UserNotifications
import XCTest
import RevenueCat
@testable import OneTapHeadacheTracker

@MainActor
private final class GatedEligibilityClient: RevenueCatClient {
    var cachedCustomerInfo: CustomerInfo?
    var offering: Offering?
    private(set) var eligibilityRequested = false
    private var released = false
    private var gate: CheckedContinuation<Void, Never>?

    func customerInfo(fetchPolicy: CacheFetchPolicy) async throws -> CustomerInfo { throw URLError(.notConnectedToInternet) }
    func paywallOffering(forceRefresh: Bool) async throws -> Offering? { offering }
    func purchase(package: Package) async throws -> PurchaseResultData { throw URLError(.cancelled) }
    func restorePurchases() async throws -> CustomerInfo { throw URLError(.cancelled) }
    func introEligibility(productIdentifiers: [String]) async -> [String: IntroEligibilityStatus] {
        eligibilityRequested = true
        if !released { await withCheckedContinuation { gate = $0 } }
        return Dictionary(uniqueKeysWithValues: productIdentifiers.map { ($0, IntroEligibilityStatus.eligible) })
    }
    func release() {
        released = true
        gate?.resume()
        gate = nil
    }
    func setSubscriberAttributes(_ attributes: [String: String]) {}
    func recordImpression(_ params: CustomPaywallImpressionParams) {}
}

@MainActor
final class StateMachineReviewChecks: XCTestCase {
    private let defaults = HeadacheAppGroup.userDefaults
    private var saved: [String: Any?] = [:]
    private let cal = Calendar.current
    private var touchedKeys: [HeadacheStorageKey] { [.patternAlertsEnabled, .patternAlertSensitivity, .proAlertsEnabled] }

    override func setUp() async throws {
        try await super.setUp()
        for key in touchedKeys { saved[key.rawValue] = defaults.object(forKey: key.rawValue) }
    }

    override func tearDown() async throws {
        NotificationFake.shared.uninstall()
        for key in touchedKeys {
            if let value = saved[key.rawValue] ?? nil { defaults.set(value, forKey: key.rawValue) } else { defaults.removeObject(forKey: key.rawValue) }
        }
        try await super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([HeadacheEvent.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func event(day: Int, hour: Int) -> HeadacheEvent {
        // Oct 5 2026 is a Monday.
        HeadacheEvent(timestamp: cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 5))!)
    }

    private func pendingPatternIDs() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix("pattern-alert-") }
    }

    private func enablePatternAlertsAsPro() {
        StoreService.shared.activateScreenshotPro()
        defaults.set(true, forKey: HeadacheStorageKey.patternAlertsEnabled.rawValue)
        defaults.set(1.0, forKey: HeadacheStorageKey.patternAlertSensitivity.rawValue)
    }

    private func trialMonthlyPackage() -> Package {
        let trial = TestStoreProductDiscount(
            identifier: "trial", price: 0, localizedPriceString: "$0.00", paymentMode: .freeTrial,
            subscriptionPeriod: .init(value: 1, unit: .week), numberOfPeriods: 1, type: .introductory
        )
        let product = TestStoreProduct(
            localizedTitle: "Monthly", price: 3.99, currencyCode: "USD", localizedPriceString: "$3.99",
            productIdentifier: HeadacheProProduct.monthly, productType: .autoRenewableSubscription,
            localizedDescription: "Monthly access", subscriptionPeriod: .init(value: 1, unit: .month),
            introductoryDiscount: trial, locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        return Package(identifier: "$rc_monthly", packageType: .monthly, storeProduct: product,
                       offeringIdentifier: "default", webCheckoutUrl: nil)
    }

    /// B8: HeadacheLoggerApp.onChange(of: products.count) re-runs the existing-user trial path,
    /// which requires hasTrialOffer (directTrialPackage needs isEligibleForIntroOffer). On the
    /// configured (device) path, StoreService.fetchProducts publishes products before it awaits
    /// eligibility. This records what that trigger can see.
    func testB8ProductsPublishBeforeIntroEligibility() async throws {
        let client = GatedEligibilityClient()
        client.offering = Offering(identifier: "default", serverDescription: "default",
                                   availablePackages: [trialMonthlyPackage()], webCheckoutUrl: nil)
        let service = StoreService(client: client)
        let fetch = Task { await service.fetchProducts() }
        for _ in 0..<300 where !client.eligibilityRequested {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(client.eligibilityRequested, "precondition: fetchProducts reached the eligibility call")
        XCTAssertEqual(service.products.count, 1, "precondition: products already published (fires onChange(products.count))")
        let package = try XCTUnwrap(service.onboardingTrialPackage, "precondition: the monthly package is the direct trial package")
        XCTAssertNotNil(package.headacheProIntroOfferLabel, "precondition: package carries a free trial")
        let eligibleAtProductsChange = service.isEligibleForIntroOffer(package)
        client.release()
        await fetch.value
        XCTAssertTrue(service.isEligibleForIntroOffer(package), "control: eligibility lands after the products change")
        XCTAssertTrue(eligibleAtProductsChange, "B8: products published while introEligibility was still empty, so the products.count trigger sees hasTrialOffer == false")
    }

    /// B9: subscription lapses, then the BGAppRefreshTask body runs (BackgroundRefreshService.handle
    /// -> ProactiveAlertsEngine.runIfEligible). It learns the user is not Pro; does the pattern alert go?
    func testB9BackgroundRunAfterLapseLeavesPatternAlert() async throws {
        NotificationFake.shared.install()
        enablePatternAlertsAsPro()
        defaults.set(true, forKey: HeadacheStorageKey.proAlertsEnabled.rawValue)
        let context = try makeContext()
        [(5, 15), (12, 15), (19, 15), (6, 9), (7, 10), (8, 11), (9, 12), (10, 13)].forEach {
            context.insert(event(day: $0.0, hour: $0.1))
        }
        try context.save()
        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let scheduled = await pendingPatternIDs()
        XCTAssertEqual(scheduled.count, 1, "precondition: Pro schedules the Monday 15:00 pattern alert")

        let expired = EntitlementInfo(
            identifier: RevenueCatConfig.proEntitlement, isActive: false, willRenew: false, periodType: .normal,
            latestPurchaseDate: .now.addingTimeInterval(-40 * 86_400), originalPurchaseDate: .now.addingTimeInterval(-40 * 86_400),
            expirationDate: .now.addingTimeInterval(-3_600), store: .appStore, productIdentifier: HeadacheProProduct.monthly,
            isSandbox: true, ownershipType: .purchased
        )
        StoreService.shared.apply(customerInfo: CustomerInfo(
            entitlements: EntitlementInfos(entitlements: [RevenueCatConfig.proEntitlement: expired]),
            requestDate: .now, firstSeen: .now, originalAppUserId: "review-lapse"
        ))
        XCTAssertFalse(StoreService.shared.isProUnlocked, "precondition: Pro lapsed")

        let fired = await ProactiveAlertsEngine.runIfEligible()
        XCTAssertFalse(fired, "precondition: background run returns at the Pro gate")
        let afterBackground = await pendingPatternIDs()
        XCTAssertEqual(afterBackground, [], "B9: pattern alert still pending after the background run saw non-Pro")

        await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        let afterForeground = await pendingPatternIDs()
        XCTAssertEqual(afterForeground, [], "control: the foreground path cancels it")
    }

    /// B3 variant: the 7th log turns on pattern analysis (patternMinimumEvents), so an
    /// existing Monday cluster gets scheduled even though the 7th log is on another day.
    /// Undo of that log leaves the alert, which can fire within hours, not a week.
    func testB3UndoOfSeventhLogLeavesAlertForAnotherDay() async throws {
        NotificationFake.shared.install()
        enablePatternAlertsAsPro()
        let context = try makeContext()
        [(5, 15), (12, 15), (19, 15), (6, 9), (7, 10), (8, 11)].forEach {
            context.insert(event(day: $0.0, hour: $0.1))
        }
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
        let remaining = try context.fetch(FetchDescriptor<HeadacheEvent>())
        XCTAssertEqual(remaining.count, 6, "precondition: undo deleted the log")
        let afterUndo = await pendingPatternIDs()
        XCTAssertEqual(afterUndo, [], "B3 variant: alert built on 7 logs still pending with 6 logs left")
    }
}
```
