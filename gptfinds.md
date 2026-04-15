# GPT Finds — Fresh Validated Bugs

**Generated:** April 14, 2026  
**Method:** Fresh source audit of the current codebase. This report includes only issues I can justify directly from the code and call paths.

---

## Summary

I found **11 legitimate bugs / defects worth fixing**.

These are not speculative platform-hardening suggestions. Each item below is backed by a concrete code path that can:
- lose or distort user data
- report success incorrectly
- fail to persist user actions
- create misleading product behavior
- advertise fields the code never actually produces

---

## 1. Offline Apple Watch logging does not actually queue multiple events
**Severity:** High  
**Files:**
- `HeadacheLoggerWatch/WatchConnectivityController.swift:27-38`
- `HeadacheLogger/Services/PhoneWatchSession.swift:44-52`
- `README.md:21`

### Proof
The offline path sends a single app-context payload:

```swift
let payload = ["action": "headacheLog"]
try session.updateApplicationContext(payload)
```

The phone only reacts to the latest application context:

```swift
func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    guard applicationContext["action"] as? String == "headacheLog" else { return }
    DispatchQueue.main.async { [weak self] in
        self?.handleHeadacheLogRequest()
    }
}
```

There is no queue, array, timestamp list, or unique request ID. The payload represents only one pending state.

### Why this is a bug
The README says watch entries "queue and sync automatically," but this implementation cannot represent multiple offline watch taps. If the user logs more than once while the phone is unavailable, the extra taps are not preserved as distinct events.

---

## 2. Watch-originated events get the wrong timestamp
**Severity:** High  
**Files:**
- `HeadacheLoggerWatch/WatchConnectivityController.swift:27`
- `HeadacheLogger/HeadacheLoggerApp.swift:34-35`
- `HeadacheLogger/Services/CaptureCoordinator.swift:61`
- `HeadacheLogger/Models/HeadacheEvent.swift:190-195`

### Proof
The watch sends no timestamp:

```swift
let payload = ["action": "headacheLog"]
```

The phone then creates a new event with the default initializer:

```swift
captureCoordinator.captureHeadache(in: modelContext, fromWatch: true)
```

```swift
let event = HeadacheEvent()
```

```swift
init(timestamp: Date = .now) {
    self.timestamp = timestamp
    self.createdAt = .now
}
```

### Why this is a bug
A watch tap is timestamped when the **phone receives** the request, not when the **watch user tapped**. If delivery is delayed, the recorded event time is wrong.

---

## 3. Watch shows success before delivery is confirmed, and failures are effectively hidden
**Severity:** High  
**Files:**
- `HeadacheLoggerWatch/WatchConnectivityController.swift:28-56`
- `HeadacheLoggerWatch/WatchRootView.swift:28-33`

### Proof
Reachable path:

```swift
session.sendMessage(payload, replyHandler: nil, errorHandler: { error in
    Task { @MainActor [weak self] in
        self?.statusMessage = error.localizedDescription
    }
})
confirmLogged()
```

`confirmLogged()` immediately does:

```swift
statusMessage = "Logged."
showConfirmation = true
```

But the UI only renders `statusMessage` when confirmation is not showing:

```swift
if let message = session.statusMessage, !session.showConfirmation {
    Text(message)
}
```

### Why this is a bug
The watch gives success haptics and a success label before receipt is confirmed. If `sendMessage` later fails, the error text is assigned while `showConfirmation == true`, so it is hidden by the view logic and then cleared by the 4-second reset task.

That means a failed delivery can look like a successful log.

---

## 4. Initial save failure leaves a stale `lastCapturedEventID`, causing a bogus Undo option
**Severity:** Medium  
**Files:**
- `HeadacheLogger/Services/CaptureCoordinator.swift:61-70`
- `HeadacheLogger/Views/HomeView.swift:61-67`

### Proof
During capture:

```swift
let event = HeadacheEvent()
context.insert(event)
lastCapturedEventID = event.id

do {
    try context.save()
} catch {
    bannerMessage = "Could not save event. Try again."
    return
}
```

In the UI:

```swift
if captureCoordinator.lastCapturedEventID != nil {
    Button("Undo Last Tap") {
        captureCoordinator.undoLastCapture(in: modelContext)
    }
}
```

### Why this is a bug
If the initial save fails, `lastCapturedEventID` is not cleared. The app can show `Undo Last Tap` even though nothing was ever persisted.

---

## 5. Final capture save failure is reported to the user as success
**Severity:** Medium  
**File:** `HeadacheLogger/Services/CaptureCoordinator.swift:96-117`

### Proof
After applying health/environment data:

```swift
do {
    try context.save()
} catch {
    consoleError("CaptureCoordinator: finalize save failed", error: error, trace: ["eventID": "\(eventID)"])
}

isCapturing = false

switch found.captureStatus {
case .complete:
    bannerMessage = "Context saved."
case .partial:
    bannerMessage = "Saved with partial context."
case .failed:
    bannerMessage = "Saved; some context unavailable."
case .pending:
    bannerMessage = nil
}
```

### Why this is a bug
Even when `context.save()` fails, the app still shows a success-style banner based on the in-memory object state. That tells the user the enriched event was saved when it may not have been.

---

## 6. Undo can fail to persist, but the app still clears the only retry handle
**Severity:** Medium  
**File:** `HeadacheLogger/Services/CaptureCoordinator.swift:121-137`

### Proof
```swift
if let event = try? context.fetch(descriptor).first {
    context.delete(event)
    do {
        try context.save()
    } catch {
        consoleError("CaptureCoordinator: undo save failed", error: error, trace: ["eventID": "\(eventID)"])
    }
}

lastCapturedEventID = nil
bannerMessage = nil
```

### Why this is a bug
If the delete save fails, the event may still exist on disk, but `lastCapturedEventID` is cleared anyway. The user loses the ability to retry undo from the app state.

---

## 7. History delete ignores save failures completely
**Severity:** Low  
**File:** `HeadacheLogger/Views/HistoryView.swift:105-109`

### Proof
```swift
private func deleteEvents(at offsets: IndexSet) {
    for index in offsets {
        modelContext.delete(events[index])
    }
    try? modelContext.save()
}
```

### Why this is a bug
`try?` suppresses the error entirely. If the save fails, the app gives no feedback. The row can disappear in current UI state but come back later after reload.

---

## 8. Widget enrichment fetches every event, then filters in memory
**Severity:** Low  
**File:** `HeadacheLogger/Services/CaptureCoordinator.swift:19-24`

### Proof
```swift
let pending: [HeadacheEvent] = (try? context.fetch(FetchDescriptor<HeadacheEvent>(
    sortBy: [SortDescriptor(\HeadacheEvent.timestamp, order: .forward)]
)))?.filter { event in
    event.healthStatusMessage == HeadacheWidgetQuickLog.healthMessagePending
        && event.environmentStatusMessage == HeadacheWidgetQuickLog.environmentMessagePending
} ?? []
```

### Why this is a bug
There is no predicate in the fetch descriptor, so this loads **all events** and filters in memory. As history grows, app foreground enrichment does unnecessary work every time.

---

## 9. AQI and pollen are advertised but never populated
**Severity:** Medium  
**Files:**
- `HeadacheLogger/Services/EnvironmentService.swift:152-165`
- `README.md:18-19`
- `HeadacheLogger/Views/HomeView.swift:159-160`
- `HeadacheLogger/Views/HistoryView.swift:243`

### Proof
Environment snapshot hardcodes these fields to `nil`:

```swift
usAQI: nil,
europeanAQI: nil,
pm25: nil,
pm10: nil,
ozone: nil,
nitrogenDioxide: nil,
sulphurDioxide: nil,
carbonMonoxide: nil,
alderPollen: nil,
birchPollen: nil,
grassPollen: nil,
mugwortPollen: nil,
olivePollen: nil,
ragweedPollen: nil
```

The UI and docs still surface these fields/features.

### Why this is a bug
The product claims air quality and pollen capture, but the current source never populates those values. This is not just future work hidden from the UI — it is visible and documented as if working now.

---

## 10. Pressure trend is always `unavailable`
**Severity:** Low  
**Files:**
- `HeadacheLogger/Services/EnvironmentService.swift:280`
- `HeadacheLogger/Services/EnvironmentService.swift:412`
- `README.md:17`

### Proof
Current weather path:

```swift
pressureTrend: .unavailable,
```

Hourly historical path:

```swift
pressureTrend: .unavailable,
```

### Why this is a bug
The model, export, and docs all treat pressure trend as a real captured field, but the fetch layer hardcodes it to unavailable in both code paths.

---

## 11. CSV export is vulnerable to spreadsheet formula injection via notes
**Severity:** Low  
**File:** `HeadacheLogger/Services/ExportService.swift:174-177`

### Proof
```swift
private static func csv(_ value: String?) -> String {
    let raw = value ?? ""
    let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
}
```

User-controlled notes flow straight into CSV:

```swift
csv(event.userNotes)
```

### Why this is a bug
Quoted CSV cells beginning with `=`, `+`, `-`, or `@` can be interpreted as formulas by spreadsheet software. Since `userNotes` is arbitrary text, exported CSV can contain formula payloads.

---

## Excluded as not clearly bugs
I intentionally did **not** include these categories:
- hypothetical crashes based on Apple removing long-stable HealthKit identifiers
- generic network retry/timeouts without a concrete broken state in current code
- `createdAt` vs `timestamp` semantic differences that look intentional
- file-cleanup timing claims that are not provable from this source alone
- SwiftData autosave concerns without a demonstrated failing path

---

## Priority order
1. **Watch offline queue bug**
2. **Watch timestamp loss**
3. **Watch false-success / hidden error path**
4. **Finalize save still reports success**
5. **Initial save failure leaves bogus Undo state**
6. **Undo clears retry handle even on save failure**
7. **AQI/pollen never populated**
8. **Pressure trend always unavailable**
9. **History delete silent failure**
10. **Widget enrichment full-table fetch**
11. **CSV formula injection hardening**

---

*End of report.*
