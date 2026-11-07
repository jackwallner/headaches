# State machine audit fixes, 2026-11-06

Fixes for the claims `state-machines-2026-11-06-review.md` confirmed, in the review's ranked order. Base commit `0fbbc458b7309e8d1b3c2f30e0ef23fe7b2698f9`.

**Summary: 9 in-scope claims (9 CONFIRMED, 0 UNVERIFIED). 8 fixed, 1 held for Jack, 0 skipped.**

## Claims

| id | outcome | commit | regression test (`HeadacheLoggerTests/StateMachineFixesTests`, added in 53bb4ac) | what changed |
|---|---|---|---|---|
| B1 | fixed | 555a922 | `testPatternToggleAsksForNotificationPermission` | Turning on "Predict from your patterns" (and opening Proactive Alerts with it on) now asks for notification permission while it is undecided, through the engine's existing status-gated request, then schedules (`ProactiveAlertsEngine.patternAlertSettingsChanged`). The permission banner now also shows when only the pattern toggle is on (the location line still needs the forecast toggle). Granting through the forecast toggle now schedules pattern alerts at once. |
| B2 | fixed | 1340b57 | `testPatternAlertsNeverFireInsideQuietHours`, control `testQuietHoursOffKeepsNightPatternAlerts` | Pattern alerts whose fire time falls inside quiet hours are not scheduled, the same rule the forecast alerts follow. Changing quiet hours reschedules at once. The audit's repro asserted exactly one pending alert; the new test asserts the invariant (no pending alert inside quiet hours) plus a daytime control. |
| B4 | fixed | e96c1a9 | `testHistoryDeleteRemovesPatternNotificationItNoLongerSupports` | History delete, the Edit sheet's save and CSV import now reschedule pattern alerts after they save. The delete body moved into `HistoryView.delete(_:in:)` so the test runs the real code; it deletes the same rows as before. |
| B3 | fixed | e96c1a9 | `testUndoRemovesPatternNotificationTheLogCreated`, `testUndoOfSeventhLogRemovesAlertForAnotherDay` | `CaptureCoordinator.undoLastCapture` reschedules pattern alerts after a successful undo. Covers the review's 7th-log route. |
| B8 | held | none | none | See Held for Jack. |
| B5 | fixed | 1340b57 | `testMidnightClusterFiresOneHourBeforeWindow` | A 12 am window now fires at 11 pm the previous evening (Sunday wraps to Saturday), not 23 hours late on the same day. One function, `nextPatternAlertDate`, computes the fire time for B2 and B5. The test turns quiet hours off, since 11 pm is inside the default quiet window. |
| B6 | fixed | 4bfb8c4 | none (see note) | Proactive Alerts refreshes its notification and location status and banner whenever the app becomes active, so returning from iOS Settings updates the screen. |
| B9 | fixed | badd361 | `testBackgroundRunAfterLapseCancelsPatternAlert` | The background forecast run cancels pending pattern alerts when its fresh entitlement fetch says the user is not Pro. A failed fetch (`entitlementCheckFailed`) keeps them. The root view also reschedules pattern alerts when `hasResolvedEntitlements` turns true (the first fresh answer of a launch), which cancels them for a lapsed account and restores them for a renewed one that a cached record had read as lapsed. How membership is judged is unchanged. |
| B7 | fixed | 94b1be8 | `testForecastLocationIsCachedWhenAllowedButMissing`, `testForecastLocationKeepsExistingAndNeedsPermission` | When location is allowed but no capture has stored a coordinate (the review's CSV import route), Proactive Alerts, enabling forecast alerts, and each foreground for a Pro user with forecast alerts on now take a one-shot location and cache it, so "Forecast location: Ready" is true and the forecast check has a place to look up. A stored coordinate is never replaced, and nothing runs without permission or after the onboarding decline. |

Notes:
- B6 has no automated test. The fix is a `scenePhase` observer on a pushed SwiftUI screen, and checking it needs a UI test that denies notifications, grants them with `simctl privacy` and foregrounds the app. gh-sim offers no privacy-grant step.
- B1's new test replaces the audit's `testEnablingPatternAlertsAsksForNotificationPermission`, which the review called unpassable (no unattended test can answer a system prompt). It stubs `requestAuthorization` behind the real center and asserts the toggle's path asks.
- The B2, B3, B5 and B9 tests compile on the base commit and were run there to show they fail without the fixes: run id `headaches-smfix-base-mbpro3b657-1107-001649-15054` (GitHub run 42354800005), 1 passed (the quiet-hours-off control), 5 failed, each on its bug assertion (B9 alert still pending after the lapsed background run, B5 Monday 12 am window notified Monday 23:00, B2 Tuesday 02:00 alert inside 22:00-07:00, B3 alert still pending after both undo routes). The B1, B4 and B7 tests call functions this change adds, so they cannot compile on the base. Their behaviour on the base is the audit's repro result (run 42336784787) and the review's (run 42342538489).
- The audit's repro suite was never added to the test target, so there was nothing to remove. `StateMachineFixesTests.swift` was added to `project.pbxproj` by hand (four lines in the same form XcodeGen writes), because the project file is tracked and XcodeGen is not installed on this fleet machine.
- `.claude/rules/android.md` asks for iOS changes to be ported to `android/`. This run covered the iOS app only, so the Android pattern alerts still need the same review (quiet hours, the midnight window, rescheduling after undo, delete, edit and import, permission on the pattern toggle).

## Held for Jack

- **B8 (existing-user trial pitch never fires from the products trigger on a device).** The fix is a re-evaluation when intro eligibility arrives (an `onChange(of: storeService.introEligibility)` that calls `evaluateExistingUserTrialOffer()`, or publishing eligibility before products in `StoreService.fetchProducts`). Either one changes when the trial offer appears: free users with logs who have not seen it would get the sheet about 3 s after a cold launch, where today they often do not. Decision: should the existing-user trial sheet fire once intro eligibility lands, as the code comment at `HeadacheLoggerApp.swift:282` intends?

## Skipped

None.

## Test results

All on Xcode 27.1, iPhone 17, iOS 27.2 simulator.

- Regression suite on this branch: `gh-sim test --scheme HeadacheLogger --only HeadacheLoggerTests/StateMachineFixesTests`, run id `headaches@20261106-224139-cf80-claude-mbpro3b657-1106-230908-913` (GitHub run 42350053213): 10 passed, 0 failed.
- Same suite on `0fbbc458b7309e8d1b3c2f30e0ef23fe7b2698f9` (the six tests that compile there): run id `headaches-smfix-base-mbpro3b657-1107-001649-15054` (GitHub run 42354800005): 1 passed (control), 5 failed on their bug assertions.
- Full suite on this branch: `gh-sim test --scheme HeadacheLogger`, run id `headaches@20261106-224139-cf80-claude-mbpro3b657-1107-010258-28037` (GitHub run 42358044814): 125 passed, 0 failed, 0 skipped. No test failed, so none needed a base check and none already failed on the base commit.
