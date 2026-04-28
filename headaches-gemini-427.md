# Headache Logger - Bug Report & High-Level Fixes
**Date:** April 27, 2026

## Tier 1: Data Loss & Correctness (High Priority)

### 1. Watch Offline Queue Drops Logs
*   **Bug:** Offline Apple Watch logs use a static payload (`["action": "headacheLog"]`). Multiple taps overwrite the same pending context, resulting in lost data upon reconnection.
*   **High-Level Fix:** Inject a unique `requestID` (UUID) into the payload dictionary so every tap is distinct and queued by the system.

### 2. Incorrect Watch Timestamps
*   **Bug:** Watch events are timestamped upon phone receipt, not at the time of the actual watch tap.
*   **High-Level Fix:** Add a `timestamp` field to the watch payload. On the phone side, parse this and pass it into the `HeadacheEvent(timestamp:)` initializer instead of relying on `.now`.

### 3. Hidden Watch Delivery Errors
*   **Bug:** The Watch UI shows a success state ("Logged") immediately before delivery is confirmed. If it fails, the error message is hidden by the success UI logic.
*   **High-Level Fix:** Move the success UI update into the `replyHandler` for reachable sessions. In the `errorHandler`, ensure the view state actually displays the error description and hides the false success message.

---

## Tier 2: Save Reliability (Medium Priority)

### 4. Stale Undo State
*   **Bug:** If the initial database save of a new log fails, the UI still shows an "Undo Last Tap" button for an event that wasn't persisted.
*   **High-Level Fix:** Clear the `lastCapturedEventID` variable inside the `catch` block of the initial `context.save()`.

### 5. False Success Banners
*   **Bug:** If saving the enriched event (weather/health data) fails, the app still shows a "Context saved" success banner.
*   **High-Level Fix:** Gate the banner assignment on the success of the `try context.save()` operation, showing an error banner in the `catch` block.

### 6. Broken Retry on Undo
*   **Bug:** If deleting an event during an "Undo" operation fails to save, the app clears the undo state anyway, preventing the user from retrying.
*   **High-Level Fix:** Only clear `lastCapturedEventID` and hide the undo button if the deletion's `context.save()` is successful.

---

## Tier 3: Feature Gaps & Hardening (Low Priority)

### 7. CSV Formula Injection
*   **Bug:** Unsanitized user notes in CSV exports can trigger formula execution in spreadsheet software.
*   **High-Level Fix:** Prefix any note starting with `=`, `+`, `-`, or `@` with a single quote (`'`) during export string generation.

### 8. Silent History Deletion
*   **Bug:** Deleting history rows uses `try?`, completely hiding database save errors.
*   **High-Level Fix:** Replace `try?` with a proper `do/catch` block and add a `print` or minimal error handling for visibility.

### 9. Inefficient Widget Enrichment
*   **Bug:** The app fetches the entire history into memory to filter for pending widget logs.
*   **High-Level Fix:** Add a `#Predicate` to the SwiftData `FetchDescriptor` to filter rows at the database level.

### 10. AQI & Pollen Advertised but Hardcoded
*   **Bug:** 14 advertised environmental fields are hardcoded to `nil`.
*   **High-Level Fix:** Strip these claims from the UI and README immediately. Add `// TODO` comments to implement the Open-Meteo Air Quality API calls later.

### 11. Pressure Trend Always Unavailable
*   **Bug:** `pressureTrend` is hardcoded to `.unavailable` in both weather API paths.
*   **High-Level Fix:** Calculate the trend programmatically by comparing the current pressure to the historical pressure from a few hours prior.
