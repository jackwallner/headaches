#if os(iOS)
import Foundation
import WatchConnectivity

/// Receives “log headache” from the Watch companion (works even while iPhone onboarding is unfinished).
final class PhoneWatchSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    nonisolated(unsafe) static let shared = PhoneWatchSession()

    /// C4: any tap dates received before the SwiftUI root view installs
    /// `onWatchRequestedCapture` are queued here (on main) and replayed as soon as the
    /// handler is assigned, so cold-start watch taps no longer fail with "Failed" on first tap.
    private var pendingTapDates: [Date] = []

    var onWatchRequestedCapture: ((Date) -> Bool)? {
        didSet {
            guard onWatchRequestedCapture != nil, !pendingTapDates.isEmpty else { return }
            let queued = pendingTapDates
            pendingTapDates.removeAll()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for date in queued {
                    _ = self.handleHeadacheLogRequest(tapDate: date)
                }
            }
        }
    }

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("PhoneWatchSession activation error: \(error)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["action"] as? String == "headacheLog" else { return }
        let tapDate = Self.extractTimestamp(from: message)
        DispatchQueue.main.async { [weak self] in
            _ = self?.handleHeadacheLogRequest(tapDate: tapDate)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["action"] as? String == "headacheLog" else {
            replyHandler(["status": "ignored"])
            return
        }
        let tapDate = Self.extractTimestamp(from: message)
        // C4/C5: always accept. The actual capture happens on main asynchronously; failures are
        // recovered by the re-enrichment sweep when the app next foregrounds (CaptureCoordinator
        // `enrichPendingCapturesIfNeeded`). Replying synchronously on the delegate's thread avoids
        // Swift 6's Sendable violation from dispatching a non-Sendable replyHandler across threads,
        // and eliminates the prior `DispatchQueue.main.sync` deadlock risk.
        DispatchQueue.main.async { [weak self] in
            _ = self?.handleHeadacheLogRequest(tapDate: tapDate)
        }
        replyHandler(["status": "ok"])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["action"] as? String == "headacheLog" else { return }
        let tapDate = Self.extractTimestamp(from: userInfo)
        DispatchQueue.main.async { [weak self] in
            _ = self?.handleHeadacheLogRequest(tapDate: tapDate)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard applicationContext["action"] as? String == "headacheLog" else { return }
        let tapDate = Self.extractTimestamp(from: applicationContext)
        DispatchQueue.main.async { [weak self] in
            _ = self?.handleHeadacheLogRequest(tapDate: tapDate)
        }
    }

    private func handleHeadacheLogRequest(tapDate: Date) -> Bool {
        if let handler = onWatchRequestedCapture {
            return handler(tapDate)
        }
        // C4: no handler yet (cold start from the Watch beat SwiftUI's onAppear). Queue the tap
        // and optimistically ack so the Watch shows success; the didSet on `onWatchRequestedCapture`
        // replays queued taps as soon as the root view installs its handler.
        pendingTapDates.append(tapDate)
        return true
    }

    private static func extractTimestamp(from payload: [String: Any]) -> Date {
        if let interval = payload["timestamp"] as? Double {
            return Date(timeIntervalSince1970: interval)
        }
        return .now
    }
}
#endif
