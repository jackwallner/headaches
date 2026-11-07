# State machine audit, 2026-11-06

Scope: iOS app, shared module, widget, watch. No backend function exists in the repo that the app's entitlements depend on (RevenueCat is a hosted service, read through `StoreService`). Android is out of scope. Audited committed code at `1bfee47` (working tree clean, nothing to stash). No app code was changed.

**Summary: 9 bugs. 5 proved by failing test (B1 to B5), 4 code path only (B6 to B9, not proved).** Plus 5 product calls (not counted).

Test run: `gh-sim test --scheme HeadacheLogger --only HeadacheLoggerTests/StateMachineAuditRepro`, run id `headaches@20261106-191146-cb8b-claude-mbpro33782-1106-200407-2163` (GitHub run 42336784787), Xcode 27.1, iPhone 17, iOS 27.2 simulator. Result: 1 passed (control), 5 failed (B1 to B5). Run 1 (`...-191842-27006`) is not used as evidence: all six tests failed on their own precondition because the real notification center rejects `add` while permission is undecided; that is itself the finding B1, and the suite then put a recording fake behind the center (inside the test file only) for B2 to B5. B1 uses the real center.

Existing test seams used: `StoreService.activateScreenshotPro()` (DEBUG Pro override), in-memory `ModelContainer`, the real `CaptureCoordinator.undoLastCapture`, `ProactiveAlertsEngine.reschedulePatternNotifications` / `schedulePatternAlertsIfEnabled` / `analyzeTimePatterns`, `ProAlertPreferenceValues.isQuietHour`, app-group defaults (saved and restored per test). Seams that exist but were not needed: `RevenueCatClient` mock with constructed `CustomerInfo` (see `PurchaseEntitlementTests`), `ConversionDiagnostics.defaultsOverride`. There is no injected notification scheduler in the app, so the tests use ObjC method replacement on `UNUserNotificationCenter` in the test file.

Scheduler call sites for pattern notifications (complete list, `grep` of the iOS targets): `ProactiveAlertsEngine.reschedulePatternNotifications` (ProactiveAlertsEngine.swift:668, the only `add` at :703 and `remove` at :672), `cancelAllPatternNotifications` (:708), called from `schedulePatternAlertsIfEnabled` (:737). That is called from: CaptureCoordinator.swift:59 (widget/pending enrichment), :172 (capture finish), :241 (retry finish); HeadacheLoggerApp.swift:371 (`schedulePatterns`, on `scenePhase == .active` only); ProAlertsConfigView.swift:187 (toggle and sensitivity `onChange`). No other call site: not Undo (CaptureCoordinator.swift:245), not History delete (HistoryView.swift:450), not the Edit sheet, not CSV import, not an entitlement change. Other notification producers: `ProactiveAlertsEngine.deliver` (:349, immediate, no trigger) and the Settings test alert (ProAlertsConfigView.swift:284). The only `requestAuthorization` calls are ProAlertsConfigView.swift:277 (master toggle), :287 (test alert), ProactiveAlertsEngine.swift:343 (inside the background forecast run).

## Bugs ranked by impact

Ranked within each group by users reached times cost. Proved bugs first.

| id | bug | what the user sees | promise | user route | impact | evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 | "Predict from your patterns" never asks for notification permission and silently schedules nothing when it is undecided or denied | Toggle is on and the footer says alerts are coming; the Notifications row says "Needs permission" with no button; no banner (the banner needs the master toggle); no alert ever arrives | ProAlertsConfigView.swift:167 "notifies you ~1 hour before a headache is likely"; :149 toggle | Settings tab > Headache Pro > Proactive Alerts (Pro only) > leave "Enable Proactive Alerts" off > switch "Predict from your patterns" on, with notifications never allowed or denied. Needs a Pro account with 7 or more logs for a cluster to exist | Every Pro user who turns on only the pattern toggle before allowing notifications (the master toggle is the only place that prompts; Send Test Alert is disabled while it is off). Likely the common path for this toggle, because it sits last on the screen and is independent. The paid feature does nothing and nothing says so. Also: after permission is granted later (master toggle, iOS Settings), nothing is scheduled until the next app foreground or log | Test `testEnablingPatternAlertsAsksForNotificationPermission` FAILS: status rawValue 0 (notDetermined) after the toggle's call, 0 pending; direct `add` error recorded: `UNErrorDomain Code=2003 "Repository could not save notification. Source is not authorized."` | ProactiveAlertsEngine.swift:703 (`try?`), ProAlertsConfigView.swift:149-155, :253-254 |
| B2 | Pattern alerts ignore Quiet hours | A sound notification at night inside the window the user set to "Don't alert at night" | ProAlertsConfigView.swift:122 toggle "Don't alert at night" (default on, 22:00 to 07:00, ProAlertPreferences.swift:23-26); ProactiveAlertsEngine.swift:79 "Respect quiet hours at fire time" (forecast alerts do; pattern alerts do not) | Settings > Headache Pro > Proactive Alerts > Predict from your patterns on, notifications allowed; log headaches that cluster in an hour from 23:00 to 07:59 (for example 3 am, 4 or more logs on the same weekday and hour under "Any chance", or 5 under "High chance only"). Quiet hours left at default | Pro users with pattern alerts and a night or early-morning headache cluster. Early-morning migraine is common; the cost is a woken sleeper per week per cluster | Test `testPatternAlertRespectsQuietHours` FAILS: "pattern alert scheduled for Tue 02:00 (weekday 3, hour 2) inside quiet hours 22:00-07:00". Control `testControlDaytimeClusterFiresOneHourBeforeWindow` passes | ProactiveAlertsEngine.swift:675-701 (no `isQuietHour` call) |
| B3 | Undo leaves the pattern notification the undone log created | Notification arrives saying "38% of your headaches fall on Mondays around 3 pm" built from a log the user undid | ProactiveAlertsEngine.swift:719 body states a share of "your headaches"; CaptureCoordinator.swift:241 reschedules at capture end, Undo has no counterpart (the bar says "Last entry undone.") | Home tab > tap the Headache button as the log that completes a pattern > Undo on the bar within 15 s > leave the app (do not reopen it before the alert time). Pattern alerts on, notifications allowed, Pro | Pro users with pattern alerts who undo a log that tipped a cluster. Undo is a common action, the threshold crossing is not. Stale until the next app open (the foreground repairs it, ProactiveAlertsEngine.swift:681 comment documents capture/foreground as the triggers). Cost: one false alert | Test `testUndoRemovesPatternNotificationTheLogCreated` FAILS: "pending after undo: [pattern-alert-2-15: 38% of your headaches fall on Mondays around 3 pm.]"; preconditions pass (7 events remain, `analyzeTimePatterns` empty); control (rerun of the scheduler) clears it | CaptureCoordinator.swift:245-266 |
| B4 | History delete leaves the pattern notification the deleted entries supported | Same false alert after deleting entries | Same as B3 | History tab > swipe-delete an entry (under 7 days old deletes at once; older asks to confirm) so a cluster drops below the threshold > leave the app | Same population as B3, a more deliberate action | Test `testHistoryDeleteRemovesPatternNotificationItNoLongerSupports` FAILS: "pending after delete: [38% of your headaches fall on Mondays around 3 pm.]"; preconditions pass | HistoryView.swift:450-464 |
| B5 | A cluster starting at 12 am notifies 23 hours after the window starts instead of 1 hour before | Alert for a "12 am" pattern arrives at 11 pm the same weekday, after the headache window | ProactiveAlertsEngine.swift:667 "Notifications fire 1 hour before the predicted headache window"; ProAlertsConfigView.swift:167 | Same as B2, with logs clustering between 00:00 and 00:59 on one weekday | Pro users with a midnight-hour cluster. Small population; the alert is also useless | Test `testMidnightClusterFiresOneHourBeforeWindow` FAILS: "Monday 00:xx window notified at Mon 23:00 (weekday 2, hour 23); window start would be Tue 00:00 (weekday 3, hour 0)". Control (12:00 cluster fires at 11:00 Monday) passes | ProactiveAlertsEngine.swift:675 (`: 23` keeps the same weekday) |
| B6 | Permission banner and rows on Proactive Alerts do not refresh after granting in iOS Settings | "Notifications are off. Alerts can't be delivered until you enable them in Settings." stays after the user enabled them | ProAlertsConfigView.swift:253-266 banner text claims the current state; the Settings screen itself refreshes on `didBecomeActive` (SettingsView.swift:194), this pushed screen does not | Settings > Headache Pro > Proactive Alerts > enable (deny the prompt) > banner > "Open iPhone Settings" > allow notifications > return to the app (screen still mounted) | Pro users who denied once and then fix it, a one-time event per user. Cost: they think it failed, or turn the master toggle off and on. Alerts still work once the app is next active (the engine reads the live status) | Code path. Evidence: `refreshPermissionStatuses` is called only from `.task` (:174), `requestPermissionsIfNeeded` and `sendTestAlert`; grep for `scenePhase`, `didBecomeActive`, `willEnterForeground` in the file returns nothing. Would settle it: a UI test that denies, grants via `simctl privacy`, foregrounds, and reads the banner id | ProAlertsConfigView.swift:174-177, :246-266 |
| B7 | "Forecast location: Ready" is shown from the permission alone; alerts need a stored coordinate that only a capture writes | Ready, but no forecast alert ever fires | ProAlertsConfigView.swift:215-221 maps authorized to "Ready"; ProactiveAlertsEngine.swift:77 returns without a `CachedLocation` | Decline location in onboarding, log some headaches (no coordinate stored), allow While Using in iOS Settings, Pro, Settings > Proactive Alerts > master on. No new log yet | Pro users who allowed location after logging. Fixes itself at the next log or enrichment. Insights "Today's risk" does show a location-missing state (InsightsView.swift:12, :179), so only this screen misstates | Code path. Would settle it: unit test of `runIfEligible` with Pro override, alerts on and no `CachedLocation` keys, versus the row text with authorized status | ProAlertsConfigView.swift:215, ProactiveAlertsEngine.swift:77, EnvironmentService.swift:110 |
| B8 | Existing-user trial offer depends on intro eligibility, but nothing re-evaluates when eligibility arrives | A user with logs who never saw the trial offer does not get it in that session | HeadacheLoggerApp.swift:282-283 comment "Products may load after appear, so re-evaluate the existing-user path so a returning user with logs but no products yet still gets pitched" | Free user with 1 or more logs and trial not yet shown, cold launch with a slow StoreKit eligibility lookup | Free users in the launch where `hasTrialOffer` flips after the last trigger. The Patterns-tab second touch and the next launch recover it, so the cost is a delayed or lost pitch. Revenue path | Code path. `fetchProducts` assigns `products` (StoreService.swift:445, fires `onChange(products.count)`), then awaits `refreshIntroEligibility` (:447, :590) which sets `introEligibility`; `hasTrialOffer` (HeadacheLoggerApp.swift:173-181) needs eligibility, and no `onChange` watches it. Would settle it: log the order of `products`, `introEligibility` and `hasResolvedEntitlements` on a device with a real offering, or a mock `RevenueCatClient` whose `introEligibility` is delayed plus a Combine sink on `$products` | StoreService.swift:425-451, HeadacheLoggerApp.swift:173-181, :281-284 |
| B9 | Pattern notifications keep their pending request after Pro lapses until the app is next opened | A paid-feature alert after the subscription ended | AGENTS.md "Pro ... unlocks ... Proactive Alerts"; `schedulePatternAlertsIfEnabled` cancels when not Pro (ProactiveAlertsEngine.swift:745) but only runs on foreground or capture | Pro subscriber with pattern alerts, subscription expires or trial ends, app not opened before the next alert | Lapsed Pro users with pattern alerts, at most one request per cluster, at most 7 days. Cost: small (a free notification) | Code path. Would settle it: with the fake center, schedule as Pro, flip `StoreService.apply` to a non-Pro `CustomerInfo` (mock client), assert pending is cleared without calling the scheduler | ProactiveAlertsEngine.swift:737-753 |

## Product calls (not counted)

No quoted promise, so not bugs:
- Quiet hours with equal From and Until (both Steppers allow 0 to 23, ProAlertsConfigView.swift:123-137) silently turn quiet hours off while the toggle shows on (ProAlertPreferences.swift:77).
- Forecast alerts can fire every 6 hours (`minNotificationGap`) for one unchanged forecast window.
- The background refresh task re-queues itself forever, also for free users and users with alerts off (BackgroundRefreshService.swift:41), doing a network entitlement fetch each run.
- Editing an entry's date and time (EditEventSheet.swift:76-84) updates weekday, hour and part of day but keeps the weather, sleep, steps and pressure trend captured at the original time; `DailyRecordStore.merged` then credits that weather to the new day, and weather an event contributed stays on its day after the event is deleted or moved. The Edit sheet's DatePicker also allows future dates.
- `.pending` from `StoreService.purchase` is treated as success by onboarding, the root trial sheet and the paywall (OnboardingView.swift:324, HeadacheLoggerApp.swift:557, PaywallView.swift:338). RevenueCat normally throws for a deferred purchase, so it is reachable only when a purchase returns without an entitlement; no Ask to Buy message exists in any case.

Checked and found consistent (no bug): purchase and restore guards and stale `CustomerInfo` ordering (covered by existing `PurchaseEntitlementTests`); promo sheet single-presenter and `foregroundEpoch` guards; review-prompt gating; `DailyRecordStore.merged` re-deriving headache columns after deletes; the watch and widget logging paths (a duplicate watch entry is possible if `sendMessage` errors after delivery, because `requestID` is never used by the phone, but it needs a WCSession error after delivery and could not be reproduced, so it is not claimed).

## Related fixes, in order

1. B1: request notification permission (or show the banner) from the pattern toggle, and reschedule when permission is granted later. Same change gives B6 a place to refresh on foreground.
2. B2 and B5: one trigger-time function used by the scheduler, with the previous-weekday wrap for hour 0 and a quiet-hours check. Test with the existing repro tests.
3. B3 and B4: call `schedulePatternAlertsIfEnabled` after Undo, History delete, Edit, and import; a single `onChange` on the event set in the root view covers all four. Then B9 can be covered by observing `isProUnlocked`.
4. B7 and B8: status rows from real readiness, and an `onChange(of: introEligibility)` re-evaluation.

## State machines

Invariant ids are local to each machine (M1.I1 etc). A transition marked `breaks Mx.Iy` is the reachable bad transition behind the bug id in brackets.

### M1. Pattern alert schedule (pending local notifications `pattern-alert-<weekday>-<startHour>`)

State is spread across: `patternAlertsEnabled` and `patternAlertSensitivity` (app-group defaults), `StoreService.isProUnlocked` (in memory), the event log (SwiftData), the iOS notification authorization status and the OS pending-request list. There is no stored copy of "what is scheduled"; the pending list in `UNUserNotificationCenter` is the only record, and it is rebuilt wholesale by `reschedulePatternNotifications`.

States: `Off` (no pattern requests pending), `Scheduled(clusters)` (one non-repeating request per cluster, next occurrence only), `Stale` (pending requests that no longer match `analyzeTimePatterns(events)`), `Dropped` (toggle on, but iOS refuses `add` because authorization is `notDetermined` or `denied`, so nothing is pending).

Invariants:
- M1.I1 Pending requests equal `analyzeTimePatterns(events, sensitivity)` for the current log whenever the toggle is on and Pro is active.
- M1.I2 Each request fires one hour before its cluster's first hour (ProactiveAlertsEngine.swift:667).
- M1.I3 No request fires inside the user's quiet hours (Quiet hours section, "Don't alert at night").
- M1.I4 With the toggle off or Pro inactive, nothing is pending.
- M1.I5 Turning the toggle on either results in pending requests or the user is asked for permission / told it is off.

| From | Event | To | Code | Breaks |
|---|---|---|---|---|
| Off | toggle on (Pro), notifications undecided or denied | Off (silently) | ProAlertsConfigView:149 -> `schedulePatternAlertsIfEnabled` -> `try? await center.add` (ProactiveAlertsEngine.swift:703) fails, error swallowed | M1.I1, M1.I5 [B1] |
| Off | toggle on (Pro), notifications authorized | Scheduled | same | none |
| Scheduled | capture finishes | Scheduled | CaptureCoordinator:59,172,241 | none |
| Scheduled | Undo of that capture | Stale | `undoLastCapture` has no reschedule | M1.I1 [B3] |
| Scheduled | History swipe delete | Stale | HistoryView `commitDelete` (line 450) | M1.I1 [B4] |
| Scheduled | Edit sheet changes day/hour | Stale | EditEventSheet `save` | M1.I1 (code path) |
| Scheduled | CSV import | Stale | ImportService | M1.I1 (code path) |
| Scheduled | app becomes active | Scheduled | HeadacheLoggerApp:371 | repairs M1.I1 |
| Scheduled | cluster with startHour 0 | Scheduled | `triggerHour = 23` same weekday | M1.I2 [B5] |
| Scheduled | cluster with start 23..7 | Scheduled | no quiet hour check | M1.I3 [B2] |
| Scheduled | Pro lapses while app closed | Scheduled (illegal) | nothing runs until next foreground | M1.I4 [B9] |
| Scheduled | toggle off | Off | `cancelAllPatternNotifications` | none |

### M2. Entitlement (`StoreService`)

State: `customerInfo`, `isProUnlocked`, `hasResolvedEntitlements`, `entitlementCheckFailed`, `isLoadingProducts`, `introEligibility`, `lastCustomerInfoDate`, `purchaseInFlight`.

States: `Unconfigured` (simulator or no key), `Cached` (cached info applied, not resolved), `Resolved(pro|free)`, `CheckFailed` (fetch threw, cached stays), `Purchasing`.

Invariants:
- M2.I1 `isProUnlocked == customerInfo.entitlements.active non-empty`, for the newest accepted `requestDate`.
- M2.I2 Promo surfaces never present before `hasResolvedEntitlements`.
- M2.I3 An older `CustomerInfo` never replaces a newer one.
- M2.I4 Intro eligibility shown equals what Apple will grant.
- M2.I5 `purchase` never double-buys for an active entitlement.

| From | Event | To | Notes |
|---|---|---|---|
| Unconfigured | `start()` with key | Cached or Resolved | `apply(cached)` runs in `App.init`; hasResolved only after explicit fetch |
| Cached | `.fetchCurrent` returns | Resolved | ok |
| Cached | fetch throws | CheckFailed | `hasResolved` stays false; delegate pushes do not resolve it (StoreService:685). `purchase()` retries once |
| CheckFailed | delegate push | CheckFailed | isPro updates, promos stay blocked until next launch or purchase |
| Resolved(free) | `purchase` ok | Resolved(pro) | `.pending` is returned only when no throw and no entitlement |
| any | older info arrives | unchanged | guarded by requestDate (tested in PurchaseEntitlementTests) |
| Resolved | `fetchProducts` | eligibility reset to `[:]` then refilled | window where `isEligibleForIntroOffer` is false while `products` is already set [see Code path B8] |

### M3. Trial / Pro promo sheets (root + onboarding + Home card)

State: `hasSeenProIntro`, `hasSeenTrialOffer`, `hasSeenInsightsTrialOffer` (defaults), `milestone3/5/10PromptShown` (defaults), `activeSheet` (@State), `pendingPaywallAfterTrialDismiss`, `trialPurchaseInFlight`, `firstLogOfferShownThisSession`, `proPromptShownThisSession` (CaptureCoordinator), `foregroundEpoch`.

Invariants:
- M3.I1 At most one promo sheet at a time (single `activeSheet`).
- M3.I2 No promo before entitlements resolve, none for a Pro or recently-Pro account.
- M3.I3 `hasSeen*` flags flip at present time, so a one-shot stays one-shot across kill.
- M3.I4 A delayed presentation never fires across a backgrounding (`foregroundEpoch`).
- M3.I5 Once Pro, all seen flags are true.

| From | Event | To | Notes |
|---|---|---|---|
| none | 1st log (count 0 -> 1) | trialOffer after 4s | evaluateFirstLogTrialOffer; also triggered by Undo then relog and by CSV import into an empty log (count 0 -> N) |
| none | existing user appears/products/resolved | trialOffer after 3s | `hasTrialOffer` needs `introEligibility` which has no trigger [B8] |
| trialOffer | Start trial | purchase | `.purchased` and `.pending` both set seen and dismiss (pending shows no Ask to Buy message; RevenueCat normally throws for deferred, so rare) |
| trialOffer | See all plans | trialPaywall after dismiss | via `onDismiss` chain |
| any | isProUnlocked true | none | flags set, sheet cleared |

### M4. One-tap capture, undo and enrichment (`CaptureCoordinator`)

State: `isCapturing`, `currentRunIsRetry`, `lastCapturedEventID`, `bannerMessage/bannerIsError`, per-event `captureStatus`, `healthStatus`, `environmentStatus`, Home `undoSnackbarVisible`, `showCheckmark`.

Event lifecycle: `pending(pending,pending)` -> `complete | partial | failed`; widget logs start as `unavailable` with sentinel messages and are enriched on foreground.

Invariants:
- M4.I1 Every logged tap is persisted before enrichment (initial save).
- M4.I2 Undo removes the entry and everything derived from it.
- M4.I3 Enrichment uses the event timestamp, never now.
- M4.I4 `isCapturing` is true iff some capture/retry task is running.

| From | Event | To | Breaks |
|---|---|---|---|
| idle | tap | capturing | none |
| capturing | second capture (watch) | capturing | first finisher clears `isCapturing` while second runs (M4.I4, no user-visible effect found) |
| captured | Undo | idle | M4.I2: pattern notifications, review positive-moment count not rolled back [B3] |
| capturing | Undo target deleted mid-flight | error banner | needs a watch tap inside the 15 s Undo window, not claimed |
| pending (killed) | foreground | enrich | `enrichPendingCapturesIfNeeded` |

### M5. Daily baseline (`DailyRecordStore`, daily_records.json)

State: one record per day (headache columns derived from events, weather/sleep columns fetched). Writers: `sync` (root, events.count change and foreground), `Task.detached` backfill (HeadacheLoggerApp `maintainDailyRecordsIfNeeded`), `InsightsView.loadAndBackfillDailyRecords`, `OnboardingView.initializeDailyRecords`.

Invariants:
- M5.I1 Headache columns equal the event log (`merged` re-derives them).
- M5.I2 Fetched weather and sleep are never discarded.
- M5.I3 Writers do not lose each other's updates.

Transitions: delete and undo flip a day back to headache-free (M5.I1 holds, tested in the app's own tests). Editing an event to another day does not change `events.count`, so the root `onChange` does not run `sync`; repair waits for the next foreground (self-healing, not claimed). The detached backfill and `InsightsView` read-modify-write the whole file across network awaits, so a `sync` write in between is overwritten (M5.I3), but the next `sync` re-derives headache columns (self-healing, not claimed). Weather that an event contributed stays on its day after the event is deleted or moved (by design, see Product calls).

### M6. Permission and readiness surfaces (Proactive Alerts screen)

State: notification authorization (`UNAuthorizationStatus`), location authorization string, `CachedLocation` (coordinates stored at last capture), `alertsEnabled`, `patternAlertsEnabled`, view @State `notificationStatus`, `locationStatus`, `permissionsBanner`.

Invariants:
- M6.I1 Shown status equals current OS status.
- M6.I2 "Forecast location: Ready" implies a forecast can be fetched (a cached coordinate exists).
- M6.I3 Any toggle that promises a notification either asks for permission or says it is off.

| From | Event | To | Breaks |
|---|---|---|---|
| denied banner shown | user grants in iOS Settings, returns | banner unchanged | M6.I1 [B6] |
| location authorized, no cached coordinate | screen opens | "Ready" | M6.I2 [B7] |
| pattern toggle on, auth undecided | toggle | no prompt, no banner | M6.I3 [B1] |

### M7. Watch and widget logging

Widget: `LogHeadacheIntent` inserts a `pending` row if onboarding is complete, else returns a dialog. Watch: `requestLogFromPhone` -> `sendMessage` (reachable) or `transferUserInfo`; the phone logs on every message, with no use of the `requestID` the watch sends. Invariants: M7.I1 one tap, one entry; M7.I2 an acknowledged tap is stored.

| From | Event | To | Notes |
|---|---|---|---|
| sending | reply error after phone already handled | userInfo fallback sent too | possible duplicate entry (M7.I1); needs WCSession error after delivery, not reproducible here, not claimed |
| sending | 10 s timeout | "Timed out. Try again." | same duplicate risk when the message was delivered |

### M8. Review prompt (`ReviewPromptTracker`)

State: launch count, positive-moment pending flag and count, last shown, outcome, plus `reviewPromptShownThisSession`, `foregroundEpoch`, Home coverage flags. Invariants: at most one ask per 30 days, never over a sheet or Undo bar, never for an undone log. Undo calls `consumePendingPositiveMoment`; `positiveMomentCount` is not decremented but is only a counter. No violation found.

### M9. Import and delete (user data)

History delete of entries older than 7 days confirms; newer ones delete immediately and the only way back is the Undo bar (Home, last capture only). Import `Overwrite Existing` replaces every field of a matching event from the CSV row, including clearing notes and severity when the row's cells are empty. `importEvents` ignores a failed `save()` and still reports "N imported" (code path, low likelihood, not claimed).
