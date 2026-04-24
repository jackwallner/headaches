import SwiftData
import SwiftUI

@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published var bannerMessage: String?
    @Published var isCapturing = false
    @Published var lastCapturedEventID: UUID?
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
        guard HeadacheOnboardingStore.hasCompletedOnboarding || AppEnvironment.bypassOnboarding else { return }
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

    /// - Parameter fromWatch: Watch requests bypass the iPhone onboarding gate so logging works from the watch immediately.
    @discardableResult
    func captureHeadache(
        in context: ModelContext,
        fromWatch: Bool = false,
        watchTapDate: Date? = nil
    ) -> Bool {
        if !fromWatch {
            guard HeadacheOnboardingStore.hasCompletedOnboarding || AppEnvironment.bypassOnboarding else {
                bannerMessage = "Finish setup on your iPhone first."
                return false
            }
        }

        let event = HeadacheEvent(timestamp: watchTapDate ?? .now)
        context.insert(event)
        lastCapturedEventID = event.id

        do {
            try context.save()
        } catch {
            consoleError("CaptureCoordinator: initial save failed", error: error, trace: [:])
            lastCapturedEventID = nil
            bannerMessage = "Could not save event. Try again."
            return false
        }

        isCapturing = true
        bannerMessage = nil

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
                return
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
        bannerMessage = nil
        let timestamp = event.timestamp

        Task { @MainActor in
            let health = await HealthKitService.shared.captureSnapshot(at: timestamp)
            let environment = await EnvironmentService.shared.captureSnapshot(at: timestamp)

            var refetch = FetchDescriptor<HeadacheEvent>(predicate: #Predicate { $0.id == eventID })
            refetch.fetchLimit = 1
            guard let found = try? context.fetch(refetch).first else {
                isCapturing = false
                bannerMessage = "Retry failed — event missing."
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
                return
            }

            isCapturing = false

            switch found.captureStatus {
            case .complete:
                bannerMessage = "Context saved."
            case .partial:
                bannerMessage = "Still partial. You can email the developer from the event card."
            case .failed:
                bannerMessage = "Retry still failed. Email the developer from the event card."
            case .pending:
                bannerMessage = nil
            }
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
                bannerMessage = nil
            } catch {
                consoleError("CaptureCoordinator: undo save failed", error: error, trace: ["eventID": "\(eventID)"])
                bannerMessage = "Undo failed. Try again."
            }
        } else {
            lastCapturedEventID = nil
            bannerMessage = nil
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
        print(parts.joined(separator: " | "))
    }
}
