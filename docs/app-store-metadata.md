# One Tap Headache Tracker App Store Notes

## Public URLs

- Marketing URL: `https://jackwallner.github.io/headaches/`
- Privacy Policy URL: `https://jackwallner.github.io/headaches/privacy-policy.html`
- Support URL: `https://jackwallner.github.io/headaches/support.html`
- Planned repo URL: `https://github.com/jackwallner/headaches`

## App Store Listing Draft

- App Name: `One Tap Headache Tracker`
- Subtitle: `One-tap headache tracking`
- Promotional Text:
  `Log a headache in one tap and automatically capture surrounding Health, time, and weather context. Export your history as a CSV whenever you want to share patterns with your doctor. Pro users get proactive alerts before headache weather arrives.`
- Keywords:
  `headache,migraine,health,journal,tracker,watch,export,doctor,weather,symptoms`

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

## Review Notes Draft

- No account or login is required.
- The main experience is the `Log` tab on iPhone and the watch companion app.
- HealthKit and Location permissions are optional. If either permission is denied, the app still logs the headache and stores partial context.
- The `History` tab exports a CSV through the standard iOS share sheet.
- The `Settings` tab contains a Pro paywall and a Proactive Alerts configuration screen for paid users.
- The `About` tab contains links for privacy policy and support.
- The Apple Watch app queues headache entries to the paired iPhone using `WatchConnectivity`.

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
