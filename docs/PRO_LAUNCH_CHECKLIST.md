# Pro Launch Checklist

What's wired up in code, and what you (Jack) still need to do in App Store Connect / on the privacy
policy page before submitting the v1.1.0 build that ships Proactive Alerts.

## Code complete

- [x] StoreKit 2 service (`HeadacheLogger/Services/StoreKitService.swift`) — handles purchase, restore, transaction listener, on-device entitlement.
- [x] Local StoreKit configuration (`HeadacheLogger/Services/Products.storekit`) — used only by the Debug scheme; excluded from Release builds.
- [x] Paywall (`HeadacheLogger/Views/PaywallView.swift`) with Restore Purchases, Privacy Policy and Terms of Use links.
- [x] Settings: locked Pro row that opens the paywall; unlocked row navigates to `ProAlertsConfigView`.
- [x] Background task: registered in `AppDelegate`, scheduled when Pro + alerts toggle on, scheduled again when scene goes background.
- [x] Forecast engine (`ProactiveAlertsEngine`) evaluates a 24h window from Open-Meteo for pressure drops and AQI spikes; respects quiet hours and a 6-hour cooldown.
- [x] Cached last-known location: written by `EnvironmentService.captureSnapshot` so the background task does not need "Always" location.
- [x] Marketing version bumped to 1.1.0 (build 35).

## Required: App Store Connect

### 1. Create the IAP product

Go to App Store Connect → Your App → Features → In-App Purchases → "+"

| Field | Value |
|-------|-------|
| Type | Non-Consumable |
| Product ID | `com.jackwallner.headachelogger.pro.lifetime` |
| Reference Name | `Pro Lifetime` |
| Price | $9.99 USD (Tier 10) |
| Display Name | `Pro Lifetime Unlock` |
| Description | `Get notified before a likely headache day. Predictive barometric pressure and air quality alerts based on your local forecast.` |
| Family Sharing | **Disabled** |
| Review Screenshot | Upload a screenshot of the Paywall screen |
| Review Notes | `Unlocks the Proactive Alerts feature: a daily background check of the local Open-Meteo forecast that fires a local notification when a sharp barometric pressure drop or AQI spike is forecast in the next 24h.` |

Click **Save**, then click **Submit for Review** once the app binary is uploaded.

### 2. Update App Privacy ("nutrition labels")

Go to App Store Connect → Your App → App Privacy → **Edit**

Set these exactly:

- **Tracking**: `No, we do not track users`
- **Linked to user data**:
  - `Purchases` → `Linked to user` → `App Functionality`
  - `Precise Location` → `Not linked to user` → `App Functionality`
  - `Health & Fitness` → `Not linked to user` → `App Functionality`
- **Data used for tracking**: `None`

Then save and continue.

### 3. App Review Information

Go to App Store Connect → Your App → App Review Information

- **Demo Account**: Not needed (no accounts)
- **Notes** (copy-paste exactly):
  ```
  Proactive Alerts is a paid in-app purchase that runs a periodic background-fetch task. It uses the device's last-known coarse location (captured when the user logs a headache) to query the public Open-Meteo forecast API and posts a local notification if a meaningful barometric pressure drop or AQI spike is forecast. No Always-location, no servers, no accounts.
  ```

### 4. Version Information for v1.1.0

Go to App Store Connect → Your App → v1.1.0 → Version Information

- **What's New** (copy-paste):
  ```
  New: Proactive Alerts (Pro). Get a heads-up when sharp barometric pressure drops or air-quality spikes are forecast — common headache triggers. Free version is unchanged.
  ```
- **Promotional Text** (optional):
  ```
  Log a headache in one tap and automatically capture surrounding Health, time, and weather context. Pro users get proactive alerts before headache weather arrives.
  ```

## Required: Privacy Policy page

- [x] Updated `docs/privacy-policy.html` with sections on In-App Purchases, Notifications, Background Location Use, and Forecast Data.

**Next step:** Commit and push the `docs/` folder so `https://jackwallner.github.io/headaches/privacy-policy.html` is live before submission.

## Recommended: Sandbox / TestFlight smoke test

### Simulator (StoreKit sandbox)

1. In Xcode: Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration → confirm `Products.storekit` is selected.
2. Build to a simulator. Open Settings → "Proactive Alerts" → tap the locked row.
3. Tap the unlock button. Sandbox purchase should succeed and the row should now navigate to the config screen.
4. In Xcode menu: Debug → StoreKit → Manage Transactions → delete the transaction. The row should revert to locked on next launch.

### Device (background task)

1. Build to a physical device, complete onboarding, and purchase Pro via TestFlight sandbox.
2. Enable Proactive Alerts in Settings → Proactive Alerts.
3. Background the app.
4. In Xcode, pause the app and run in LLDB console:
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.jackwallner.headachelogger.weatherCheck"]
   ```
5. A local notification should appear if a pressure drop ≥ 4 hPa or AQI ≥ 100 is forecast in the next 24h.

## Notes

- The paywall says "Family Sharing not supported." Flip the toggle in App Store Connect AND in `Products.storekit` (`familyShareable: true`) AND update the paywall copy if you decide to enable it.
- Pricing is set in App Store Connect, not in the app — the local `.storekit` price is only for dev. The displayed price in the paywall comes from `product.displayPrice`.
- If Apple requests a "Manage Subscription" link, this is a non-consumable so it doesn't apply. If you ever switch to a subscription, the paywall will need a "Manage Subscription" link to `https://apps.apple.com/account/subscriptions`.
