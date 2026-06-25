# Fix Plan

**Generated:** April 14, 2026
**Method:** Cross-referenced kimifinds.md (30 bugs), claudefinds.md (7 validated), gptfinds.md (11 found) against actual source code. Each item below is independently verified.

---

## Verdict Summary

| Source | Total Reported | Confirmed Real | False Positive | Enhancement/Not Bug |
|--------|---------------|----------------|----------------|---------------------|
| Kimi   | 28 bugs       | 6              | 16             | 6                   |
| Claude | 7 bugs        | 7              | 0              | 0                   |
| GPT    | 11 bugs       | 11             | 0              | 0                   |

**Unique confirmed bugs across all three reports: 11**

Claude was the most accurate — zero false positives, but missed 4 real bugs that GPT caught (save-path failures in CaptureCoordinator and the watch timestamp gap). Kimi had the widest net but a ~57% false-positive rate. GPT found the most unique real bugs.

---

## Tier 1 — Data Loss / User-Facing Correctness (fix now)

### FIX-1: Watch offline queue drops repeat logs
**File:** `HeadacheLoggerWatch/WatchConnectivityController.swift:27,37`
**Reported by:** Kimi (BUG-011), Claude (BUG-A), GPT (#1)
**Severity:** High

`updateApplicationContext` only delivers when the dictionary changes. The payload is always `["action": "headacheLog"]` — identical every time. A second offline tap is a no-op; the phone never sees it.

**Fix:** Add a unique key so every tap produces a distinct dictionary:
```swift
let payload: [String: Any] = [
    "action": "headacheLog",
    "requestID": UUID().uuidString,
    "timestamp": Date.now.timeIntervalSince1970
]
```
**Effort:** ~5 min. One-line change + phone-side parsing.

---

### FIX-2: Watch events get the wrong timestamp
**File:** `HeadacheLoggerWatch/WatchConnectivityController.swift:27` → `HeadacheLogger/Services/CaptureCoordinator.swift:61`
**Reported by:** GPT (#2) only — missed by Kimi and Claude
**Severity:** High

The watch sends no timestamp. The phone creates `HeadacheEvent()` which defaults to `Date.now` — the phone's receive time, not the watch tap time. Delayed delivery = wrong event time.

**Fix:** Include `Date.now.timeIntervalSince1970` in the watch payload (pairs with FIX-1). On the phone side, pass it through to `HeadacheEvent(timestamp:)`:
```swift
// Phone side — in PhoneWatchSession or CaptureCoordinator:
let watchTimestamp = Date(timeIntervalSince1970: payload["timestamp"] as? Double ?? Date.now.timeIntervalSince1970)
let event = HeadacheEvent(timestamp: watchTimestamp)
```
**Effort:** ~15 min. Touch watch payload, PhoneWatchSession delegate, CaptureCoordinator.

---

### FIX-3: Watch shows success before delivery confirmed; errors hidden
**File:** `HeadacheLoggerWatch/WatchConnectivityController.swift:28-56`
**Reported by:** Kimi (BUG-010), Claude (BUG-B), GPT (#3)
**Severity:** High

`confirmLogged()` fires immediately after `sendMessage`. If the message fails, the errorHandler sets `statusMessage` but the view guard `!session.showConfirmation` hides it. Then the 4-second clearTask wipes everything. The user never sees the error.

**Fix:** Move `confirmLogged()` into a reply handler (for reachable path). For the error path, cancel the clear task and show the error:
```swift
session.sendMessage(payload, replyHandler: { _ in
    Task { @MainActor [weak self] in self?.confirmLogged() }
}, errorHandler: { error in
    Task { @MainActor [weak self] in
        self?.clearTask?.cancel()
        self?.showConfirmation = false
        self?.statusMessage = error.localizedDescription
    }
})
```
For the offline `updateApplicationContext` path, `confirmLogged()` is acceptable since the system guarantees eventual delivery (once FIX-1 is applied).

**Effort:** ~15 min.

---

## Tier 2 — Save Reliability (fix soon)

### FIX-4: Initial save failure leaves stale lastCapturedEventID → bogus Undo button
**File:** `HeadacheLogger/Services/CaptureCoordinator.swift:61-71`
**Reported by:** GPT (#4) only
**Severity:** Medium

`lastCapturedEventID` is set before `context.save()`. If save fails, the ID isn't cleared. The UI shows "Undo Last Tap" for an event that was never persisted.

**Fix:** Clear the ID in the catch block:
```swift
} catch {
    consoleError(...)
    lastCapturedEventID = nil
    bannerMessage = "Could not save event. Try again."
    return
}
```
**Effort:** 1 line.

---

### FIX-5: Final capture save failure still shows success banner
**File:** `HeadacheLogger/Services/CaptureCoordinator.swift:100-117`
**Reported by:** GPT (#5) only
**Severity:** Medium

After enrichment, if `context.save()` fails, the code falls through to the success banner switch. The user sees "Context saved." when it wasn't.

**Fix:** Gate the banner on save success:
```swift
do {
    try context.save()
} catch {
    consoleError(...)
    isCapturing = false
    bannerMessage = "Context captured but save failed. Reopen to retry."
    return
}
```
**Effort:** ~5 min.

---

### FIX-6: Undo clears lastCapturedEventID even when delete save fails
**File:** `HeadacheLogger/Services/CaptureCoordinator.swift:121-137`
**Reported by:** GPT (#6) only
**Severity:** Low

If `context.save()` fails after `context.delete()`, `lastCapturedEventID` is set to nil anyway. The user loses the ability to retry.

**Fix:** Only clear the ID on save success:
```swift
do {
    try context.save()
    lastCapturedEventID = nil
    bannerMessage = nil
} catch {
    consoleError(...)
    bannerMessage = "Undo failed. Try again."
}
```
**Effort:** ~5 min.

---

## Tier 3 — Feature Gaps & Hardening (fix when ready)

### FIX-7: AQI and pollen fields never populated
**File:** `HeadacheLogger/Services/EnvironmentService.swift:152-165`
**Reported by:** Kimi (BUG-025), Claude (BUG-C), GPT (#9)
**Severity:** Medium

All 14 AQI/pollen fields are hardcoded to `nil`. README line 5, 18-19, and the tech stack table advertise these features. The UI shows "AQI: —" on every event.

**Fix:** Either:
- **(a)** Add a second Open-Meteo call to `air-quality-api.open-meteo.com` and populate the fields, or
- **(b)** Remove the claims from README, hide the AQI pill from HistoryView, and add a `// TODO` until the feature ships.

Option (b) is a 15-minute fix. Option (a) is ~2-3 hours of real feature work.

**Recommendation:** Ship (b) now, implement (a) in a follow-up.

---

### FIX-8: Pressure trend always `.unavailable`
**File:** `HeadacheLogger/Services/EnvironmentService.swift:280, 412`
**Reported by:** Kimi (BUG-024), Claude (BUG-D), GPT (#10)
**Severity:** Low

Both fetch paths hardcode `pressureTrend: .unavailable`. The field flows through the model, CSV, and README as always unavailable.

**Fix:** Compute trend from the hourly pressure data already fetched in `fetchHourlySlot` (compare pressure at event hour vs 3 hours prior), or from HealthKit barometric samples. Alternatively, mark as "coming soon" in docs.

**Effort:** ~1 hour if computed from hourly data.

---

### FIX-9: Widget enrichment fetches all events, filters in memory
**File:** `HeadacheLogger/Services/CaptureCoordinator.swift:19-24`
**Reported by:** Kimi (BUG-013), Claude (BUG-F), GPT (#8)
**Severity:** Low

No `#Predicate` in `FetchDescriptor` — loads every row, then filters with `.filter {}`.

**Fix:** Add a predicate to push filtering to SQLite:
```swift
let healthPending = HeadacheWidgetQuickLog.healthMessagePending
let envPending = HeadacheWidgetQuickLog.environmentMessagePending
var descriptor = FetchDescriptor<HeadacheEvent>(
    predicate: #Predicate { $0.healthStatusMessage == healthPending && $0.environmentStatusMessage == envPending },
    sortBy: [SortDescriptor(\HeadacheEvent.timestamp, order: .forward)]
)
```
**Effort:** ~10 min.

---

### FIX-10: CSV formula injection in user notes
**File:** `HeadacheLogger/Services/ExportService.swift:174-178`
**Reported by:** Kimi (BUG-008), Claude (BUG-E), GPT (#11)
**Severity:** Low

Notes starting with `=`, `+`, `-`, `@` inside quoted CSV can be interpreted as formulas by Excel. OWASP CWE-1236.

**Fix:** Prefix with a tab or single-quote when the first character is a formula trigger:
```swift
private static func csv(_ value: String?) -> String {
    let raw = value ?? ""
    let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
    let safe = escaped.first.map({ "=+-@".contains($0) }) == true ? "'" + escaped : escaped
    return "\"\(safe)\""
}
```
**Effort:** 2 lines.

---

### FIX-11: History delete ignores save failure
**File:** `HeadacheLogger/Views/HistoryView.swift:105-109`
**Reported by:** Kimi (BUG-018), Claude (BUG-G), GPT (#7)
**Severity:** Low

`try? modelContext.save()` discards errors silently.

**Fix:** Replace with `do/catch` and surface an alert:
```swift
private func deleteEvents(at offsets: IndexSet) {
    for index in offsets {
        modelContext.delete(events[index])
    }
    do {
        try modelContext.save()
    } catch {
        // optionally show alert or let SwiftData autosave retry
        print("HistoryView: delete save failed | \(error)")
    }
}
```
**Effort:** ~5 min.

---

## What NOT to fix (confirmed false positives)

These were reported by Kimi but correctly debunked by Claude and/or GPT:

| Kimi ID | Claim | Why Not a Bug |
|---------|-------|---------------|
| BUG-001/002/003 | HealthKit force-unwraps | Stable identifiers since iOS 8-13; app targets iOS 17+. Code already uses optional variants for newer types. |
| BUG-004 | Widget intent data loss | If `insertQuickLog()` throws, the intent re-throws; success dialog is never reached. |
| BUG-005 | OneShotLocationManager hang | Apple guarantees `requestLocation()` calls either `didUpdateLocations` or `didFailWithError`. All auth states handled. |
| BUG-006 | Widget enrichment race condition | Guard blocks re-entry; second pass finds zero pending events. Harmless. |
| BUG-007 | HealthKit query timeout | Apple guarantees HealthKit query completion handlers fire. |
| BUG-009 | PhoneWatchSession data race | Both callback assignment and invocation happen on main thread. |
| BUG-012 | Temperature precision loss | 2 decimal places exceeds clinical thermometer precision (0.1°F). |
| BUG-014 | Sleep wake time edge case | Sub-second equality between different timestamp sources is effectively impossible. |
| BUG-015 | Barometric delta requires 2 samples | Computing a delta mathematically requires two values. Returning nil for 1 sample is correct. |
| BUG-016/028 | Export file race | `UIActivityViewController` copies data before presenting; temp file not needed after dismiss. |
| BUG-017 | Settings status stale | Already refreshes in `.onAppear`. |
| BUG-019 | Notes no length limit | Enhancement, not a bug. No standard iOS text editor enforces limits. |
| BUG-020 | URLSession no custom timeout | Enhancement. 60s default is reasonable. |
| BUG-021 | No retry logic | `fetchWeatherNearestTo` already chains 3 fallback API calls. |
| BUG-022 | Timezone mismatch | `timezone=auto` resolves from coordinates — correct for weather at a physical location. |
| BUG-023 | createdAt vs timestamp | Intentionally different by design. |

---

## Execution Order

| Order | Fix | Files Touched | Est. Time |
|-------|-----|---------------|-----------|
| 1 | FIX-1 + FIX-2 (combine) | WatchConnectivityController, PhoneWatchSession, CaptureCoordinator | 30 min |
| 2 | FIX-3 | WatchConnectivityController | 15 min |
| 3 | FIX-4 | CaptureCoordinator | 2 min |
| 4 | FIX-5 | CaptureCoordinator | 5 min |
| 5 | FIX-6 | CaptureCoordinator | 5 min |
| 6 | FIX-10 | ExportService | 2 min |
| 7 | FIX-9 | CaptureCoordinator | 10 min |
| 8 | FIX-11 | HistoryView | 5 min |
| 9 | FIX-7b (remove claims) | README, HistoryView | 15 min |
| 10 | FIX-8 | EnvironmentService | 1 hour |

**Total estimated: ~2.5 hours for all 11 fixes.**
Tier 1 (FIX 1-3) alone takes ~45 min and addresses all data-loss scenarios.

---

*End of plan.*
