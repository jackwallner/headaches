#if os(iOS)
import Foundation
import WatchConnectivity

/// Receives “log headache” from the Watch companion (works even while iPhone onboarding is unfinished).
final class PhoneWatchSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    nonisolated(unsafe) static let shared = PhoneWatchSession()

    var onWatchRequestedCapture: ((Date) -> Void)?

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
            self?.handleHeadacheLogRequest(tapDate: tapDate)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["action"] as? String == "headacheLog" else {
            replyHandler(["status": "ignored"])
            return
        }
        let tapDate = Self.extractTimestamp(from: message)
        replyHandler(["status": "ok"])
        DispatchQueue.main.async { [weak self] in
            self?.handleHeadacheLogRequest(tapDate: tapDate)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard applicationContext["action"] as? String == "headacheLog" else { return }
        let tapDate = Self.extractTimestamp(from: applicationContext)
        DispatchQueue.main.async { [weak self] in
            self?.handleHeadacheLogRequest(tapDate: tapDate)
        }
    }

    private func handleHeadacheLogRequest(tapDate: Date) {
        onWatchRequestedCapture?(tapDate)
    }

    private static func extractTimestamp(from payload: [String: Any]) -> Date {
        if let interval = payload["timestamp"] as? Double {
            return Date(timeIntervalSince1970: interval)
        }
        return .now
    }
}
#endif
