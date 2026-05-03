# Pro Launch Checklist

What's wired up in code, and what you (Jack) still need to do in App Store Connect / on the privacy
policy page before submitting the v1.1.0 build that ships Proactive Alerts.

## Code complete

- StoreKit 2 service (`HeadacheLogger/Services/StoreKitService.swift`) — handles purchase, restore, transaction listener, on-device entitlement.
- Local StoreKit configuration (`HeadacheLogger/Services/Products.storekit`) — used only by the Debug scheme; excluded from Release builds.
- Paywall (`HeadacheLogger/Views/PaywallView.swift`) with Restore Purchases, Privacy Policy and Terms of Use links.
- Settings: locked Pro row that opens the paywall; unlocked row navigates to `ProAlertsConfigView`.
- Background task: registered in `AppDelegate`, scheduled when Pro + alerts toggle on, scheduled again when scene goes background.
- Forecast engine (`ProactiveAlertsEngine`) evaluates a 24h window from Open-Meteo for pressure drops and AQI spikes; respects quiet hours and a 6-hour cooldown.
- Cached last-known location: written by `EnvironmentService.captureSnapshot` so the background task does not need "Always" location.
- Marketing version bumped to 1.1.0 (build 35).

## Required: App Store Connect

1. **Create the IAP product**
   - Type: Non-Consumable
   - Product ID: `com.jackwallner.headachelogger.pro.lifetime` (must match exactly)
   - Reference name: "Pro Lifetime"
   - Price: $9.99 (Tier 10) — or change in `Products.storekit` if you want a different price
   - Display name: "Pro Lifetime Unlock"
   - Description: same string as in `Products.storekit` localizations
   - Family Sharing: **disabled** (consistent with paywall copy; flip if you change your mind)
   - Review notes: "Unlocks the Proactive Alerts feature: a daily background check of the local Open-Meteo forecast that fires a local notification when a sharp barometric pressure drop or AQI spike is forecast in the next 24h."
   - Review screenshot: paywall screen

2. **Update App Privacy ("nutrition labels")**
   - **Purchases** → "Linked to user" (Apple ID transaction). No tracking.
   - **Location → Coarse Location** → "Used for App Functionality, Not linked to user, Not used for tracking."
   - Confirm "Health & Fitness" entry already covers the existing HealthKit reads.
   - No new data categories — alerts run on-device.

3. **App Review Information**
   - Demo account: not needed (no accounts).
   - Notes: "Proactive Alerts is a paid in-app purchase that runs a periodic background-fetch task. It uses the device's last-known coarse location (captured when the user logs a headache) to query the public Open-Meteo forecast API and posts a local notification if a meaningful barometric pressure drop or AQI spike is forecast. No Always-location, no servers, no accounts."

4. **Version Information for v1.1.0**
   - "What's New": short copy, e.g.
     "New: Proactive Alerts (Pro). Get a heads-up when sharp barometric pressure drops or air-quality spikes are forecast — common headache triggers. Free version is unchanged."
   - Promotional text: optional; can mention Pro.

## Required: Privacy Policy page

Edit `https://jackwallner.github.io/headaches/privacy-policy.html` to add:

- Section on **In-App Purchases**: "The app offers a one-time non-consumable purchase ('Pro') unlocking Proactive Alerts. Purchase processing is handled by Apple. The app stores no payment information and does not associate purchases with any account."
- Section on **Notifications**: "When Proactive Alerts is enabled, the app posts local notifications based on weather forecasts. No notification content is sent to any server."
- Section on **Background Location Use**: clarify that the app uses **only the last-known coarse location captured during foreground use** for background forecast queries; no continuous tracking, no Always authorization requested.
- Section on **Forecast Data**: "Forecast queries are sent to Open-Meteo (open-meteo.com), a free public weather API, with only latitude/longitude and the current request. No personal identifiers are sent."

## Recommended: Sandbox / TestFlight smoke test

1. In Xcode: Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration → confirm `Products.storekit` is selected.
2. Build to a simulator. Open Settings → Pro → "Proactive Alerts" → tap the locked row.
3. Tap the unlock button. Sandbox purchase should succeed and the row should now navigate.
4. In Xcode menu: Debug → StoreKit → Manage Transactions → delete the transaction. The row should revert to locked on next launch.
5. To smoke-test the background task on a device:
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.jackwallner.headachelogger.weatherCheck"]
   ```
   Run this in the LLDB console while the app is paused in the background. A notification should appear if a trigger condition is met.

## Notes

- The paywall says "Family Sharing not supported." Flip the toggle in App Store Connect AND in `Products.storekit` (`familyShareable: true`) AND update the paywall copy if you decide to enable it.
- Pricing is set in App Store Connect, not in the app — the local `.storekit` price is only for dev. The displayed price in the paywall comes from `product.displayPrice`.
- If Apple requests a "Manage Subscription" link, this is a non-consumable so it doesn't apply. If you ever switch to a subscription, the paywall will need a "Manage Subscription" link to `https://apps.apple.com/account/subscriptions`.
