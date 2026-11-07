VERDICT: PASS

# Verification of the state machine audit fixes, 2026-11-07

Independent check of `state-machines-2026-11-06-fixes.md` against `state-machines-2026-11-06-review.md`, over the whole change `ab672d48d4d89e2930c049aa3d27aacd5ba5d574..331eb69`. This replaces the earlier verify doc, which checked a pre-rebase copy of the branch and cited runs on other code. Every claim was re-read in the code at `331eb69`. The fix commits on this branch are B1 `faf9909`, B2/B5 `0ff2b5b`, B3/B4 `2d9dbe8`, B6 `b6a9cbf`, B9 `d0a7c1b`, B7 `72c7f78`, tests `8d18d34`. No app code or tests were changed by this check. The throwaway branches `scratch-revert` and `scratch-ui` were deleted; the only new commit is this doc.

## Fixes

| id | works | regression check | evidence |
|---|---|---|---|
| B1 pattern toggle never asks for notification permission | yes | pass | The toggle's `onChange` (ProAlertsConfigView.swift:153-156) and the sensitivity picker (:163-165) call `schedulePatterns` (:199-204), which runs `patternAlertSettingsChanged` (ProactiveAlertsEngine.swift:758-763): when the toggle is on and the user is Pro it calls the existing status-gated `ensureNotificationAuthorization` (:341-354, prompts only while `.notDetermined`), then schedules. Opening the screen with the toggle already on does the same (ProAlertsConfigView.swift:182-185), so users who turned it on before the upgrade get asked too. The banner now shows for pattern-only users (:274) while the location line still needs the forecast toggle (:287). Granting through the forecast toggle now schedules pattern alerts (:301). `testPatternToggleAsksForNotificationPermission` fails with the fix reverted (0 authorization requests, expected 1). The test drives the engine function, not the toggle; the toggle-to-prompt route was checked in the screen run below (prompt about 5 s after the tap). |
| B2 pattern alerts ignore quiet hours | yes | pass | `nextPatternAlertDate` returns nil when the fire time is inside quiet hours (ProactiveAlertsEngine.swift:707-725, check at :723), and it is the only fire-time source in `reschedulePatternNotifications` (:686). Same rule as the forecast path (:87-88). Changing the quiet-hours toggle or either stepper reschedules (ProAlertsConfigView.swift:124-126). `testPatternAlertsNeverFireInsideQuietHours` fails reverted (Tue 02:00 and Mon 06:00 alerts pending inside 22:00-07:00); the control `testQuietHoursOffKeepsNightPatternAlerts` passes both ways. |
| B4 History delete (and Edit, import) leave a stale alert | yes | pass | Swipe delete (HistoryView.swift:271 via `deleteEvents` :428-442) and the old-entry confirm (:135) both go through `commitDelete` (:450-454) to `HistoryView.delete` (:458-472), which reschedules after a successful save (:470) and rolls back without rescheduling on failure, as before. The body now deletes the passed rows directly instead of re-finding them in `events` by id; the targets come from `filteredEvents` of the same `@Query`, so the same rows go. Edit save (EditEventSheet.swift:93) and CSV import (HistoryView.swift:523) reschedule too. `testHistoryDeleteRemovesPatternNotificationItNoLongerSupports` runs the real `HistoryView.delete` and fails reverted (`pattern-alert-2-15` still pending). |
| B3 Undo leaves a stale alert | yes | pass | `undoLastCapture` reschedules after its save succeeds (CaptureCoordinator.swift:258). The Undo bar calls exactly this (HomeView.swift:225). The capture's own reschedule (:241) has finished before the bar appears, so the two do not overlap. `testUndoRemovesPatternNotificationTheLogCreated` and `testUndoOfSeventhLogRemovesAlertForAnotherDay` (the review's 7th-log route) both fail reverted. |
| B8 trial pitch trigger dead on devices | held | n/a | Held for Jack. Both candidate fixes change when the existing-user trial sheet appears, which check 4 puts out of scope. The diff touches no `StoreService`, trial, onboarding or paywall code. |
| B5 midnight window notified 23 h late | yes | pass | A 0 h cluster now fires at 23:00 on the previous weekday, `(weekdayIndex + 5) % 7 + 1` (ProactiveAlertsEngine.swift:718): Sunday (1) maps to Saturday (7), Monday (2) to Sunday (1), Saturday (7) to Friday (6). With default quiet hours that 23:00 alert is then suppressed by B2, which is consistent with the quiet-hours promise. `testMidnightClusterFiresOneHourBeforeWindow` fails reverted (Monday window notified Mon 23:00, Sunday window Sun 23:00). |
| B6 stale permission banner after iOS Settings | yes (code reading) | pass | `.onChange(of: scenePhase)` refreshes both statuses and the banner on `.active` (ProAlertsConfigView.swift:188-191), the same refresh-on-return SettingsView does with `didBecomeActiveNotification` (SettingsView.swift:195). The pushed screen stays mounted while the user is in iOS Settings, so this observer is live on the review's route. No automated test (device check below). |
| B9 pattern alert survives a Pro lapse | yes | pass | The background run cancels pending pattern alerts only when its `.fetchCurrent` fetch succeeded and reads non-Pro; a failed fetch sets `entitlementCheckFailed` and keeps them (ProactiveAlertsEngine.swift:72-80, StoreService.swift:505-528). `hasResolvedEntitlements`, which on a device only a successful explicit fetch, purchase or restore sets, now triggers a reschedule (HeadacheLoggerApp.swift:287-296), which cancels for a lapsed account and restores for a renewed one. Only pending notifications are removed; the pattern toggle and every other setting stay. `testBackgroundRunAfterLapseCancelsPatternAlert` fails reverted (alert still pending). |
| B7 "Forecast location: Ready" with no coordinate | yes | pass | `cacheForecastLocationIfMissing` takes a one-shot coordinate only when location is authorized, onboarding did not decline it, and none is stored (EnvironmentService.swift:70-87). It never prompts (it returns before `OneShotLocationManager` could ask) and never replaces a stored coordinate. It runs on opening Proactive Alerts (ProAlertsConfigView.swift:186), after enabling forecast alerts (:302), and on each foreground for a Pro user with forecast alerts on (HeadacheLoggerApp.swift:258, :378-381). On the review's CSV route the coordinate lands as soon as the user opens the screen or the app. Each call gets its own `OneShotLocationManager`, so it cannot collide with a capture's location request. The two tests cover the helper's guards only; they call a function the fix adds, so they cannot fail on the base except by not compiling. |

### Disputed

The fixes doc lists no Disputed items (it has no such section), so there is nothing to rule on. All nine review claims B1 to B9 appear in its table: 8 fixed, 1 held, 0 skipped.

### Scope (check 4)

No failure.
- No change to prices, paywall offers, trial or onboarding flows, how membership is judged, or when or to whom a paywall or trial appears. The `schedulePatterns()` added to the `hasResolvedEntitlements` handler (HeadacheLoggerApp.swift:293) only starts a notification reschedule Task before the unchanged promo calls.
- No backend, App Store Connect or RevenueCat change.
- No stored data format change and no new storage key. B7 writes the existing `CachedLocation` keys only while they are empty. No SwiftData model change.
- Teardown: B9 cancels pending pattern notifications only after a fresh successful fetch reads non-Pro. I checked the `entitlementCheckFailed` flag against the concurrent launch fetch from `StoreService.start()`: the flag is only reset when a fetch starts and only set on failure, so an overlap can only keep alerts, never cancel them on a cached answer. No stored setting or record is cleared.
- No UNVERIFIED claim was fixed. B6 and B7 are CONFIRMED in the review.
- B8 was held for a reason the rules accept and was left untouched.
- Every change maps to a listed claim. The extra triggers (quiet-hour steppers for B2, Edit and import for B4, forecast toggle for B1, the open-screen and foreground location fetch for B7) are each named in the review's route or impact for that claim.

### Regression walk (check 2)

- Callers: `schedulePatternAlertsIfEnabled` now also runs from undo, delete, edit, import, quiet-hours changes, the forecast toggle and the first fresh entitlement answer. It is idempotent (removes all `pattern-alert-*`, re-adds from current data), so extra calls only cost an analysis pass. `nextPatternAlertDate` has one caller. `patternAlertSettingsChanged` has two (the toggle and picker, and the screen's `.task`). `HistoryView.delete` has one app caller (`commitDelete`) plus the test.
- Widgets and watch: neither target compiles any changed file (project.yml widget and watch sources). Widget and watch logs still end in `CaptureCoordinator`, unchanged here, and are picked up by the foreground reschedule.
- Existing users after upgrade: alerts the old code left pending (inside quiet hours, or the late midnight one) are replaced at the first foreground. A Pro user with the pattern toggle on and permission undecided is asked when they next open Proactive Alerts, not at launch.
- Entitlements and trials: the `hasResolvedEntitlements` flip happens once per launch; nothing in the promo or trial gating changed.
- Undo and edit: covered above. Edit's reschedule runs after its save on the same context.
- Day and time zone: weekday wrap checked for all seven days. Fire times still use floating `DateComponents`, as before.
- Localized text: no new or changed string. The banner text is unchanged and now shows in one more state.
- iPhone Duo: no layout change. The existing banner section on Proactive Alerts appears in one more state.

### Device checks the tests leave open

The unit tests drive the real scheduling code but not the views. Still open:
- B1: the open-screen prompt for a user whose toggle was already on before the upgrade (ProAlertsConfigView.swift:182-185). The toggle route itself is covered by the UI run below.
- B2: rescheduling when the quiet-hour toggle or steppers change (ProAlertsConfigView.swift:124-126).
- B4: Edit save and CSV import rescheduling (EditEventSheet.swift:93, HistoryView.swift:523). Only the delete route is tested.
- B6: deny, grant in iOS Settings, return, and check the banner clears.
- B7: the CSV import route with location allowed; check a coordinate is stored after opening Proactive Alerts.
- B9: the launch reschedule on `hasResolvedEntitlements` for a renewed account that a cached record read as lapsed, and the keep-on-failed-fetch branch.

## Must change

Nothing in app code or tests.

Doc only (does not fail the check): the fixes doc cites base `0fbbc458b7309e8d1b3c2f30e0ef23fe7b2698f9` and commits 555a922, 1340b57, e96c1a9, 4bfb8c4, badd361, 94b1be8 and 53bb4ac, none of which exist on this branch. The real commits are listed at the top of this doc. Its run ids are from that earlier copy as well.

## Test results

All on GitHub via gh-sim: Xcode 27.1, iPhone 17, iOS 27.2 simulator.

- Full suite on HEAD `331eb69`, `gh-sim test --scheme HeadacheLogger`: run id `headaches@20261107-050636-a8b0-claude-imaca330-1107-050720-20059` (GitHub run 42375500583). 125 passed, 0 failed, 0 skipped, matching the fixes doc's count. All 10 `StateMachineFixesTests` passed. No failure, so no base comparison was needed.
- Fail-without-fix proof on `scratch-revert` (B1, B2, B3, B4, B5 and B9 reverted in behaviour only, the functions the tests call kept, tests unchanged), one `--only` run of 8 tests: run id `headaches@20261107-050636-a8b0-claude-imaca330-1107-052526-14691` (GitHub run 42376899443). 1 passed (the quiet-hours-off control), 7 failed, each on its bug assertion and none on a precondition:
  - `testPatternToggleAsksForNotificationPermission`: 0 authorization requests, expected 1.
  - `testPatternAlertsNeverFireInsideQuietHours`: `pattern-alert-3-3` at Tue 02:00 and `pattern-alert-2-7` at Mon 06:00 inside quiet hours.
  - `testHistoryDeleteRemovesPatternNotificationItNoLongerSupports`: `pattern-alert-2-15` still pending.
  - `testUndoRemovesPatternNotificationTheLogCreated`, `testUndoOfSeventhLogRemovesAlertForAnotherDay`: `pattern-alert-2-15` still pending.
  - `testMidnightClusterFiresOneHourBeforeWindow`: Monday window notified Mon 23:00, Sunday window Sun 23:00.
  - `testBackgroundRunAfterLapseCancelsPatternAlert`: alert still pending after the lapsed background run.
- Screen check (check 5) on the unmodified HEAD app: a throwaway UI test on `scratch-ui` (deleted) with `-uitesting -HeadacheScreenshotSeed -HeadacheProOverride`, Settings > Proactive Alerts, forecast toggle left off: run id `headaches@20261107-050636-a8b0-claude-imaca330-1107-053915-29741` (GitHub run 42377946959), 1 passed. Screenshots in that run's `attachments/`:
  - `01-open`: Notifications "Needs permission", both toggles off, no banner (unchanged behaviour).
  - `02-quiet-hours-and-prediction`: Quiet hours (10 PM to 7 AM) and "Predict from your patterns" render as before.
  - `03-after-pattern-toggle`: tapping only "Predict from your patterns" raised the system prompt "One Tap Headache Tracker Would Like to Send You Notifications" about 5 s later. This is the B1 route, which never prompted before the fix.
  - `04-after-allow-top`: after Allow, Notifications reads "Ready" and no banner shows; the location line stays out of the banner with forecast alerts off, as intended.
  The B6 banner refresh, the B2 stepper reschedule and the B7 row need permission changes outside the app and were not reachable in this run (device checks above).

## Notes

- `testPatternToggleAsksForNotificationPermission` took 96 s in the full run (0.05 s in the revert run). The time is spent before the test body's first assertion, in the real `notificationSettings()` call on a cold notification daemon. It passed, but on a slower runner it is the test most likely to hit a timeout.
- Pre-existing, not introduced: the root foreground reschedule (HeadacheLoggerApp.swift:256) can run on the cached entitlement at cold launch, before the fresh answer. B9's `hasResolvedEntitlements` reschedule corrects that a beat later.
- Concurrent reschedules (quick stepper taps) can interleave remove and add in the nonisolated `reschedulePatternNotifications`. That race already existed; the new triggers make it a little more frequent, and the next reschedule corrects it.
- `HistoryView.delete` now calls `context.delete` on the passed model without first checking it is still in `events`. A model deleted elsewhere between the swipe and the old-entry confirm would be deleted twice; no route found reaches that (Undo only covers the newest log, which never needs the confirm).
- The Proactive Alerts `.task` takes a one-shot location for any visitor with location allowed and no stored coordinate, even with forecast alerts off. It never prompts.
- Pre-existing, not touched by this change: on the Proactive Alerts screen the Personalization footer runs under the floating tab bar (`01-open`), since the screen calls `.clearsFloatingTabBar()` without row marks.
- `StateMachineFixesTests.swift` was added to `project.pbxproj` by hand. The test target is path-based in `project.yml`, so `xcodegen generate` keeps it.
- Android: as the fixes doc says, `android/` still needs the same review under `.claude/rules/android.md`.
