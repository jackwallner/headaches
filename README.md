# Headache Logger

**One-tap headache tracking for iPhone & Apple Watch.**

Log a headache in one tap. The app automatically captures 50+ data points from Apple Health and local weather. Export a doctor-friendly CSV whenever you're ready.

**Free. No ads. No accounts. No cloud. Open source.**

[Website](https://jackwallner.github.io/headaches/) | [App Store](https://apps.apple.com/us/app/headache-migraine-logger/id6762074561) | [Privacy Policy](https://jackwallner.github.io/headaches/privacy-policy.html) | [Support](https://jackwallner.github.io/headaches/support.html)

[![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/us/app/headache-migraine-logger/id6762074561)

## Features

- **One tap** - Log a headache instantly. No forms, no questions, no typing.
- **Apple Health context** - Steps, sleep, HRV, resting heart rate, SpO2, VO2max, workouts, audio exposure, mindful minutes, and more.
- **Weather & environment** - Temperature, barometric pressure + trend, humidity, wind, UV index, precipitation, cloud cover.
- **Air quality** - US AQI, EU AQI, PM2.5, PM10, ozone, NO2, SO2, CO.
- **Pollen** - Alder, birch, grass, mugwort, olive, ragweed.
- **Time patterns** - Weekday, hour, part of day, timezone.
- **Apple Watch** - One-tap logging from your wrist. Entries queue and sync automatically.
- **Home screen widget** - Log without opening the app via WidgetKit + App Intents.
- **Siri Shortcuts** - Automate logging with the "Log Headache" intent.
- **CSV export** - 60+ columns. Share via email, AirDrop, or any share destination.
- **Doctor-friendly** - Designed for clinical sharing with both metric and imperial units.

## Privacy

Headache Logger stores everything on your device. No accounts, no analytics, no ads, no cloud sync.

Location is used once per tap to fetch local weather from [Open-Meteo](https://open-meteo.com/). Raw coordinates are never stored. Your data leaves your device only when you explicitly export it.

[Full privacy policy](https://jackwallner.github.io/headaches/privacy-policy.html)

## Tech Stack

| Framework | Purpose |
|-----------|---------|
| SwiftUI | UI |
| SwiftData | Local persistence |
| HealthKit | Apple Health integration (read-only) |
| CoreLocation | Location for weather lookup |
| Open-Meteo API | Weather |
| WidgetKit + App Intents | Home screen widget |
| WatchConnectivity | Apple Watch sync |
| XcodeGen | Project generation |

## Repo Layout

```
HeadacheLogger/          iPhone app
HeadacheLoggerWatch/     Apple Watch companion
HeadacheLoggerWidget/    Home screen widget extension
HeadacheLoggerTests/     Unit tests
SharedHeadache/          App group helpers and shared keys
docs/                    GitHub Pages (landing page, privacy, support)
scripts/                 Helper scripts (e.g. TestFlight upload)
```

## Build

```bash
xcodegen generate
xcodebuild -project HeadacheLogger.xcodeproj -scheme HeadacheLogger -destination 'generic/platform=iOS' build
```

## Test

```bash
xcodebuild -project HeadacheLogger.xcodeproj -scheme HeadacheLogger -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## License

See [LICENSE](LICENSE) for details.

## Author

Jack Wallner — [jackwallner@gmail.com](mailto:jackwallner@gmail.com)
