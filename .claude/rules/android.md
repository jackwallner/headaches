---
paths:
  - "android/**"
  - "docs/android-*.html"
  - "scripts/android-pro.sh"
  - "scripts/play_screenshot_compositor.py"
  - "scripts/play-products.py"
  - "scripts/play-upload.sh"
  - "scripts/make_android_icon.py"
---

# Migraine Headache Tracker Android rules

## Identity and products

- Native Android code is in `android/`, a screen-for-screen port of the iOS app
  (same copy, brand `#F2405C` / `#DB296E`, flows and product IDs). When iOS
  changes, port the change. Watch app and Siri are out of scope.
- Package `com.jackwallner.headachelogger` (same as the iOS bundle ID),
  launcher label "One Tap Headache Tracker", Play title "Migraine Tracker:
  Headache Log", paid tier "Headache Pro". Contact `jackwallner+ha@gmail.com`.
- Free: logging, history, CSV export/import, the Glance widget. Pro (any active
  entitlement, `StoreService.isPro`): full Patterns, Doctor PDF, Proactive
  Alerts (WorkManager forecast check every 3 hours plus pattern alerts) and the
  daily risk forecast.
- Products (same IDs as iOS): subscriptions
  `com.jackwallner.headachelogger.pro.monthly` and `.pro.yearly` (base plans
  `monthly` / `yearly`, 7-day `trial-7d` new-customer offer), lifetime one-time
  product `com.jackwallner.headachelogger` (purchase option `lifetime`). Android
  US ladder $7.99 / $31.99 / $71.99, about 20% under iOS ($9.99 / $39.99 /
  $89.99); local prices are Play's conversion plus the fleet PPP curve. Never
  put prices in listing copy or app literals. Onboarding and the trial sheet
  sell the monthly plan; the paywall lists yearly, monthly, lifetime.
- RevenueCat project `proj9f4317d7`: Test Store app `appc9f5ec98ff` (Debug key
  `apikey133d4ecc5f`), Play app `app9a47a4ce79` (`goog_` key
  `apikey23c1114d75`, release only), App Store app `appb2158584e0`. Entitlement
  `entlcee15be440` holds every store's products. The app reads offering
  `android` (`ofrng908a7044d9`, not current; iOS keeps its default) with
  `$rc_monthly` (`pkge79ec494407`), `$rc_annual` (`pkge6f6c96971f`) and
  `$rc_lifetime` (`pkge78e629606b`). Play products `prod15ec9a8db5`,
  `prod2484bafb08`, `prode55d0abe4f`; Test Store twins `prod9aa4ce3c30`
  (monthly), `prodd3c9df8958` (yearly), `prodd45d6d893b` (lifetime).
- Play reviewers unlock Headache Pro with a code (long-press Settings > About &
  Support > Version). Only its SHA-256 is in the build (`PLAY_REVIEW_CODE_SHA256` in
  `local.properties`); the code is `HEADACHES_PLAY_REVIEW_CODE` in
  `~/.headaches_credentials`. Never commit it.

## Deliberate differences from iOS

- Sleep comes from Health Connect (`READ_SLEEP` only, `SleepSessionRecord`);
  steps, heart rate and the other HealthKit columns stay empty, so Home shows
  Pressure, Sleep and AQI chips and History rows show Sleep, hPa and AQI.
  `HealthRationaleActivity` is the Health Connect rationale screen.
- Location is one-shot coarse (`ACCESS_COARSE_LOCATION`), cached for the
  background forecast check; no background location permission.
- iOS sheets are an overlay stack (`Navigator`) plus root promo sheets
  (`PromoController`) with the same timing (first log +4s, existing user +3s,
  Patterns second touch, one promo per session).
- Purchase copy names Google Play. The review prompt keeps the iOS gates
  (second launch on, 30-day cooldown, 3.5s after a complete log with Home
  clear) and calls `launchReviewFlow` with no enjoyment question, never from a
  button. Settings "Rate" opens the Play listing.
- Charts are Compose Canvas; the Doctor PDF is `PdfDocument` (`ReportPdf.kt`).

## Build

- JDK 17 (`/Library/Java/JavaVirtualMachines/temurin-17.jdk`), checked-in Gradle
  wrapper 9.7.0, AGP 9.4.1, Kotlin 2.4.20, minSdk 26, target/compile 36.
- `android/local.properties` (ignored, mode 600) holds `REVENUECAT_TEST_KEY`,
  `REVENUECAT_PLAY_KEY`, `PLAY_REVIEW_CODE_SHA256` and `PLAY_UPLOAD_*` (upload
  keystore `~/.android/keystores/headaches-upload.p12`, backup in
  `~/.android/keystores/backups/`, alias `upload`, password
  `HEADACHES_PLAY_UPLOAD_PASSWORD` in `~/.headaches_credentials`). Release
  builds fail without them. Upload cert SHA-256
  `3D:5E:A9:11:46:D8:3A:30:2E:75:F8:7E:9A:BB:EB:03:82:61:10:76:A2:B9:19:12:F3:34:82:DF:5A:6F:B7:4B`.
- Unit tests: `cd android && ./gradlew testDebugUnitTest` (76 tests, parity with
  the iOS tests for CSV, insights, alerts, daily records, plans, conversion
  copy and the review tracker).
- `scripts/make_android_icon.py` derives the adaptive icon layers and
  `play-assets/icon-512.png` from the iOS AppIcon.
- Increment `versionCode` on every Play upload. 1.5.3 is versionCode 1.
- `scripts/play-upload.sh [validate|internal|internal-draft|production-draft]`
  and `scripts/play-products.py [--dry-run]` need `PLAY_SERVICE_ACCOUNT_JSON`.
  Neither has been run yet.

## Emulator (remote MacBook Pro only)

Follow the `android-dev` skill's Remote MacBook Pro section. Host
`jackwallner@192.168.4.25` (strict host keys), SDK
`/Users/jackwallner/Library/Android/sdk`. Never boot an emulator on this Mac,
never touch `small_phone` (emulator-5554) or other agents' AVDs.

- Create the temporary AVD `headaches_agent_test` by hand: `.ini` plus a
  `config.ini` cloned from `small_phone.avd/config.ini` with the `android-36`
  `google_apis_playstore` x86_64 image (not 36.1), `hw.lcd.width=1080`,
  `hw.lcd.height=2400`, `hw.lcd.density=420`. Boot headless on port 5570:
  `nohup ~/Library/Android/sdk/emulator/emulator -avd headaches_agent_test -port 5570 -no-window -no-audio -no-boot-anim -no-metrics -gpu swiftshader_indirect > /tmp/headaches-emulator.log 2>&1 &`.
  A cold boot takes about 5 minutes on the 2-core Pro; let it settle (the
  first instrumentation run after boot can ANR).
- Disable Digital Wellbeing (`pm disable-user --user 0
  com.google.android.apps.wellbeing`) and the three animation scales first.
- Pro has no JDK 17: build both APKs here (`./gradlew assembleDebug
  assembleDebugAndroidTest`), then `scripts/android-pro.sh install | test
  [class] | shot <png> | adb <args>`. `AppSmokeTest` is 8 connected tests.
- Stop with `adb -s emulator-5570 emu kill`, wait for the qemu process to
  exit, then delete only `~/.android/avd/headaches_agent_test.{avd,ini}` and
  `/tmp/headaches-android-test`.
- Debug launch extras (`DebugLaunchOptions`, debug builds only): `resetAll`,
  `completeSetup`, `seedDemo` (the iOS screenshot seed, sleep and AQI only),
  `demoPro`, `previewStore`, `fakeContext` (offline Health and weather),
  `appearance` (light|dark), `tab` (home|history|patterns|settings), `sheet`
  (paywall|trial|prointro|details|alerts|quiz), `onboardingStep` (0-3),
  `noPromos`. Test tags are exposed as resource ids.

## Store assets

Raw 1080x2400 captures in `android/play-assets/raw/` come from the emulator in
System UI demo mode (clock 0941, wifi full, mobile hidden, notifications off):
home and history (`seedDemo`, free), patterns, Proactive Alerts (toggle on) and
an insight detail (`demoPro`, `fakeContext`). `python3
scripts/play_screenshot_compositor.py` writes the 1080x1920 frames to
`android/play-assets/screenshots/` and the 1024x500 feature graphic. Listing
text is in `android/play-assets/metadata/android/en-US/` (no prices, no em
dashes, never treat/cure/diagnose claims). Privacy and terms pages are
`docs/android-privacy.html` and `docs/android-terms.html` on GitHub Pages.

## Play Console answers to enter (app does not exist yet)

- App content > Health apps declaration: health and fitness features, a
  personal headache log (symptom tracking and wellness). Not a medical device,
  no clinical use, no diagnosis, no treatment claims.
- Health Connect permissions declaration: `READ_SLEEP` only, read only, to
  note sleep length before a headache and compare sleep with headache days.
  Rationale screen `HealthRationaleActivity` (action
  `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, alias for
  `VIEW_PERMISSION_USAGE`).
- Data safety: the headache log and sleep data stay on device (not
  collected). Approximate location: collected and shared with Open-Meteo for
  app functionality (weather and air quality), not stored by us, optional.
  Shared with RevenueCat as a service provider: Purchase history (Financial
  info), Device or other IDs (anonymous app user ID), App interactions
  (upgrade-screen counts). Purposes: app functionality and analytics.
  Encrypted in transit: yes. Not sold, no ads. Deletion by email (privacy
  policy section `#delete-data`).
- Privacy policy URL: `https://jackwallner.github.io/headaches/android-privacy.html`.
- Content rating (IARC): Utility/Productivity or Reference; no violence,
  sexual content, language, controlled substances, gambling, user-generated
  content; does not share the user's location with other users. Expected
  Everyone / PEGI 3.
- Target audience: 18 and over. Ads: none. App access: no login; Headache Pro
  is unlocked for review with the code above (long-press Settings > About &
  Support > Version). News: no. Government: no. Financial features: no.
- Store listing: category Health & Fitness, contact `jackwallner+ha@gmail.com`,
  website `https://jackwallner.github.io/headaches/`.

## Play state (2026-10-16)

Not yet created. Signed AAB vc1 1.5.3 is built and verified locally. The app
record, listing, App content declarations, products, service account access and
every upload are still to do in Play Console.
