# Migraine Headache Tracker — Project Guide

One-tap headache logging with weather and sleep context around each entry, plus
pattern insights over what was logged. XcodeGen project/scheme: `HeadacheLogger`,
sim lease owner `headaches`. App Store name **Migraine Headache Tracker**, App
Store ID `6762074561`.

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency), SwiftData in an App Group
- Core Location + **Open-Meteo** for weather and air quality (no WeatherKit entitlement)
- HealthKit (sleep), WidgetKit + an App Intent, watchOS companion, BGTaskScheduler
- XcodeGen (`project.yml`). Targets: iOS 17+, watchOS
- RevenueCat, gate is `StoreService.isProUnlocked`

## Targets / bundle IDs
- `HeadacheLogger` — `com.jackwallner.headachelogger`
- `HeadacheLoggerWidget` — `.widget` (carries `LogHeadacheIntent`)
- `HeadacheLoggerWatch` — `.watch`
- `HeadacheLoggerTests` — `.tests`, `HeadacheLoggerUITests` — `.uitests`
- App Group: `group.com.jackwallner.headachelogger`

## Architecture
`SharedHeadache/` is the small module the phone, watch and widget all compile:
`HeadacheAppGroup` (the container and every `HeadacheStorageKey`),
`HeadacheQuizStore` and its questions, and `HeadacheTemperatureFormatting`.
The widget additionally compiles `HeadacheEvent` and `HeadacheModelStore`
straight from the app target, so those two files must stay free of app-only
dependencies. Everything else lives in `HeadacheLogger/`:

- `Models/` — `HeadacheEvent`, `ProAlertPreferences`
- `Services/`
  - `CaptureCoordinator` — the one-tap log path every surface goes through
  - `HeadacheModelStore`, `DailyRecordStore` — persistence and the per-day rollup
  - `EnvironmentService` — one-shot location plus the Open-Meteo fetch
  - `ProactiveAlertsEngine` — value-typed 24-hour forecast evaluation that can run
    off the main actor from a background task; `BackgroundRefreshService`
    schedules it; `DailyWeatherBackfillService` fills gaps in past days
  - `InsightsEngine` — pure analysis over logged events, on device
  - `ExportService` / `ImportService`, `HealthKitService`, `PhoneWatchSession`,
    `StoreService`, `ReviewPromptTracker`, `ConversionDiagnostics`
- `Views/` — `RootTabView`, `HomeView`, `HistoryView`, `InsightsView`,
  `OnboardingView`, the headache quiz, `PaywallView`, `SettingsView`,
  `ProAlertsConfigView`
- `Utilities/` — `AppStoreReviewLinks`, `OpenMeteoTimeParsing`,
  `SleepIntervalMerge`, `PaywallScreenshotMode`, appearance

## Rules that hold everywhere
- **Weather is Open-Meteo, not WeatherKit.** Keep it that way: the app ships no
  WeatherKit entitlement. Forecast work runs from the background task declared in
  `Info.plist` as `com.jackwallner.headachelogger.weatherCheck`.
- **`InsightsEngine` output is descriptive, never causal.** "What does the data
  show", never "what caused this headache". That framing is what keeps a symptom
  tracker clear of App Review 1.4.1, and the same rule governs store copy.
- **Free vs Pro.** Logging, history, the widget and the watch app are free. Pro
  (`StoreService.isProUnlocked`) unlocks the full insights view past the sample
  threshold, the Doctor PDF export, and Proactive Alerts
  (`ProactiveAlertsEngine` returns early without it). Products: subscriptions
  `…headachelogger.pro.monthly` / `.pro.yearly` plus the non-consumable
  `com.jackwallner.headachelogger` in `Services/Products.storekit`.
- **Never present a promo or trial sheet before entitlements resolve.**
  `HeadacheLoggerApp` gates every sheet on `hasResolvedEntitlements` and
  `!isProUnlocked`, because a pending renewal can flip Pro on a beat after launch
  and yank a sheet mid-layout.
- **Review funnel:** `ReviewPromptTracker.recordPositiveMoment()` after a
  completed capture (`CaptureCoordinator`) and from History; the sheet is
  `ReviewPromptSheet`. App Store ID above.
- `design.md` is the design system (brand `#F2405C`, high-contrast on system
  grays). Read it before UI work.
- ASO plan and keyword reasoning: `aso-plan.md`. The subtitle sells the one-tap
  log; barometric forecasting failed the SERP-intent guardrail and stays in the
  keyword field only.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
