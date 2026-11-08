# Pre-submit review, 2026-11-07 (1.5.6)

Scope: every app source change from the live App Store version to `origin/main`.

- Live: 1.5.5 build 120, released 2026-11-01 (iTunes lookup for id 6762074561 returns 1.5.5). It shipped from `ship/1.5.5`, tip `cf4abba` (last app change `c036c5f`, build bump `b177ca4`).
- Candidate: 1.5.6 build 121, `25ec7f8` (main, which merges `ship/1.5.5` back in).
- Diff: `git diff cf4abba 25ec7f8` over `HeadacheLogger/`, `SharedHeadache/`, the widget and watch targets and `project.yml`. 22 Swift/plist files plus `Localizable.xcstrings` (+18 keys). Widget and watch sources are unchanged.

What changed: the new `AppTheme` contrast palette replacing `ReadableColors`, localization of runtime strings (severity, part of day, capture status, insight titles, weather summaries), the Settings Language row with `UIPrefersShowingLanguageSettings`, accessibility layout work on Home, History and the paywall, DEBUG-only screenshot seeding, and the state machine audit fixes (B1 to B7, B9: pattern alert permission, quiet hours, the midnight window, rescheduling after undo, delete, edit and import, lapse cancellation, forecast location caching).

Checked and clean:
- Crashes: no new force unwraps, indexing or SwiftData schema changes (`HeadacheEvent` gained only computed `localizedName`s, no stored properties). `cacheForecastLocationIfMissing` uses a fresh `OneShotLocationManager` per call, so it cannot clobber a capture's continuation. The new `#if DEBUG` modifier and branches compile out of Release.
- String catalog: every new key has all 14 languages, and no translation's format specifiers differ from its key's (script check over every entry). Each new `String(localized:)` key the code builds is in the catalog.
- Purchases: the paywall diff is layout and color only. Close button, Restore, Terms and Privacy links remain on the paywall, the trial sheet and onboarding. No hard-coded prices. `isProUnlocked` gating is unchanged, except that pattern alerts are now also cancelled after a fresh non-Pro answer (a failed fetch keeps them).
- App Review: no new debug UI reachable in Release (`isScreenshotMode` and the seeds are `#if DEBUG`), no links to other platforms, and no new treat, cure or diagnose wording.
- Project: `project.pbxproj` no longer references the deleted `ReadableColors.swift`, and no old helper is still used. No merge conflict markers.

## Findings

| # | severity | file:line | what happens | status |
|---|---|---|---|---|
| 1 | P2 | HeadacheLogger/Services/ProactiveAlertsEngine.swift:675 | `reschedulePatternNotifications` and `cancelAllPatternNotifications` read the pending list and then remove from it in separate steps, and several unserialized Tasks can run them together (the launch foreground, `hasResolvedEntitlements`, Proactive Alerts `.task`, a capture). The IDs are deterministic (`pattern-alert-<weekday>-<hour>`), so a cancel based on an older snapshot can remove an alert another Task has just rescheduled. That needs a Pro user with no cached customer info whose two Tasks interleave on the notification center. | not fixed: no reproduction, and the fix (serializing the scheduler behind an actor) is larger than a pre-submit change |
| 2 | P2 | HeadacheLogger/HeadacheLoggerApp.swift:264 | When `isProUnlocked` flips mid-session (a purchase, or a lapse pushed by the RevenueCat delegate), only the background check is rescheduled. Pattern alerts catch up on the next foreground, capture or Proactive Alerts visit, so a lapsed account can still get one pending pattern alert during that session. | not fixed: the window is one session and the next foreground corrects it |
| 3 | P2 | HeadacheLogger/Views/HomeView.swift:47 | The 3.5 s post-log lockout (`showCheckmark`) is gone. The Log button ignores taps only while a capture runs, so a second tap right after a capture finishes logs a second entry. The Undo bar covers it. | not fixed: a deliberate UX change from the Home redesign, not a defect |
| 4 | P2 | HeadacheLogger/Services/InsightsEngine.swift:1517 | Patterns calls the 12 am to 6 am bucket "Night" ("Most common time: Night"), while Home and History show the same bucket as "Overnight" (`PartOfDay.localizedName`). | not fixed: copy choice from `dd667ca` (screenshot localization) |
| 5 | P2 | HeadacheLogger/HeadacheLoggerApp.swift:466 | Carried over from the 2026-11-06 state machine audit (B8, held for Jack): on a device the existing-user trial pitch can miss the products trigger, because intro eligibility arrives after `products.count` changes. Pre-existing in 1.5.5, so not a regression. | not fixed: held for Jack's call on when the trial offer should appear |

No P0 or P1 findings.

## Tests

`gh-sim test --scheme HeadacheLogger --skip HeadacheLoggerUITests` on `25ec7f8`; result below.
