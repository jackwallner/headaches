# Pro Launch Checklist

What's wired up in code, and what you (Jack) still need to do in App Store Connect / on the privacy
policy page before submitting the v1.1.0 build that ships Proactive Alerts and Personalized Insights.

## Code complete

- [x] StoreKit 2 service (`HeadacheLogger/Services/StoreKitService.swift`) — handles purchase, restore, transaction listener, on-device entitlement for both subscription and lifetime products.
- [x] Local StoreKit configuration (`HeadacheLogger/Services/Products.storekit`) — used only by the Debug scheme; excluded from Release builds. Defines:
  - `com.jackwallner.headachelogger.pro.yearly` — auto-renewable subscription, $9.99/yr, 7-day free trial.
  - `com.jackwallner.headachelogger.pro.lifetime` — non-consumable, $24.99, family shareable.
- [x] Paywall (`HeadacheLogger/Views/PaywallView.swift`) — yearly + lifetime selector, free-trial CTA, auto-renewal disclosure, Restore Purchases, Privacy Policy and Terms of Use links.
- [x] Settings: locked Pro row that opens the paywall; unlocked row navigates to `ProAlertsConfigView`. "Manage Subscription" deep-link visible when subscription is active. Restore Purchases always visible.
- [x] Background task: registered in `AppDelegate`, scheduled when Pro + alerts toggle on, scheduled again when scene goes background.
- [x] Forecast engine (`ProactiveAlertsEngine`) evaluates a 24h window from Open-Meteo for pressure drops and AQI spikes; respects quiet hours and a 6-hour cooldown. Re-checks both product IDs against current entitlements before firing.
- [x] Personalized Insights view (`HeadacheLogger/Views/InsightsView.swift`) — computes pattern distributions across the user's logged events; Pro-gated with a paywall teaser for free users.
- [x] Cached last-known location: written by `EnvironmentService.captureSnapshot` so the background task does not need "Always" location.
- [x] Marketing version 1.1.0 (build 37+).

## Required: App Store Connect

### 1. Create the IAP products

Go to App Store Connect → Your App → Features → In-App Purchases → "+"

#### A. Subscription

| Field | Value |
|-------|-------|
| Type | Auto-Renewable Subscription |
| Reference Name | `Pro Yearly` |
| Subscription Group Reference Name | `OneTapHeadacheProGroup` (create new) |
| Product ID | `com.jackwallner.headachelogger.pro.yearly` |
| Subscription Duration | 1 Year |
| Price | $9.99 USD (or local equivalent) |
| Display Name | `Pro Yearly` |
| Description | `Annual Pro access. Proactive headache-weather alerts and personalized pattern insights.` |
| Family Sharing | **Enabled** |
| Introductory Offer | Free trial, 1 week, available to new subscribers in all territories |
| Review Screenshot | Upload a screenshot of the Paywall screen showing the subscription option |
| Review Notes | `Auto-renewable annual subscription. 7-day free trial for new subscribers. Unlocks Proactive Alerts (background forecast check) and Personalized Insights (analytics over the user's logged events). All processing is on-device.` |

#### B. Lifetime

| Field | Value |
|-------|-------|
| Type | Non-Consumable |
| Product ID | `com.jackwallner.headachelogger.pro.lifetime` |
| Reference Name | `Pro Lifetime` |
| Price | $24.99 USD |
| Display Name | `Pro Lifetime` |
| Description | `One-time purchase. Unlocks Pro forever — proactive alerts and personalized insights.` |
| Family Sharing | **Enabled** |
| Review Screenshot | Same paywall screenshot showing the lifetime option |
| Review Notes | `Non-consumable alternative to the yearly subscription. Same Pro entitlement; no auto-renewal.` |

Click **Save** for both, then **Submit for Review** once the app binary is uploaded.

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
  Pro is sold as either an auto-renewable yearly subscription (with a 7-day free trial) or a one-time
  lifetime purchase. Both unlock the same on-device feature set: Proactive Alerts (a periodic
  background-fetch task that uses the device's last-known coarse location to query the public
  Open-Meteo forecast API and posts a local notification if a meaningful barometric pressure drop or
  AQI spike is forecast) and Personalized Insights (analytics computed locally over the user's own
  logged events). No Always-location, no servers, no accounts.
  ```

### 4. Version Information for v1.1.0

Go to App Store Connect → Your App → v1.1.0 → Version Information

- **What's New** (copy-paste):
  ```
  New: Pro tier (optional). Two new features for Pro subscribers and lifetime buyers:
  • Proactive Alerts — a heads-up when sharp barometric pressure drops or air-quality spikes are forecast.
  • Personalized Insights — see what conditions your headaches actually cluster around.
  Free version is unchanged. Try Pro free for 7 days.
  ```
- **Promotional Text** (optional):
  ```
  Log a headache in one tap and capture surrounding Health, time, and weather context. Pro shows you what triggers your headaches and pings you before risky days.
  ```

## Required: Privacy Policy page

- [x] Updated `docs/privacy-policy.html` with sections on In-App Purchases, Notifications, Background Location Use, and Forecast Data.

**Next step:** Commit and push the `docs/` folder so `https://jackwallner.github.io/headaches/privacy-policy.html` is live before submission. Add a sentence covering subscription auto-renewal terms if not already present.

## Recommended: Sandbox / TestFlight smoke test

### Simulator (StoreKit sandbox)

1. In Xcode: Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration → confirm `Products.storekit` is selected.
2. Build to a simulator. Open Settings → tap the locked "Proactive Alerts" row.
3. **Test subscription path:** select Yearly → tap "Start 7-Day Free Trial". Verify sandbox purchase succeeds, paywall dismisses, and the row navigates to the config screen.
4. **Test lifetime path:** Debug → StoreKit → Manage Transactions → delete the subscription. Re-open paywall, select Lifetime, complete purchase. Verify entitlement.
5. **Test restore:** delete the transaction again, then Restore Purchases from the paywall — entitlement should come back.
6. **Test "Manage Subscription":** with the subscription active, tap "Manage Subscription" in Settings → opens the system subscription management sheet.

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

- Pricing is set in App Store Connect, not in the app — the local `.storekit` price is only for dev. The displayed price in the paywall comes from `product.displayPrice`.
- The free trial is configured as an Introductory Offer on the subscription in App Store Connect — it must be enabled there for the paywall's "Start 7-Day Free Trial" copy to be accurate. The local `.storekit` already declares it for development.
- Both products belong to the same on-device entitlement: any verified, non-revoked transaction for either product unlocks Pro. The subscription's expiration is enforced by StoreKit — `Transaction.currentEntitlements` will stop yielding it on expiry.
