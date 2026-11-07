VERDICT: PASS

# Verification of the state machine audit fixes, 2026-11-07

Independent check of `state-machines-2026-11-06-fixes.md` against `state-machines-2026-11-06-review.md`. Every claim was re-read in the code at HEAD `0977b84` (the diff `0fbbc458b7309e8d1b3c2f30e0ef23fe7b2698f9..HEAD`: commits 8b85ba3, 6a73993, 786f3b1, 39cf2f5, 3a67df1, c5d2edf, tests 5042bcb, doc 6e3744e). No app code or tests were changed on this branch. Throwaway branches used for the revert proof and the UI screenshots were deleted.

## Fixes

| id | works | regression check | evidence |
|---|---|---|---|
| B1 pattern toggle never asks for notification permission | yes | pass | Toggle `onChange` calls `schedulePatterns` (ProAlertsConfigView.swift:153-156, :199-204), which goes through `patternAlertSettingsChanged` (ProactiveAlertsEngine.swift:758-763). That function asks through the existing status-gated `ensureNotificationAuthorization` only when the toggle is on and the user is Pro, then schedules. The banner now covers pattern-only users (:274), and the location line still needs the forecast toggle (:287). The `.task` asks again on open while the toggle is on and permission is undecided (:182-185), which reaches users who turned it on before this fix. Shipping UI: on the uninstrumented HEAD app (run 42373726674), tapping "Predict from your patterns" raised the system prompt "Would Like to Send You Notifications" about 4 s later. After Allow, the Notifications row read "Ready" with no banner (screenshots `02-after-pattern-toggle`, `03-stage-after-pattern-toggle`). Unit test `testPatternToggleAsksForNotificationPermission` fails with the fix reverted (0 authorization requests, expected 1). |
| B2 pattern alerts ignore quiet hours | yes | pass | `nextPatternAlertDate` returns nil inside quiet hours (ProactiveAlertsEngine.swift:707-725), and it is the only fire-time source for `reschedulePatternNotifications` (:686). Changing quiet hours reschedules (ProAlertsConfigView.swift:124-126). With default quiet hours (22 to 7), the "7 am on waking" cluster now gets no alert at all instead of a 6 am alert. That is the same rule the forecast path follows (ProactiveAlertsEngine.swift:87-88). `testPatternAlertsNeverFireInsideQuietHours` fails reverted (Tue 02:00 and Mon 06:00 alerts pending). The control `testQuietHoursOffKeepsNightPatternAlerts` passes both ways. |
| B4 History delete (and Edit, import) leave a stale alert | yes | pass | Both delete routes (swipe at HistoryView.swift:271 via `deleteEvents`, and the old-entry confirm at :135) go through `commitDelete`, then `HistoryView.delete` (:450-472), which reschedules after a successful save and rolls back on failure as before. The new body deletes the passed rows directly instead of looking each up in `events` by id; they are the same context's models from `filteredEvents`, so it deletes the same rows. Edit save reschedules (EditEventSheet.swift:93), and import reschedules (HistoryView.swift:523). `testHistoryDeleteRemovesPatternNotificationItNoLongerSupports` fails reverted (`pattern-alert-2-15` still pending). |
| B3 Undo leaves a stale alert | yes | pass | `undoLastCapture` reschedules after its save (CaptureCoordinator.swift:258). The Undo bar calls exactly this function (HomeView.swift:221). Both `testUndoRemovesPatternNotificationTheLogCreated` and `testUndoOfSeventhLogRemovesAlertForAnotherDay` (the review's 7th-log route) fail reverted. |
| B8 trial pitch trigger dead on devices | held | n/a | Correctly held. Both candidate fixes change when the trial sheet appears, which is out of scope for an unattended fix. The diff touches no StoreService, trial or paywall code. |
| B5 midnight window notified 23 h late | yes | pass | A 0 h cluster now fires at 23:00 on the previous weekday, `(weekdayIndex + 5) % 7 + 1` (ProactiveAlertsEngine.swift:718): Sunday maps to Saturday, Monday to Sunday, Saturday to Friday. With default quiet hours that 23:00 alert is suppressed by B2, which is consistent. `testMidnightClusterFiresOneHourBeforeWindow` fails reverted (Monday window notified Monday 23:00). |
| B6 stale permission banner after iOS Settings | yes (code reading) | pass | `.onChange(of: scenePhase)` refreshes statuses and the banner on `.active` (ProAlertsConfigView.swift:188-191), the same pattern SettingsView uses. The root view's foreground reschedule (HeadacheLoggerApp.swift:256) covers the alerts themselves. No automated test (see device checks). |
| B9 pattern alert survives a Pro lapse | yes | pass | The background run cancels pattern alerts when its `.fetchCurrent` entitlement fetch succeeds and reads non-Pro, and keeps them when the fetch failed (ProactiveAlertsEngine.swift:71-80, StoreService.swift:505-527). `hasResolvedEntitlements`, which only an explicit successful fetch sets, now triggers a reschedule (HeadacheLoggerApp.swift:288-296). That cancels alerts for a lapsed account and restores them for a renewed one. Teardown happens only on a fresh network "not Pro"; the pattern toggle and other settings are never cleared. `testBackgroundRunAfterLapseCancelsPatternAlert` fails reverted. |
| B7 "Forecast location: Ready" with no coordinate | yes, partial by design | pass | `cacheForecastLocationIfMissing` fetches one coordinate only when location is authorized, onboarding did not decline it, and none is stored (EnvironmentService.swift:67-87). It never replaces a stored coordinate and never prompts. It runs on opening Proactive Alerts (ProAlertsConfigView.swift:186), after enabling forecast alerts (:302), and on each foreground for Pro users with forecast alerts on (HeadacheLoggerApp.swift:258, :378-381). On the review's CSV route, the coordinate now lands as soon as the user opens the screen or the app. If the one-shot fix fails (15 s timeout), the row still reads "Ready" until a later foreground succeeds. Tests cover the helper only. |

### Disputed

The fixes doc has no Disputed section and lists no disputed claim, so there is nothing to rule on. All nine review claims (B1 to B9) appear in its table: 8 fixed, 1 held, 0 skipped.

### Scope (check 4)

No failure found.
- No change to prices, paywall offers, trial or onboarding flows, how membership is judged, or when a promo appears. The new `schedulePatterns()` in the `hasResolvedEntitlements` handler runs before the unchanged promo calls and only touches local notifications.
- No backend, App Store Connect or RevenueCat change.
- No stored data format change, and no new storage keys. B7 writes the existing `CachedLocation` keys only when they are empty.
- Teardown on entitlement: only after a successful fresh fetch (B9). A failed fetch keeps alerts.
- No UNVERIFIED claim was fixed. B6 and B7 are CONFIRMED in the review (code path), not UNVERIFIED.
- B8 was held for a reason the rules accept (it changes when a trial sheet appears), and it was left untouched.

### Device checks the tests leave open

Each unit test drives the real scheduling code, but none drives the views. These remain device checks:
- B1: covered here by a UI run on the shipping screen (above). Not covered: the open-screen prompt for a user whose toggle was already on before upgrade (ProAlertsConfigView.swift:182-185).
- B2: rescheduling when the quiet-hour steppers change (ProAlertsConfigView.swift:124-126).
- B4: Edit sheet save and CSV import rescheduling (EditEventSheet.swift:93, HistoryView.swift:523). Only the delete route is tested.
- B6: deny, grant in iOS Settings, return, and check the banner clears.
- B7: the CSV import route with location allowed. Check that a coordinate is stored after opening Proactive Alerts.
- B9: the launch reschedule on `hasResolvedEntitlements` for a renewed account that a cached record read as lapsed, and the keep-on-failed-fetch branch.

## Must change

Nothing in app code. One doc inaccuracy: the fixes doc cites commits 555a922, 1340b57, e96c1a9, 4bfb8c4, badd361, 94b1be8 and test commit 53bb4ac, and none of them exist on this branch (it was rebased). The real commits are B1 8b85ba3, B2/B5 6a73993, B3/B4 786f3b1, B6 39cf2f5, B9 3a67df1, B7 c5d2edf, tests 5042bcb.

## Test results

All runs: Xcode 27.1, iPhone 17, iOS 27.2 simulator, on GitHub via gh-sim.

- Full suite on HEAD, `gh-sim test --scheme HeadacheLogger`: run id `headaches@20261107-020506-7442-claude-mbpro649a-1107-020558-756` (GitHub run 42362496456). 125 passed, 0 failed, 0 skipped, matching the fixes doc. All 10 `StateMachineFixesTests` passed. No failure, so no base comparison was needed.
- Fail-without-fix proof on a throwaway branch: B1, B2, B3, B4, B5 and B9 reverted in behaviour only (seams kept so the tests compile), tests unchanged. One `--only` run of 8 tests: run id `headaches@20261107-020506-7442-claude-mbpro649a-1107-023939-16630` (GitHub run 42364890733). 1 passed (the quiet-hours-off control), 7 failed, each on its bug assertion:
  - `testPatternToggleAsksForNotificationPermission`: 0 authorization requests, expected 1.
  - `testPatternAlertsNeverFireInsideQuietHours`: `pattern-alert-3-3` at Tue 02:00 and `pattern-alert-2-7` at Mon 06:00, inside quiet hours.
  - `testHistoryDeleteRemovesPatternNotificationItNoLongerSupports`: `pattern-alert-2-15` still pending.
  - `testUndoRemovesPatternNotificationTheLogCreated` and `testUndoOfSeventhLogRemovesAlertForAnotherDay`: `pattern-alert-2-15` still pending.
  - `testMidnightClusterFiresOneHourBeforeWindow`: Monday window notified Mon 23:00.
  - `testBackgroundRunAfterLapseCancelsPatternAlert`: alert still pending after the lapsed run.
- B7's two tests call a helper the fix adds and cannot fail without it except by not compiling; they assert the helper's guards, not the route.
- UI runs (throwaway UI test on the `HeadacheLoggerUITests` scheme, Pro via `-HeadacheProOverride`, fresh simulator):
  - `...-1107-033052-29395` (GitHub 42368496004): no prompt appeared within 25 s of the toggle tap, and the banner never showed either. Failed.
  - `...-1107-035915-20418` (GitHub 42370473471): my instrumentation did not compile. Proves nothing.
  - `...-1107-041701-29185` (GitHub 42371788078): instrumented build. Toggle `onChange` fired once, the path reached `ensureNotificationAuthorization`, the prompt appeared about 7 s after the tap, and the test passed.
  - `...-1107-044311-31556` (GitHub 42373726674): HEAD app code unmodified, with a 30 s wait and the forecast toggle as a control. The prompt appeared about 4 s after the pattern toggle tap. After Allow the row read "Ready". Passed.

  Two of three valid runs prompted, including the unmodified build. The first run's miss did not repeat and is noted below; it is not counted as a fail.

## Notes

- B1, first UI run: the prompt never appeared and the task never finished (no banner, row still "Needs permission"). That suggests `requestAuthorization` was pending without a visible prompt, which looks like a simulator hiccup. It did not reproduce on HEAD. In the instrumented run the path was entered twice (once from the toggle, once from a second caller, probably the screen's `.task`), and the two calls overlapped. That is harmless, since the status-gated request shows one prompt, but it is worth a look on a device.
- Pre-existing, not introduced: the root foreground reschedule (HeadacheLoggerApp.swift:256) can run on the cached entitlement at cold launch, before the fresh answer. B9's `hasResolvedEntitlements` reschedule repairs that state a beat later.
- Concurrent reschedules (for example quick quiet-hour stepper taps, or an Undo while the capture's own reschedule is still in flight) can interleave remove and add in the nonisolated `reschedulePatternNotifications`. That race already existed. The new triggers make it slightly more frequent, and the next foreground corrects it.
- Existing users after upgrade: alerts already pending from the old code (inside quiet hours, or the late midnight one) are replaced at the first foreground after the update.
- No new user-facing strings, so no localization impact. No layout change. On the iPhone Duo the Proactive Alerts banner section just appears in one more state.
- The Proactive Alerts `.task` takes a one-shot location for any visitor with location allowed and no stored coordinate, even with forecast alerts off. It never prompts, so it is acceptable.
- `StateMachineFixesTests.swift` was added to `project.pbxproj` by hand. The test target is path-based in `project.yml`, so `xcodegen generate` keeps it.
- Android: as the fixes doc says, `android/` still needs the same review under `.claude/rules/android.md`.
