# Headache Logger iOS App - Comprehensive Update Plan (sfix59)

**Generated:** 2026-04-15
**Scope:** Exhaustive user-focused review and update plan
**Status:** Planning phase - no code edits to be made

---

## Executive Summary

This plan synthesizes findings from:
- Existing bug reports (fixplan.md, claudefinds.md, gptfinds.md, kimifinds.md)
- Full codebase review of architecture, models, services, views, and utilities
- Watch and Widget implementations
- Testing coverage analysis
- Documentation and accessibility review

**Priority Categories:**
- **Tier 1 (Critical):** Data loss, crashes, save reliability
- **Tier 2 (High):** Feature gaps, misleading behavior, user experience issues
- **Tier 3 (Medium):** Code quality, documentation, performance optimizations

---

## Tier 1: Critical Fixes (Data Loss & Crashes)

### 1.1 Watch Offline Logging Data Loss
**Location:** `HeadacheLoggerWatch/WatchConnectivityController.swift`
**Issue:** Watch logs queued during offline periods may not be delivered to iPhone when connectivity restores. The current implementation uses `transferUserInfo` as a fallback but lacks:
- Explicit retry logic on session reactivation
- Persistence of queued requests across Watch app restarts
- User visibility into failed queued logs
**Impact:** Users lose headache logs when Watch is offline for extended periods
**Fix:** Implement persistent queue in Watch app with retry on session activation, show queued count in UI, add "Retry All" button

### 1.2 CaptureCoordinator Stale lastCapturedEventID
**Location:** `HeadacheLogger/Services/CaptureCoordinator.swift`
**Issue:** `lastCapturedEventID` is set before save confirmation. If the initial save fails but a subsequent retry succeeds, the ID may be stale, causing undo to target wrong event.
**Impact:** Undo may delete the wrong event
**Fix:** Only set `lastCapturedEventID` after successful save confirmation

### 1.3 HealthKit Force-Unwrap Crashes
**Location:** `HeadacheLogger/Services/HealthKitService.swift`
**Issue:** Lines 20-30 use force-unwrap (`!`) for HKObjectType creation. If HealthKit adds/removes types in future iOS versions, this will crash.
**Impact:** App crashes on iOS version changes
**Fix:** Use optional binding with graceful fallback to unavailable status

### 1.4 Silent Save Failures in History Delete
**Location:** `HeadacheLogger/Views/HistoryView.swift`
**Issue:** Delete operations use `try? context.save()` which silently fails on SwiftData errors. User sees no feedback but event may persist.
**Impact:** Users think events are deleted when they aren't
**Fix:** Show error banner on delete failure, use explicit error handling

### 1.5 Widget Intent Data Loss on Onboarding
**Location:** `HeadacheLoggerWidget/LogHeadacheIntent.swift`
**Issue:** If user taps widget before completing onboarding, the intent returns a dialog but doesn't persist the tap timestamp. When they complete onboarding, that log is lost.
**Impact:** Lost headache logs from widget taps during onboarding
**Fix:** Queue widget taps in app-group UserDefaults during onboarding, replay after completion

---

## Tier 2: High Priority (Feature Gaps & UX)

### 2.1 User Notes Length Limit
**Location:** `HeadacheLogger/Models/HeadacheEvent.swift`
**Issue:** No validation on `userNotes` field. Users can enter arbitrarily long text, causing:
- UI layout issues in HistoryView
- CSV export line breaks
- SwiftData performance degradation
**Impact:** Poor UX, potential data integrity issues
**Fix:** Add 500-character limit with character count UI, truncate at save with warning

### 2.2 Inefficient Widget Enrichment Query
**Location:** `HeadacheLogger/Services/CaptureCoordinator.swift`
**Issue:** `enrichPendingCapturesIfNeeded` fetches ALL pending events on every app foreground, even if only widget logs exist. With large datasets, this causes UI lag.
**Impact:** App feels slow on launch with many pending logs
**Fix:** Add batch limit (e.g., 10 events per enrichment pass), add "Enriching X more..." banner

### 2.3 Pressure Trend Unavailable for Early Morning Events
**Location:** `HeadacheLogger/Services/EnvironmentService.swift`
**Issue:** Pressure trend calculation requires 3 hours of prior data. Events before 03:00 local time show "unavailable" even when data exists (priorIdx < 0).
**Impact:** Misleading data for early risers
**Fix:** Already partially addressed by requesting previous day's hourly data, but verify edge cases around midnight timezone boundaries

### 2.4 Unpopulated AQI/Pollen Fields
**Location:** `HeadacheLogger/Services/EnvironmentService.swift`
**Issue:** Air quality and pollen data fail silently when Open-Meteo API returns nulls or network times out. No error message distinguishes "unavailable in region" from "network failure".
**Impact:** Users can't tell if their region lacks data or if it's a transient error
**Fix:** Add specific error messages for AQI/pollen failures, show "Not available in your region" vs "Network error"

### 2.5 Missing URLSession Timeouts
**Location:** `HeadacheLogger/Services/EnvironmentService.swift`
**Issue:** Weather requests have 8s timeout (C15), but air quality requests use default 60s timeout. On slow networks, this causes long hangs.
**Impact:** "Saving and collecting context…" banner spins for 60+ seconds
**Fix:** Apply 8s timeout to air quality requests as well

### 2.6 Temperature Precision Loss in UI
**Location:** `HeadacheLogger/Utilities/HeadacheTemperatureFormatting.swift`
**Issue:** Display uses integer formatting, losing precision for small temperature changes that matter for migraine patterns.
**Impact:** Users can't see subtle temperature variations
**Fix:** Add option for 1-decimal precision in Settings, default to integer for simplicity

### 2.7 Stale Location Status in Settings
**Location:** `HeadacheLogger/Views/SettingsView.swift`
**Issue:** Location authorization status is captured at view load and never refreshed. If user changes location permissions in Settings app, the status remains stale.
**Impact:** Misleading permission status
**Fix:** Refresh location status on view appearance, add "Refresh" button

### 2.8 Proactive Alerts No "Test Alert" Feature
**Location:** `HeadacheLogger/Views/ProAlertsConfigView.swift`
**Issue:** Users can't test if notifications are working without waiting for actual weather conditions.
**Impact:** Users disable alerts thinking they're broken when permissions are fine
**Fix:** Add "Send Test Alert" button that triggers a sample notification immediately

### 2.9 Insights No "Export Insights" Feature
**Location:** `HeadacheLogger/Views/InsightsView.swift`
**Issue:** Insights are only visible in-app. Users can't share patterns with clinicians without screenshots.
**Impact:** Reduced utility for medical conversations
**Fix:** Add "Export Insights Summary" button that generates a text summary or PDF

### 2.10 Severity Notes Sheet Timing
**Location:** `HeadacheLogger/Views/HomeView.swift`
**Issue:** Severity/notes sheet appears immediately after tap, interrupting the quick one-tap flow. Users who disabled the prompt still see it briefly.
**Impact:** Breaks the "one tap" promise
**Fix:** Add 0.5s delay before sheet presentation, or move to separate optional action

---

## Tier 3: Medium Priority (Code Quality & Documentation)

### 3.1 CSV Formula Injection Vulnerability
**Location:** `HeadacheLogger/Services/ExportService.swift`
**Issue:** Already partially addressed (M12) by prefixing cells starting with `=+-@` with `'`. Verify this covers all Excel formula injection vectors.
**Fix:** Review and test with additional malicious payloads

### 3.2 OneShotLocationManager Retain Cycle Risk
**Location:** `HeadacheLogger/Services/EnvironmentService.swift`
**Issue:** Self-retain pattern with timeout work item could theoretically leak if delegate callback and timeout race. Already mitigated by timeout (C14) but could be cleaner.
**Fix:** Consider using weak reference pattern or async/await instead of self-retain

### 3.3 PhoneWatchSession Data Race
**Location:** `HeadacheLogger/Services/PhoneWatchSession.swift`
**Issue:** `pendingTapDates` is accessed from multiple threads without synchronization. Already marked `@unchecked Sendable` (C4/C5) but true concurrency safety would be better.
**Fix:** Use actor or MainActor isolation for pendingTapDates

### 3.4 Sleep Wake Time Edge Cases
**Location:** `HeadacheLogger/Services/HealthKitService.swift`
**Issue:** Sleep query window (yesterday 18:00 → today 12:00) handles most cases but may have edge cases around timezone changes or daylight saving transitions.
**Fix:** Add unit tests for DST boundaries and timezone changes

### 3.5 Barometric Pressure Calculation
**Location:** `HeadacheLogger/Services/HealthKitService.swift`
**Issue:** Uses device samples for pressure delta. If user has no barometer-capable device, this is always nil. No fallback to weather API pressure data.
**Fix:** Consider using weather API pressure data as fallback when device samples unavailable

### 3.6 Temporary File Race Conditions
**Location:** `HeadacheLogger/Services/ExportService.swift`
**Issue:** CSV export writes to temp directory with timestamp-based filename. Concurrent exports could theoretically collide (unlikely but possible).
**Fix:** Use UUID instead of timestamp for filename

### 3.7 Testing Coverage Gaps
**Location:** `HeadacheLoggerTests/HeadacheLoggerTests.swift`
**Missing test coverage:**
- Watch connectivity scenarios
- Widget intent edge cases
- Proactive alerts evaluation logic
- Insights engine calculations
- Export service with various data states
- Background refresh scheduling
**Fix:** Add comprehensive test suite for these areas

### 3.8 Documentation Improvements
**Missing documentation:**
- Architecture overview diagram
- Data flow diagram (Watch → iPhone → SwiftData)
- Pro alerts algorithm explanation
- Insights calculation methodology
- Error handling strategy
**Fix:** Add technical documentation in `/docs` folder

### 3.9 Code Comments
**Location:** Throughout codebase
**Issue:** Some complex algorithms (e.g., pressure trend calculation, sleep interval merging) lack inline comments explaining the logic.
**Fix:** Add explanatory comments for non-obvious algorithms

### 3.10 Accessibility Labels
**Location:** All View files
**Issue:** Many UI elements lack `.accessibilityLabel()` and `.accessibilityHint()`. Dynamic VoiceOver announcements may be unclear.
**Fix:** Add accessibility labels to all interactive elements, test with VoiceOver

### 3.11 Localization
**Location:** Throughout codebase
**Issue:** All strings are hardcoded in English. No `Localizable.strings` files.
**Fix:** Extract all user-facing strings to localization files, add support for multiple languages

### 3.12 Performance: Large Dataset Queries
**Location:** `HeadacheLogger/Views/HistoryView.swift`
**Issue:** Uses `@Query` without fetch limit or pagination. With 1000+ events, this may cause scrolling lag.
**Fix:** Implement lazy loading or pagination for history view

### 3.13 Error Banner Persistence
**Location:** `HeadacheLogger/Services/CaptureCoordinator.swift`
**Issue:** Banner messages are shown once and disappear. Users may miss error messages.
**Fix:** Add error log view in Settings where past errors can be reviewed

### 3.14 Undo Button Availability
**Location:** `HeadacheLogger/Views/HomeView.swift`
**Issue:** Undo button is only available when `lastCapturedEventID` is set. If user backgrounds app during capture, undo may be unavailable.
**Fix:** Persist `lastCapturedEventID` to app-group UserDefaults, restore on app launch

### 3.15 Paywall Recovery After Failed Purchase
**Location:** `HeadacheLogger/Services/StoreKitService.swift`
**Issue:** If purchase fails due to network error, user sees error but may not retry. No clear path to restore purchases.
**Fix:** Add "Troubleshooting" section in paywall with restore purchase guidance

---

## UI/UX Improvements

### 4.1 Onboarding Flow
**Location:** `HeadacheLogger/Views/OnboardingView.swift`
**Improvements:**
- Add progress indicator (e.g., "Step 1 of 4")
- Allow skipping Health/Location permissions with clear explanation
- Add "Finish Later" option that saves progress
**Rationale:** Some users may want to explore app before granting permissions

### 4.2 Home Visual Hierarchy
**Location:** `HeadacheLogger/Views/HomeView.swift`
**Improvements:**
- Make "Headache" button more prominent (larger, centered)
- Reduce visual weight of "What Gets Captured" section
- Move "Undo" to secondary position
**Rationale:** Primary action should be most prominent

### 4.3 History View Filtering
**Location:** `HeadacheLogger/Views/HistoryView.swift`
**Improvements:**
- Add severity filter (Slight/Medium/Extreme)
- Add capture status filter (Complete/Partial/Failed)
- Add search by notes text
**Rationale:** Users need to find specific events for pattern analysis

### 4.4 Insights Visualization
**Location:** `HeadacheLogger/Views/InsightsView.swift`
**Improvements:**
- Add tap-to-expand for insight details
- Add "Compare to baseline" visualization
- Add trend line for severity over time
**Rationale:** Current charts are static; interactivity would increase utility

### 4.5 Settings Organization
**Location:** `HeadacheLogger/Views/SettingsView.swift`
**Improvements:**
- Group related settings into collapsible sections
- Add search functionality
- Add "Reset All Settings" option
**Rationale:** Settings list is growing and may become unwieldy

### 4.6 Pro Alerts UI
**Location:** `HeadacheLogger/Views/ProAlertsConfigView.swift`
**Improvements:**
- Add visual preview of alert notification
- Show "Last alert fired: X hours ago"
- Add sensitivity presets (Low/Medium/High)
**Rationale:** Users need feedback on whether alerts are working

### 4.7 Watch App Polish
**Location:** `HeadacheLoggerWatch/WatchRootView.swift`
**Improvements:**
- Add haptic feedback on successful log
- Add complication support
- Add "Quick Settings" for severity
**Rationale:** Watch app is minimal; could be more useful

### 4.8 Widget Variants
**Location:** `HeadacheLoggerWidget/HeadacheLoggerWidget.swift`
**Improvements:**
- Add medium widget with recent log count
- Add large widget with latest event details
- Add intent configuration for severity
**Rationale:** More widget options increase utility

---

## Pro Features Enhancements

### 5.1 Proactive Alerts
**Enhancements:**
- Add humidity-based alerts
- Add weather front detection
- Add multiple alert types per day
- Add alert history log
**Rationale:** Current alerts only cover pressure and AQI

### 5.2 Personalized Insights
**Enhancements:**
- Add correlation analysis (e.g., "High humidity + low HRV = 80% of headaches")
- Add prediction confidence scores
- Add time-series trend charts
- Add "What to watch for" recommendations
**Rationale:** Current insights are descriptive; predictive insights would be more valuable

### 5.3 Export Options
**Enhancements:**
- Add PDF export with charts
- Add JSON export for developers
- Add selective export (date range, filters)
- Add automatic weekly/monthly email export
**Rationale:** Current CSV export is basic; more options increase utility

---

## Technical Debt

### 6.1 Swift 6 Concurrency
**Status:** Code uses `@unchecked Sendable` and `@preconcurrency` in several places (PhoneWatchSession, WatchConnectivityController, BGTaskBox).
**Action:** Plan migration to full Swift 6 concurrency safety once Apple stabilizes the APIs

### 6.2 Dependency Management
**Status:** No package manager (SwiftPM, CocoaPods, Carthage) in use. All dependencies are Apple frameworks.
**Action:** Consider adding SwiftPM for shared utilities if codebase grows

### 6.3 SwiftData Schema Versioning
**Status:** No migration strategy for schema changes.
**Action:** Add schema versioning and migration plan before adding new fields

### 6.4 Error Handling Consistency
**Status:** Mix of `try?`, `try!`, and explicit error handling.
**Action:** Standardize on explicit error handling with user-facing messages

### 6.5 Logging Strategy
**Status:** Debug-only print statements, no structured logging.
**Action:** Add os_signpost or structured logging for production debugging

---

## Security & Privacy

### 7.1 Data-at-Rest Encryption
**Current:** No encryption for SwiftData store.
**Recommendation:** Consider adding Data Protection capability for encrypted storage

### 7.2 Network Security
**Current:** Open-Meteo uses HTTPS, no certificate pinning.
**Recommendation:** Current is acceptable for free public API; pinning not necessary

### 7.3 Privacy Policy Clarity
**Current:** Privacy policy exists but could be more detailed about:
- What data is stored
- How long data is retained
- Data deletion process
**Recommendation:** Update privacy policy with these details

---

## Testing Strategy

### 8.1 Unit Tests
**Current:** 18 tests covering basic functionality.
**Target:** 50+ tests covering:
- All service layer functions
- Model validation
- Utility functions
- Edge cases

### 8.2 Integration Tests
**Current:** None.
**Target:** Add integration tests for:
- End-to-end capture flow
- Watch → iPhone sync
- Widget → Main app enrichment
- StoreKit purchase flow

### 8.3 UI Tests
**Current:** Basic UI test support via `AppEnvironment.isUITesting`.
**Target:** Add UI tests for:
- Onboarding flow
- Main logging flow
- Settings navigation
- Export functionality

### 8.4 Performance Tests
**Current:** None.
**Target:** Add performance tests for:
- Large dataset queries (1000+ events)
- Widget enrichment batch processing
- CSV export with 1000+ rows

---

## Implementation Priority

**Phase 1 (Immediate - 1-2 weeks):**
- All Tier 1 fixes (critical data loss/crashes)
- User notes length limit
- Missing URLSession timeouts

**Phase 2 (Short-term - 1 month):**
- Tier 2 UX improvements (onboarding, home view, history filtering)
- Pro alerts test feature
- Widget variants
- Accessibility labels

**Phase 3 (Medium-term - 2-3 months):**
- Insights enhancements
- Export options
- Localization
- Testing coverage expansion

**Phase 4 (Long-term - 3-6 months):**
- Pro features expansion
- Technical debt reduction
- Performance optimization
- Documentation

---

## Success Metrics

**Data Integrity:**
- Zero data loss events in production
- <0.1% save failure rate
- 100% undo accuracy

**User Experience:**
- <2s time from tap to save confirmation
- <1s app launch time
- <3s widget enrichment completion
- 4.5+ App Store rating

**Code Quality:**
- 80%+ test coverage
- Zero compiler warnings
- Zero SwiftLint violations
- <5s unit test suite execution

---

## Notes

- This plan is based on static code review and existing bug reports
- Some recommendations may need validation through user testing
- Priorities should be adjusted based on user feedback and production metrics
- Always test changes on both iOS 17 and iOS 18 when available
- Consider beta testing phase for major feature additions

---

**End of Plan**
