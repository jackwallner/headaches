# Proactive Alerts (Paid Feature) - Exhaustive Implementation Plan

This document provides a highly detailed, step-by-step technical blueprint for implementing **Proactive Alerts (Predictive Trigger Warnings)**. It acts as the explicit specification for the AI agent to follow without human intervention.

---

## Phase 1: Project Configuration & Entitlements

Before writing code, the Xcode workspace must be configured to support StoreKit, Background Processing, and Location.

### 1.1 Entitlements (`HeadacheLogger/HeadacheLogger.entitlements`)
Add the following keys to support background tasks and StoreKit testing:
```xml
<key>com.apple.developer.storekit.testing</key>
<true/> <!-- Remove or switch to false for App Store release -->
```

### 1.2 Info.plist (`HeadacheLogger/Info.plist`)
Modify the `Info.plist` to explicitly declare background processing capabilities and update location privacy descriptions.

```xml
<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>

<!-- Background Task Identifiers -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.jackwallner.headachelogger.weatherCheck</string>
</array>

<!-- Location Privacy (Always Auth Required for Background Weather) -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Headache Logger Pro needs your location in the background to check the local weather forecast and alert you of sudden barometric pressure drops or pollen spikes before a headache strikes. Your location is never stored or tracked.</string>
```

---

## Phase 2: StoreKit 2 & Paywall Implementation

Implement Apple's modern `StoreKit 2` framework to handle the "Pro" unlock status entirely on-device, preserving the "no accounts" philosophy.

### 2.1 StoreKit Configuration (`Products.storekit`)
Create a local StoreKit Configuration File in Xcode to test purchases locally.
*   **Type:** Non-Consumable (or Auto-Renewable Subscription).
*   **Product ID:** `com.jackwallner.headachelogger.pro.lifetime`
*   **Price:** $9.99 (Example)

### 2.2 `StoreKitService.swift`
Create a singleton class in `HeadacheLogger/Services/StoreKitService.swift` to manage transactions and entitlement state.

```swift
import Foundation
import StoreKit

@MainActor
class StoreKitService: ObservableObject {
    @Published var isProUnlocked: Bool = false
    @Published var products: [Product] = []

    private let proProductId = "com.jackwallner.headachelogger.pro.lifetime"
    private var updates: Task<Void, Never>? = nil

    init() {
        updates = newTransactionListenerTask()
        Task {
            await fetchProducts()
            await updateCustomerProductStatus()
        }
    }

    deinit {
        updates?.cancel()
    }

    func fetchProducts() async {
        do {
            products = try await Product.products(for: [proProductId])
        } catch {
            print("Failed product fetch: \(error)")
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateCustomerProductStatus()
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func updateCustomerProductStatus() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.productID == proProductId {
                    isProUnlocked = true
                }
            } catch {
                // Transaction unverified
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func newTransactionListenerTask() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateCustomerProductStatus()
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification")
                }
            }
        }
    }
}
enum StoreError: Error { case failedVerification }
```

### 2.3 `PaywallView.swift`
Create `HeadacheLogger/Views/PaywallView.swift`.
*   Inject `StoreKitService` via `@EnvironmentObject`.
*   Design a clean UI explaining the features: "Proactive Alerts", "Custom Sensitivity", "Predictive Weather Polling".
*   Include standard StoreKit buttons: "Purchase", "Restore Purchases", and links to Privacy Policy / Terms of Service.

---

## Phase 3: Data Models & Persistence

Extend `SwiftData` to store the user's Pro Alert settings locally.

### 3.1 `ProAlertPreferences.swift`
Create `HeadacheLogger/Models/ProAlertPreferences.swift`. This will be a new `@Model` or simply stored in `UserDefaults` depending on complexity. Since it's a 1-to-1 user setting, `UserDefaults` via `@AppStorage` is actually cleaner and perfectly sufficient, preventing SwiftData migration complexities.

```swift
import SwiftUI

class ProAlertPreferences: ObservableObject {
    @AppStorage("pro_alerts_enabled") var alertsEnabled: Bool = false
    @AppStorage("pro_alert_pressure_drop_threshold") var pressureDropThreshold: Double = 3.0 // hPa drop over 12h
    @AppStorage("pro_alert_pollen_enabled") var pollenEnabled: Bool = true
    @AppStorage("pro_alert_aqi_threshold") var aqiThreshold: Int = 100 // Alert if AQI > 100
    @AppStorage("pro_quiet_hours_enabled") var quietHoursEnabled: Bool = true
    @AppStorage("pro_quiet_hours_start") var quietHoursStart: Double = 22.0 // 10 PM
    @AppStorage("pro_quiet_hours_end") var quietHoursEnd: Double = 7.0 // 7 AM
}
```

---

## Phase 4: The Background Engine

This is the core of the feature. It runs when the app is closed.

### 4.1 `BackgroundRefreshService.swift`
Create `HeadacheLogger/Services/BackgroundRefreshService.swift` to handle the `BGAppRefreshTask`.

```swift
import BackgroundTasks
import CoreLocation
import UserNotifications

class BackgroundRefreshService {
    static let shared = BackgroundRefreshService()
    let weatherCheckIdentifier = "com.jackwallner.headachelogger.weatherCheck"

    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: weatherCheckIdentifier, using: nil) { task in
            self.handleWeatherCheck(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleNextCheck() {
        let request = BGAppRefreshRequest(identifier: weatherCheckIdentifier)
        // Schedule for 3 hours from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    private func handleWeatherCheck(task: BGAppRefreshTask) {
        // Schedule the next check right away
        scheduleNextCheck()

        // Set an expiration handler
        task.expirationHandler = {
            // Cancel networking tasks if time runs out
        }

        Task {
            let triggered = await evaluateTriggers()
            if triggered {
                await sendNotification()
            }
            task.setTaskCompleted(success: true)
        }
    }

    // Logic goes here (detailed in Phase 5)
}
```

### 4.2 App Delegate Integration
Since the app uses SwiftUI `App` lifecycle, we need an `AppDelegate` to register background tasks on launch. Update `HeadacheLoggerApp.swift`.

```swift
import SwiftUI
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        BackgroundRefreshService.shared.registerTasks()
        return true
    }
}

@main
struct HeadacheLoggerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var storeKitService = StoreKitService()

    // ... existing setup ...
}
```

---

## Phase 5: Trigger Evaluation & Open-Meteo Forecasting

Modify the existing `EnvironmentService.swift` to support fetching the *hourly forecast* in addition to current conditions.

### 5.1 Open-Meteo Forecast Query
Currently, the app fetches `current`. Update the URL builder to include `hourly`:
*   **Parameters:** `hourly=temperature_2m,surface_pressure,pm2_5,aqi`
*   **Forecast Days:** `forecast_days=2` (To get the next 24-48 hours).

### 5.2 `evaluateTriggers()` Logic
In `BackgroundRefreshService`:
1.  **Check Permissions:** Ensure Location ("Always") and Notifications are granted.
2.  **Get Location:** Fetch a single coordinate from `CLLocationManager` silently.
3.  **Fetch Forecast:** Call `EnvironmentService` to get the next 12 hours of data.
4.  **Pressure Delta:**
    *   Find max pressure in the next 12h.
    *   Find min pressure occurring *after* the max pressure.
    *   If `(max - min) >= ProAlertPreferences.pressureDropThreshold`, set `trigger = true`.
5.  **Pollen/AQI Check:**
    *   If any hourly AQI value > `ProAlertPreferences.aqiThreshold`, set `trigger = true`.

### 5.3 Notification Scheduling
```swift
func sendNotification() async {
    let content = UNMutableNotificationContent()
    content.title = "High Headache Risk Today"
    content.body = "A rapid drop in barometric pressure is forecast for your area."
    content.sound = .default

    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil) // Fire immediately
    try? await UNUserNotificationCenter.current().add(request)
}
```

---

## Phase 6: Settings UI Integration

### 6.1 Pro Toggles in Settings
Update `HeadacheLogger/Views/SettingsView.swift`:
1.  Check `storeKitService.isProUnlocked`.
2.  If false, display a locked "Proactive Alerts" row that presents `.sheet(isPresented: $showPaywall) { PaywallView() }`.
3.  If true, display a `NavigationLink` to `ProAlertsConfigView`.

### 6.2 `ProAlertsConfigView.swift`
A simple SwiftUI Form bound to the `@AppStorage` keys defined in Phase 3.1.
*   **Location Prompt:** When enabled for the first time, explicitly request `requestAlwaysAuthorization()` and `UNUserNotificationCenter.requestAuthorization()`.

---

## Phase 7: Testing Strategy

Because background tasks are notoriously difficult to test naturally, use the debugger trick.

1.  Set a breakpoint in `handleWeatherCheck(task:)`.
2.  Run the app on a physical device.
3.  Pause the debugger and execute the following LLDB command to simulate an iOS background wake:
    `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.jackwallner.headachelogger.weatherCheck"]`
4.  Resume execution and verify the weather fetch, trigger logic, and notification delivery.
