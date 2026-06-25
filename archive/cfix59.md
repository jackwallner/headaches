# cfix59 — Exhaustive User Experience Review

A rigorous, user-perspective audit of One Tap Headache Tracker (build 41). Every item below is a real friction point a user would hit. No code edits — just the raw experience.

---

## 🔴 Premium & Paywall — The Purchase Experience Hurts

### 1. Canceling a purchase gives zero feedback
When the user taps a plan, taps "Subscribe," sees the system payment sheet, and then cancels — the button just stops spinning. Nothing else. No haptic, no "purchase canceled" message, no visual acknowledgment. The user stares at the screen wondering if their tap even registered. Same thing happens with `.pending` (Ask to Buy) — the child is waiting for parent approval but the app went silent.

### 2. No purchase-success moment
When the purchase actually succeeds, the paywall sheet just dismisses abruptly. No welcome animation, no "You're Pro!" celebration, no feature tour. The Patterns tab snaps instantly from teasing sample data to real insights (or worse, to "Not enough data yet"). The transition is cold.

### 3. "Start 7-Day Free Trial" button may be lying
The paywall shows a prominent "Start 7-Day Free Trial" CTA for the yearly plan, but the code checks whether the *product* has a trial — not whether the *user* is eligible. If someone already used their trial and comes back, the paywall still says "Free Trial." Apple's system payment sheet will show the full price. This mismatch between what the app promises and what Apple shows is jarring and erodes trust.

### 4. "No previous purchase was found" — but only sometimes
If a user restores purchases from the paywall, they get an alert whether it succeeded or failed. But if they restore from Settings, absolutely nothing happens. No spinner. No success. No "nothing found." Just silence. A user who heard about "Restore Purchases" and tries it from Settings has no idea whether it worked.

### 5. Pricing is hidden until you commit
The Patterns tab shows a locked teaser with sample insights and an "Unlock Pro" button — but no prices anywhere. The user has to tap through to the paywall before they see anything about cost. For price-sensitive users, this feels like bait-and-switch.

### 6. Partial product loading leads to an "Unavailable" button
Yearly is pre-selected. If the yearly product fails to load from App Store but monthly succeeds, the button reads "Unavailable" and is disabled — with no explanation. The user can fix it by manually tapping monthly, but there's no hint that they should.

### 7. Error messages can leak StoreKit jargon
Failed purchases show `error.localizedDescription` directly in an alert. Users can see raw Apple framework strings instead of user-facing explanations.

### 8. Subscription disclosure text wraps inconsistently
Monthly and yearly plans have different structural wrapping for their legal disclosure text, creating uneven vertical rhythm in the plan cards. Minor but sloppy.

---

## 🔴 Patterns & Insights — Promised Land, Rough Landing

### 9. Pay first, then find out you need more data
A user buys Pro expecting to see their patterns. If they have fewer than 5 events, they land on "Not enough data yet." There's no warning *before* purchase that they need 5+ logs. A paying user staring at an empty state they can't fix immediately feels cheated.

### 10. Sample insights are hardcoded, not previews of your data
The free-user teaser shows generic sample data ("40% of your headaches happen in the evening"). A user with 50 events sees the same fake sample as a user with 0 events. They can see their event count in the footer, but there's zero hint of what their actual patterns look like. A blurred or skeletonized preview of real data would be far more compelling than fake numbers.

### 11. "No clear patterns yet" is a dead end
When a user has 5+ events but no individual insight passes its statistical threshold, they see "No clear patterns yet — not enough variation in any one factor." There's no actionable guidance — no suggestion to log at different times, check Health permissions, or enable severity tracking. The user is stuck.

### 12. Charts are static and unhelpful
Every bar chart in `InsightDetailView` is a static image with zero interactivity. No tap-to-see-value. No legend toggles. No horizontal scroll for the 7-bar weekday chart (which is cramped at small card widths). The charts answer "what is my distribution" but give no ability to explore it.

### 13. You can't tell which factors were checked and excluded
The insights list only shows factors that crossed their threshold. A user with 39% high-humidity headaches (threshold: 40%) sees nothing about humidity — and has no way to know it was close. This creates false confidence that unmentioned factors are irrelevant.

### 14. Insight detail pages are long scroll marathons
Each `InsightDetailView` is a continuous `ScrollView` with chart + "Your pattern" narrative + "Why this matters" explanation + optional alerts CTA + disclaimer. On smaller phones this can be 4+ screens of scrolling with no table of contents or jump-to-section navigation. The alerts CTA at the bottom can be completely missed.

### 15. Proactive Alerts card always pushes alerts, even when irrelevant
The "Proactive Alerts" card appears in every user's insights list, urging setup even for users whose patterns show zero correlation with pressure or AQI (e.g., their only insight is "Most common day: Tuesday"). It feels like an upsell widget rather than a relevant feature.

### 16. Severity insight is permanently hidden unless you opted in at onboarding
If the user chose "Skip" on the severity/notes onboarding step (or never enabled it later), severity is never collected and the severity insight is permanently unavailable — with no indication *why* it's missing or how to enable it.

---

## 🔴 Apple Watch — Unreliable at the Worst Moment

### 17. Taps can vanish silently
If the watch app just launched and WCSession hasn't finished activating yet, tapping the button shows "Connecting to iPhone…" for 4 seconds — and then nothing. The payload is never queued. The event is lost. When you're mid-migraine and just want to log it, this is the worst possible failure mode.

### 18. "Logged" doesn't mean what you think
The watch shows a green checkmark and "Logged" — but the enrichment (HealthKit data, weather, location) hasn't happened yet. If the user hasn't completed iPhone onboarding, hasn't granted Health permissions, or has location denied, the event saves with no context. The watch gives no indication that extra context failed.

### 19. Offline queue is invisible and unreliable
When the phone is unreachable, the watch says "Queued — will sync when iPhone is nearby" but shows no persistent badge or count. Four seconds later, the message disappears and there's no indicator that entries are pending. You can log three headaches offline and have no visual evidence any of them are queued.

### 20. The same tap can log twice
In rare WCSession transition states, both `sendMessage` and the fallback `transferUserInfo` can fire for the same tap. There's no deduplication on the phone side, creating duplicate events. A user reviewing their history would see two identical entries and not know why.

### 21. iPhone cold-kill erases pending watch taps
`PhoneWatchSession.pendingTapDates` is an in-memory array. If the iPhone app is terminated before processing queued watch messages, those taps are permanently lost. The watch showed "Logged" (or "Queued") but no event exists.

### 22. Every status message vanishes in 4 seconds
Errors ("Could not save event. Try again."), success ("Logged."), and status ("Sending…") all auto-clear after 4 seconds. There's no error history, no retry button, no persistent state. If you blinked or looked away, you missed it.

### 23. "Timed out" can appear when the message was delivered
A hardcoded 10-second timeout fires even if `sendMessage` is actively in-flight over a slower Wi-Fi connection. The watch shows "Timed out. Try again." while the phone may have already created the event.

---

## 🟡 Home Screen & Capture Flow — Mostly Solid, Some Snags

### 24. Capture can take 15-20 seconds with no progress indicator
When location is slow AND HealthKit retries AND the network lags, enrichment can take 15-20 seconds. The only UI feedback is the button label changing from "Tap once to log right now" to "Saving and collecting context…" — there's no progress bar, no step indicator, no skeletal animation. A user wondering "did it work?" might tap again.

### 25. "Undo Last Tap" can appear for a save that failed
`lastCapturedEventID` is set before the initial save is confirmed. If that save fails, the Undo button appears anyway — for an event that was never persisted. The user taps Undo and nothing meaningful happens (already noted as FIX-4 in fixplan.md).

### 26. Severity/notes sheet only fires for phone taps
If `promptForSeverityNotes` is on, the severity/notes sheet appears after an iPhone tap — but never after a watch or widget tap. A watch user who wants to add severity has to open the phone app, find the event in History, and edit notes there. No indication of this gap exists.

### 27. Successful capture banner auto-clears after ~3 seconds
"Context saved." appears in a subtle orange banner that fades quickly. If the user was looking at the latest event card to check their data, they might miss the confirmation entirely.

---

## 🟡 History & Export — Powerful Data, Weak Discovery

### 28. Export button is invisible to new users
The CSV export is a bare `square.and.arrow.up` icon in the toolbar — no label, no "Export" text, no "Share with doctor" callout. It only appears after the first event is logged. A new user has no idea this feature exists. The History empty state mentions "building a timeline you can share" but never tells you how or where.

### 29. No search whatsoever
A user who remembers writing "triggered by red wine" in a note has no way to find that event. The note preview shows inline (4 lines max) but the full text isn't searchable. With 200+ events, finding anything means scrolling.

### 30. Year filter is the only filter
You can filter by year — and that's it. No severity filter ("show me extreme headaches"), no part-of-day filter ("show me morning headaches"), no date range, no capture-status filter. The 60+ data points in the CSV are completely inaccessible from the UI.

### 31. No sorting options
Events are always newest-first. No sort by severity, temperature, sleep duration, or any other captured metric.

### 32. Tap an event — nothing happens
`DetailedEventRow` shows a rich card with timestamp, badges, location, weather, and metric pills — but it's not tappable. The 60+ fields (HRV, heart rate, AQI, pollen, all individual health metrics) are invisible. The only interaction is swipe-to-delete or tap a tiny pencil icon for notes.

### 33. Summary grid can't be explored
"Most Common Day: Tuesday" and "Most Common Time: Evening" sit as flat stats. Tapping them does nothing. You can't see the day-of-week distribution or jump to those entries.

### 34. No bulk operations
Swipe-to-delete is the only row interaction. No multi-select mode, no "delete all from this month," no batch export of selected entries. A user who wants to remove a bad week of test data has to swipe-delete 14 times.

---

## 🟡 Settings & About Tab — Identity Crisis

### 35. Tab label says "About," screen says "Settings"
The tab bar reads `"About"` with a `slider.horizontal.3` icon (an iOS convention for settings/adjustments). The screen's navigation title reads `"Settings"`. A user has no idea what this tab actually is. The SF Symbol says "Settings," the label says "About," and the content is a mix of both.

### 36. Three sections of wall-of-text with zero controls
"How Logging Works," "Captured Context," and "Sharing" are pure informational paragraphs sitting inside a `List` alongside toggles and pickers. Users scan for controls and hit walls of text. This content belongs in onboarding, help docs, or contextual tooltips — not a settings form.

### 37. "Restore Purchases" is buried under "Privacy and Support"
A user looking to restore their purchase naturally checks the "Pro" section. Instead, Restore Purchases lives in the very last section alongside privacy policy links. And as noted in #4, it's completely silent.

### 38. No app version or build number anywhere
Basic "About" information is missing. A user troubleshooting or reporting a bug has no way to see what version they're on without leaving the app.

### 39. No data management at all
No way to delete all data. No way to see storage usage. No way to reset the app. A user who wants a fresh start has to delete the app and reinstall.

### 40. Health "permission" check shows hardware, not authorization
Settings shows "Available on this device" for Health, using `HKHealthStore.isHealthDataAvailable()` — which checks whether the *device* supports HealthKit, not whether the *user* granted read permissions. A user who denied Health access still sees a green checkmark.

### 41. Location status is a raw string
The permissions section shows "Denied" or "Off" as raw system authorization values, not user-friendly labels.

### 42. "Open iPhone Settings" offers no guidance
The button opens the iOS Settings app but gives zero direction about what to change once there. The user is dropped into a long settings page with no indication of which toggle to find.

### 43. No mention of the Watch app anywhere
Despite having a companion Watch app that works independently, Settings has no Watch-related row, status, or help.

### 44. No mention of the Widget anywhere
The Home Screen widget is never mentioned in Settings, help text, or onboarding. A user who would benefit from it has no way to discover it exists.

---

## 🟢 Widget — A Button, Not a Widget

### 45. Zero data display
The widget shows exactly two states: a "Log headache" button, or a green checkmark for 10 seconds after tap. There's no count, no streak, no "last logged," no today indicator — nothing that answers "at a glance" questions. Compared to widgets from other health apps, it provides no glanceable information.

### 46. Confirmation expires in 10 seconds
The green checkmark that confirms your tap disappears after 10 seconds. If you log and glance back 15 seconds later, you see the "Log headache" button again — no visual evidence you already logged today.

### 47. Medium widget wastes half the Home Screen
The widget supports `.systemMedium` (4 icon slots wide) but renders the exact same content as `.systemSmall` (2 slots) — just stretched across a wider burgundy rectangle. There's no extra information density, no second button, no stats.

### 48. Onboarding dead end
If you haven't completed iPhone onboarding, tapping the widget shows a dialog saying "Open One Tap Headache Tracker and finish setup" — but `openAppWhenRun = false` means the app doesn't actually open. You get a message and nothing happens.

### 49. Hardcoded burgundy background
The widget's `Color(red: 0.35, green: 0.12, blue: 0.16)` cannot be changed and may clash with some Home Screen aesthetics. No light/dark variants, no tinting from the app's accent color.

### 50. No configuration
It's a `StaticConfiguration` — no widget parameters, no ability to change what's shown. A user who wants "just show my count" or "show my streak" can't customize anything.

---

## 🟢 Onboarding — Unpolished First Impression

### 51. No back button
Once you advance past Welcome, you can't go back. On the Health screen and want to re-read the Welcome text? Too late. On Location and want to reconsider what Health permissions you granted? No way back.

### 52. No skip for Health or Location
The onboarding flow presents Health and Location as mandatory steps with no "Not now" button. Functionally, both permissions are optional — the app degrades gracefully without them — but the onboarding doesn't reflect this. Users who are privacy-conscious hit a forced OS permission dialog with no in-app way to decline.

### 53. No progress indicator
Four steps with no "Step 1 of 4" dots or progress bar. The user doesn't know how many steps remain or how close they are to finishing.

### 54. No privacy policy or terms during onboarding
The Settings tab has legal links, but onboarding shows none. Apple's guidelines generally want a privacy policy available before data collection begins.

### 55. Watch bypasses onboarding, widget blocks it — inconsistent
A Watch tap creates events immediately, no onboarding required. A widget tap refuses with a dialog. A user who uses both devices gets inconsistent behavior with no explanation.

### 56. "Clinician" language assumes medical context
The Welcome screen mentions "share with your clinician." Not all users have a clinician, and this framing can feel exclusionary or make the app feel more medical than it is.

### 57. 20+ Health metrics requested, only 4 mentioned
The Health step says "activity, sleep, heart rate, and workouts" but the app actually requests 20+ data types including SpO₂, VO₂ max, respiratory rate, walking speed, environmental audio exposure, barometric pressure, and mindful minutes. The user isn't told the full scope.

---

## 🟢 General — Across the App

### 58. No visual distinction between free and Pro tiers outside the paywall
Once you're past the paywall, there's no persistent "Pro" badge, no subtle indicator on tabs, no premium styling. A user who bought Pro has no ambient reminder that they're on the premium tier — and a free user has no ambient nudge that there's more to unlock.

### 59. CSV export — excellent output, zero onboarding
The `ExportService` produces a 69-column, RFC 4180-compliant CSV with a 10-line comment preamble explaining every column, formula injection guards, and proper quoting. It's genuinely well-engineered — and almost no user will ever find it. There's no first-export tip, no "Share with your doctor" callout during onboarding, no in-app badge pointing to the feature.

### 60. No notification settings for free users at all
Free-tier users see nothing about notifications anywhere. If a free user wants a daily reminder to log, or a gentle nudge, there's no option. Proactive Alerts are Pro-gated, but basic reminder notifications could be a free feature that builds the habit.

### 61. Pressure trend and AQI/pollen data are still hardcoded nil
CSV columns and UI pills exist for barometric pressure trend and air quality/pollen metrics, but these fields are never populated (noted as FIX-7 and FIX-8 in fixplan.md). A user sees pressure trend as `unavailable` on every single event and AQI showing `—` — data that never arrives undermines trust in the rest of the captured context.

### 62. No "Rate on App Store" prompt or link
Standard iOS app convention. Settings has no rate link, and there's no positive-moment prompt (e.g., after 10+ logs).

---

## Summary by Severity

| Tier | Count | Key Themes |
|------|-------|------------|
| 🔴 Critical UX failures | 8 | Silent purchase cancel, no success celebration, misleading trial CTA, silent restore, blind paywall, watch tap loss, no dedup, watch feedback lies |
| 🔴 Patterns/Premium friction | 8 | Pay-then-wait dead end, fake sample data, dead-end state, static charts, hidden insight gaps, scroll-marathon detail pages |
| 🟡 Core app friction | 11 | Slow capture no progress, buggy undo, severity gap, invisible export, no search, year-only filter, untappable events, summary dead end |
| 🟡 Settings confusion | 10 | About/Settings identity crisis, wall-of-text sections, buried restore, no version, no data mgmt, fake health check, missing watch/widget mentions |
| 🟢 Widget weakness | 5 | No data display, 10s confirmation, wasted medium space, onboarding dead end, no configuration |
| 🟢 Onboarding gaps | 7 | No back, forced permissions, no progress dots, no privacy links, inconsistent watch/widget, narrow language, incomplete Health disclosure |
| 🟢 Cross-app issues | 6 | No tier indicator, invisible export, no free notifications, hardcoded nils, no rate prompt |

---

## What's Not Here (Already in ds57.md or fixplan.md)

Issues already covered in other docs are intentionally omitted from this review:

- **ds57.md covers:** Privacy manifest gaps (location data declaration, UserDefaults API declaration, missing Watch privacy manifest), print() statements in Release, trial-to-paid sentence, widget ITSAppUsesNonExemptEncryption, Watch display name, unused background mode, duplicate product ID set
- **fixplan.md covers:** Watch offline queue dedup (FIX-1), wrong watch timestamps (FIX-2), watch success before delivery (FIX-3), stale lastCapturedEventID (FIX-4), final save success banner bug (FIX-5), undo clearing ID on save fail (FIX-6), AQI/pollen nil (FIX-7), pressure trend unavailable (FIX-8), widget enrichment fetches all events (FIX-9), CSV formula injection (FIX-10), history delete ignores save failure (FIX-11)
