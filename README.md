# Headache Logger

Headache Logger is a standalone iPhone and Apple Watch app for one-tap headache logging.
It captures as much surrounding context as possible automatically, including time-of-day,
Apple Health context, and location-based weather/environmental signals, then lets the user
export a CSV to share with a doctor.

**This repository** is the source of truth for the app (`jackwallner/headaches` on GitHub).

## Highlights

- One-tap headache logging on iPhone, Apple Watch, Home Screen widget, and Shortcuts (App Intents)
- Automatic HealthKit context such as steps, energy, sleep, heart metrics, and workouts
- Automatic weather, air quality, UV, and pollen-style context using Open-Meteo
- Local-first storage with manual CSV export
- No accounts, no ads, no analytics, no cloud sync

## Tech Stack

- SwiftUI
- SwiftData
- HealthKit
- CoreLocation
- WatchConnectivity
- WidgetKit / App Intents
- XcodeGen

## Repo Layout

- `HeadacheLogger/` — iPhone app
- `HeadacheLoggerWatch/` — Apple Watch companion
- `HeadacheLoggerWidget/` — Home Screen “Log headache” widget
- `HeadacheLoggerTests/` — unit tests
- `SharedHeadache/` — app group helpers and shared keys
- `docs/` — GitHub Pages (privacy, support, metadata notes)
- `scripts/` — helper scripts (e.g. TestFlight upload)

## Build

```bash
xcodegen generate
xcodebuild -project HeadacheLogger.xcodeproj -scheme HeadacheLogger -destination 'generic/platform=iOS' build
```

## Test

```bash
xcodebuild -project HeadacheLogger.xcodeproj -scheme HeadacheLogger -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## GitHub Pages

Static site files live under `docs/` (enable Pages from `/docs` on this repo). Example URLs:

- `https://jackwallner.github.io/headaches/`
- `https://jackwallner.github.io/headaches/privacy-policy.html`
- `https://jackwallner.github.io/headaches/support.html`
