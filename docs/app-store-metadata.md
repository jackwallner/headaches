# One Tap Headache Tracker App Store Notes

## Public URLs

- Marketing URL: `https://jackwallner.github.io/headaches/`
- Privacy Policy URL: `https://jackwallner.github.io/headaches/privacy-policy.html`
- Support URL: `https://jackwallner.github.io/headaches/support.html`
- Planned repo URL: `https://github.com/jackwallner/headaches`

## App Store Listing Draft

- App Name: `One Tap Headache Tracker`
- Subtitle: `One-tap headache tracking`
- Promotional Text (170 char max):
  `Log a headache in one tap and capture surrounding Health, time, and weather context. Pro tracks your patterns and alerts you before risky weather arrives.`
- Keywords (100 char max) — **use verified list in `docs/astro-aso-metadata-proposal.md`** (98 chars). Old draft below was 119 chars (over limit):
  ~~`headache,migraine,tracker,log,journal,diary,weather,barometric,pressure,trigger,doctor,export,csv,watch,health,symptoms`~~
  `headache,migraine,tracker,watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,log`

## Description Draft

One Tap Headache Tracker helps you capture a headache the moment it starts.

Tap once on iPhone or Apple Watch and the app records the time immediately, then fills in as much surrounding context as it can automatically.

One Tap Headache Tracker can include:

- Time context such as weekday, hour, minute, time zone, and part of day
- Apple Health context such as steps, activity, sleep, heart metrics, breathing, and recent workouts
- Weather and environmental context such as temperature, pressure, air quality, UV, and pollen-style signals
- One-tap Apple Watch logging that syncs back to your paired iPhone
- CSV export for sharing your history with a doctor
- Pro: Proactive Alerts — get notified before barometric pressure drops or air quality spikes

One Tap Headache Tracker is local-first:

- No account required
- No ads
- No analytics SDKs
- No cloud sync
- Manual export only when you decide to share data

Download One Tap Headache Tracker and start understanding your headaches.

## What's New in v1.1.0 — Copy-Paste into App Store Connect

New: Pro tier (optional). Two new features for Pro subscribers and lifetime buyers:
• Proactive Alerts — a heads-up when sharp barometric pressure drops or air-quality spikes are forecast.
• Personalized Insights — see what conditions your headaches actually cluster around.
Free version is unchanged. Try Pro free for 7 days.

## App Review Information — Copy-Paste into App Store Connect

Below is the complete text for App Store Connect → App Review → App Review Information.

---

**Sign-In Required:** No. No accounts, no sign-in, no demo credentials needed.

**Hardware Required:** None beyond a standard iPhone. Apple Watch testing is optional — the iPhone app is fully self-contained. If testing on Apple Watch, pair it to the same iPhone being reviewed.

**Permissions Required During Review:** The app requests HealthKit (read-only) and Location (When In Use) on first launch. Granting both is recommended for the full experience, but the app works if either is denied — it simply stores partial context for the headache entry. HealthKit is only read locally; no Health data leaves the device. Location is used only to fetch anonymous weather data from the public Open-Meteo API at the moment a headache is logged.

**Lifecycle for Review (Recommended Order):**

1. **Onboarding** — First launch shows a brief onboarding explaining what the app does. HealthKit and Location permissions are requested. Grant both if possible; test denial flow separately if needed.

2. **Log Tab (Core Experience)** — Tap the large `Tap to log a headache` button. The time is recorded immediately (to the second). After logging, the app shows what context was captured: weekday, time of day, step count, sleep, heart rate, breathing rate, recent workouts (from HealthKit), and environmental data (temperature, pressure, humidity, AQI, UV index, pollen-style signals from Open-Meteo). All fetched automatically — no manual data entry required.

3. **Un-log (Undo)** — After logging, the log screen shows a "headache started at X:XX" banner with a small `×` dismiss button. Tapping it removes the entry from the database.

4. **History Tab** — Lists all logged headaches in reverse chronological order. Each entry shows the timestamp, captured context, and any note. Tap on any entry to see full detail. The `Export` button (share icon, top right) opens the standard iOS share sheet with a CSV file containing all entries and their full context. Test: share to Files, Mail, or any share target — the CSV includes columns for date, weekday, hour, HealthKit values, weather values, and notes.

5. **Patterns Tab (Free/Pro)** — Free users see a teaser with sample or blurred real patterns and **See Pro plans**. Pro users see personalized insights from their logs.

6. **Settings Tab** — Contains:
   - **Proactive Alerts row** — If not Pro, tapping opens the paywall. If Pro, navigates to alert configuration.
   - **Manage Subscription** — Visible only when the user has an active monthly or yearly subscription (not lifetime). Opens Apple's system subscription management sheet.
   - **Restore Purchases** — Always visible.
   - **About & Support** — Privacy Policy, Terms, Support, and feedback.

**Pro / In-App Purchase Testing:**

Three IAP products unlock the same on-device Pro entitlement:

- **Pro Yearly** (`com.jackwallner.headachelogger.pro.yearly`) — auto-renewable yearly subscription with a 7-day free trial for eligible new subscribers.
- **Pro Monthly** (`com.jackwallner.headachelogger.pro.monthly`) — auto-renewable monthly subscription (no introductory offer).
- **Pro Lifetime** (`com.jackwallner.headachelogger.pro.lifetime`) — one-time non-consumable purchase.

**Reach the paywall:**
- Settings → locked Proactive Alerts row, OR
- Patterns tab → **See Pro plans**, OR
- After the optional trial-offer sheet → **See all plans** (or dismiss trial and open paywall from Settings/Patterns).

**Trial-offer sheet** (eligible new subscribers only): may appear after the first headache log, for returning users with existing logs, or on Patterns (second touch). Primary button starts the yearly free trial; **See all plans** opens the full paywall with all three options. **Restore Purchases** is on both the trial sheet and full paywall.

**Full paywall:** yearly (default), monthly, and lifetime plan cards; CTA reflects selection (e.g. **Start Free Trial** when eligible on yearly). Disclosure text under the button includes price, auto-renew, and subscription management in Settings. **Restore Purchases** and Terms/Privacy links at the bottom. Dismiss with the × button. Purchases dismiss the sheet automatically when Pro unlocks.

Once Pro is active:
- The "Proactive Alerts" row in Settings navigates to the alert config screen.
- The Insights tab shows real personalized data.
- Toggle "Proactive Alerts" ON to enable the background task.

**Proactive Alerts — Background Task Testing:**

When Proactive Alerts is toggled ON:
1. The app registers and schedules a BGAppRefreshTask with identifier `com.jackwallner.headachelogger.weatherCheck`.
2. iOS runs this task periodically in the background (at the system's discretion).
3. The task uses the device's last-known coarse location (stored from the most recent foreground use) to query the public Open-Meteo API for a 24-hour forecast.
4. If a barometric pressure drop ≥ 4 hPa or AQI ≥ 100 is forecast within the next 24 hours, a local notification is posted.
5. The task enforces a minimum 6-hour cooldown between notifications regardless of forecast changes.

To trigger the background task during review (on a physical device):
- In Xcode, pause the app after backgrounding it.
- In the LLDB console: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.jackwallner.headachelogger.weatherCheck"]`
- A notification should appear if qualifying weather is forecast.

**Testing with Denied Permissions:**

The app handles permission denials gracefully. If HealthKit is denied, the context card still shows all non-Health data (time, weather). If Location is denied, the weather card shows "Location not available" and no weather data is fetched. In either case, the headache is still logged and appears in History.

**Note on Double-Tap (Watch):**

On Apple Watch, a single tap on "Log Headache" queues the entry via WatchConnectivity to the paired iPhone. The watch app handles connectivity failures gracefully — if the phone isn't reachable, the entry is transferred when the connection re-establishes. Deduplication is handled on the phone side for edge cases where both the message and transferUserInfo fallback fire.

**No Backend / No Servers:**

All processing is on-device. The only external network request is to the public Open-Meteo weather API (api.open-meteo.com) for weather and air-quality data at the moment a headache is logged. No data is collected by the developer. There is no cloud sync, no analytics SDK, and no advertising.

## App Privacy Guidance

Review this carefully in App Store Connect before submission.

Recommended answers based on the current implementation:

- Tracking: `No`
- Linked-to-user data:
  - `Purchases` → Linked to user (Apple ID transaction ID for IAP)
  - Everything else → Not linked to user
- Data used for tracking: `None`
- Data collected off device for app functionality:
  - `Precise Location` — latitude and longitude are sent from the device to Open-Meteo to fetch weather and air-quality context. This is collected only at the moment you log a headache.
  - `Purchases` — handled by StoreKit; Apple processes the transaction.
- Health data:
  - `Health & Fitness` — disclosed. HealthKit values are read locally on device and are not uploaded to a developer-owned backend.

### New for v1.1.0 (Pro)

Add or update these privacy declarations:

1. **Purchases** → Data type: `Purchases` → Purpose: `App Functionality` → Linked to user: `Yes` (Apple ID)
2. **Notifications** → The app posts local notifications for Proactive Alerts. No notification data is sent off-device.
3. **Location** → Already declared as `Precise Location` for app functionality. The background Pro task uses only the last-known coarse location captured during foreground use. No continuous tracking.
4. **Health & Fitness** → Already declared; no change from v1.0.

## Submission Checklist

- Confirm the production app icon set is complete and visually final.
- Publish the GitHub Pages docs so the privacy and support URLs are live.
- Verify the final App Store Connect privacy answers.
- Confirm HealthKit usage descriptions are accurate for the final release build.
- Confirm Location usage descriptions are accurate for the final release build.
- Test iPhone logging, watch logging, export, and denied-permission flows on real devices.
- Take App Store screenshots for iPhone and Apple Watch.
- Fill in age rating, category, and pricing in App Store Connect.
