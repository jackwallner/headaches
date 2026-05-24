import SwiftData
import SwiftUI
import CoreMotion

@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published var bannerMessage: String?
    /// True when `bannerMessage` describes a failure, so the UI can show a warning
    /// rather than a success affordance.
    @Published var bannerIsError = false
    @Published var isCapturing = false
    @Published var lastCapturedEventID: UUID?
    /// True once any monetization surface (trial offer, Pro intro, or milestone card) has
    /// appeared in *this* app session. Both the Home milestone card and the root-level trial
    /// offer read this so only one Pro moment shows per session. Reset on cold launch.
    @Published var proPromptShownThisSession = false
    /// Prevents overlapping widget-enrichment passes (e.g. `onAppear` + scene `active` firing together).
    private var isEnrichingWidgetLogs = false

    /// Catches two classes of un-enriched rows on app foreground:
    ///   1. Widget quick-logs (both sources `.unavailable` with the widget sentinel messages) — widget extensions
    ///      cannot run HealthKit or network queries, so enrichment always happens here later.
    ///   2. Watch-initiated captures (or main-app captures) where the enrichment Task was interrupted by the app being
    ///      backgrounded/killed; those rows stay at `healthStatus == .pending && environmentStatus == .pending`.
    ///
    /// Enrichment uses the **event's own timestamp**, never `now`, so HealthKit / weather context reflects the tap time.
    /// Oldest first so a backlog of widget taps resolves in order.
    func enrichPendingCapturesIfNeeded(in context: ModelContext) {
        guard !isCapturing else { return }
        guard !isEnrichingWidgetLogs else { return }

        let pending = fetchPendingEvents(in: context)
        guard !pending.isEmpty else { return }

        isEnrichingWidgetLogs = true
        Task { @MainActor in
            defer { isEnrichingWidgetLogs = false }
            var updated = 0
            for event in pending {
                let t = event.timestamp
                let health = await HealthKitService.shared.captureSnapshot(at: t)
                let environment = await EnvironmentService.shared.captureSnapshot(at: t)
                event.apply(health)
                event.apply(environment)
                event.finalizeCapture()
                do {
                    try context.save()
                    updated += 1
                } catch {
                    consoleError("enrichPendingCaptures: save failed", error: error, trace: ["id": "\(event.id)"])
                }
            }
            if updated > 0 {
                bannerMessage = updated == 1 ? "Updated context for a pending log." : "Updated context for \(updated) pending logs."
                bannerIsError = false
                await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
            }
        }
    }

    /// Extracted so unit tests can verify the predicate covers widget-sentinel rows AND watch-orphaned
    /// `.pending` rows without invoking HealthKit / network. Public `internal` for `@testable` reach.
    nonisolated static func pendingCaptureFetchDescriptor() -> FetchDescriptor<HeadacheEvent> {
        let healthPending = HeadacheWidgetQuickLog.healthMessagePending
        let envPending = HeadacheWidgetQuickLog.environmentMessagePending
        let pendingRaw = CaptureSourceStatus.pending.rawValue
        return FetchDescriptor<HeadacheEvent>(
            predicate: #Predicate { event in
                (event.healthStatusRaw == pendingRaw && event.environmentStatusRaw == pendingRaw)
                || (event.healthStatusMessage == healthPending && event.environmentStatusMessage == envPending)
            },
            sortBy: [SortDescriptor(\HeadacheEvent.timestamp, order: .forward)]
        )
    }

    private func fetchPendingEvents(in context: ModelContext) -> [HeadacheEvent] {
        (try? context.fetch(Self.pendingCaptureFetchDescriptor())) ?? []
    }

    @discardableResult
    func captureHeadache(
        in context: ModelContext,
        watchTapDate: Date? = nil
    ) -> Bool {
        let event = HeadacheEvent(timestamp: watchTapDate ?? .now)
        context.insert(event)

        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawBattery = UIDevice.current.batteryLevel
        event.batteryLevelPercent = rawBattery >= 0 ? Double(rawBattery * 100) : nil
        event.isCharging = rawBattery >= 0 ? UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full : nil
        event.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        Task {
            let activity = await currentMotionActivity()
            event.motionActivity = activity
        }
        lastCapturedEventID = event.id

        do {
            try context.save()
        } catch {
            consoleError("CaptureCoordinator: initial save failed", error: error, trace: [:])
            lastCapturedEventID = nil
            bannerMessage = "Could not save event. Try again."
            bannerIsError = true
            return false
        }

        isCapturing = true
        bannerMessage = "Saving and collecting context…"
        bannerIsError = false

        let eventID = event.id
        let timestamp = event.timestamp

        Task { @MainActor in
            // Serialize Health then environment so two permission / heavy queries never race on first launch.
            let health = await HealthKitService.shared.captureSnapshot(at: timestamp)
            let environment = await EnvironmentService.shared.captureSnapshot(at: timestamp)

            var descriptor = FetchDescriptor<HeadacheEvent>(
                predicate: #Predicate { $0.id == eventID }
            )
            descriptor.fetchLimit = 1

            guard let found = try? context.fetch(descriptor).first else {
                isCapturing = false
                bannerMessage = "Could not update event."
                bannerIsError = true
                consoleError("CaptureCoordinator: fetch after capture failed", error: nil, trace: ["eventID": "\(eventID)"])
                return
            }

            found.apply(health)
            found.apply(environment)
            found.finalizeCapture()

            do {
                try context.save()
            } catch {
                consoleError("CaptureCoordinator: finalize save failed", error: error, trace: ["eventID": "\(eventID)"])
                isCapturing = false
                bannerMessage = "Context captured but save failed. Reopen to retry."
                bannerIsError = true
                return
            }

            isCapturing = false

            bannerIsError = false
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

            await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        }

        return true
    }

    /// Re-runs Health + environment capture for an already-saved event so the user can recover from a
    /// partial / failed first-pass (e.g. a single HealthKit sub-query erroring out on a metric they've
    /// never logged). Uses the event's own `timestamp`, so context reflects the original tap, not `now`.
    func retryCapture(eventID: UUID, in context: ModelContext) {
        guard !isCapturing else { return }

        var descriptor = FetchDescriptor<HeadacheEvent>(predicate: #Predicate { $0.id == eventID })
        descriptor.fetchLimit = 1
        guard let event = try? context.fetch(descriptor).first else {
            bannerMessage = "Could not find event to retry."
            return
        }

        isCapturing = true
        bannerMessage = "Retrying context capture…"
        bannerIsError = false
        let timestamp = event.timestamp

        Task { @MainActor in
            let health = await HealthKitService.shared.captureSnapshot(at: timestamp)
            let environment = await EnvironmentService.shared.captureSnapshot(at: timestamp)

            var refetch = FetchDescriptor<HeadacheEvent>(predicate: #Predicate { $0.id == eventID })
            refetch.fetchLimit = 1
            guard let found = try? context.fetch(refetch).first else {
                isCapturing = false
                bannerMessage = "Retry failed. Event missing."
                bannerIsError = true
                return
            }

            found.apply(health)
            found.apply(environment)
            found.finalizeCapture()

            do {
                try context.save()
            } catch {
                consoleError("CaptureCoordinator: retry save failed", error: error, trace: ["eventID": "\(eventID)"])
                isCapturing = false
                bannerMessage = "Retry captured context but save failed."
                bannerIsError = true
                return
            }

            isCapturing = false

            switch found.captureStatus {
            case .complete:
                bannerMessage = "Context saved."
                bannerIsError = false
            case .partial:
                bannerMessage = "Still partial. You can email the developer from the event card."
                bannerIsError = true
            case .failed:
                bannerMessage = "Retry still failed. Email the developer from the event card."
                bannerIsError = true
            case .pending:
                bannerMessage = nil
                bannerIsError = false
            }

            await ProactiveAlertsEngine.schedulePatternAlertsIfEnabled(in: context)
        }
    }

    func undoLastCapture(in context: ModelContext) {
        guard let eventID = lastCapturedEventID else { return }

        var descriptor = FetchDescriptor<HeadacheEvent>(predicate: #Predicate { $0.id == eventID })
        descriptor.fetchLimit = 1

        if let event = try? context.fetch(descriptor).first {
            context.delete(event)
            do {
                try context.save()
                lastCapturedEventID = nil
                bannerMessage = "Last entry undone."
                bannerIsError = false
            } catch {
                consoleError("CaptureCoordinator: undo save failed", error: error, trace: ["eventID": "\(eventID)"])
                bannerMessage = "Undo failed. Try again."
                bannerIsError = true
            }
        } else {
            lastCapturedEventID = nil
            bannerMessage = nil
        }
    }

    private func currentMotionActivity() async -> MotionActivity? {
        guard CMMotionActivityManager.isActivityAvailable() else { return nil }
        return await withCheckedContinuation { continuation in
            let manager = CMMotionActivityManager()
            let now = Date()
            manager.queryActivityStarting(from: now.addingTimeInterval(-600), to: now, to: .main) { activities, error in
                guard error == nil, let latest = activities?.last else {
                    continuation.resume(returning: nil)
                    return
                }
                let activity: MotionActivity
                if latest.stationary { activity = .stationary }
                else if latest.automotive { activity = .automotive }
                else if latest.cycling { activity = .cycling }
                else if latest.running { activity = .running }
                else if latest.walking { activity = .walking }
                else { activity = .unknown }
                continuation.resume(returning: activity)
            }
        }
    }

    private func consoleError(_ message: String, error: Error?, trace: [String: String]) {
        var parts = [message]
        if let error {
            parts.append(String(describing: error))
        }
        if !trace.isEmpty {
            parts.append(trace.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }
        #if DEBUG
        print(parts.joined(separator: " | "))
        #endif
    }
}
