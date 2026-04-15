import Foundation
@preconcurrency import WatchConnectivity
import WatchKit

/// Sends log requests to the paired iPhone (which runs capture with Health + location there).
@MainActor
final class WatchConnectivityController: NSObject, ObservableObject {
    @Published var statusMessage: String?
    @Published var showConfirmation = false
    @Published var isSending = false
    @Published var lastLoggedDate: Date?

    private var clearTask: Task<Void, Never>?

    func activate() {
        guard WCSession.isSupported() else {
            statusMessage = "Watch Connectivity unavailable."
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        lastLoggedDate = Self.loadLastLoggedDate()
    }

    func requestLogFromPhone() {
        guard !isSending else { return }

        let session = WCSession.default
        guard session.activationState == .activated else {
            statusMessage = "Connecting to iPhone…"
            return
        }

        isSending = true
        let payload: [String: Any] = [
            "action": "headacheLog",
            "requestID": UUID().uuidString,
            "timestamp": Date.now.timeIntervalSince1970
        ]

        if session.isReachable {
            statusMessage = "Sending…"
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self else { return }
                    self.isSending = false
                    if reply["status"] as? String == "ok" {
                        self.confirmLogged(message: "Logged.", showsConfirmation: true)
                    } else {
                        self.clearTask?.cancel()
                        self.showConfirmation = false
                        self.statusMessage = "Could not save event. Try again."
                    }
                }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isSending = false
                    let fallbackSession = WCSession.default
                    self.queueForLater(payload: payload, session: fallbackSession, fallbackError: error)
                }
            })
        } else {
            queueForLater(payload: payload, session: session, fallbackError: nil)
            isSending = false
        }
    }

    private func queueForLater(payload: [String: Any], session: WCSession, fallbackError: Error?) {
        guard session.activationState == .activated else {
            clearTask?.cancel()
            showConfirmation = false
            statusMessage = fallbackError?.localizedDescription ?? "Connecting to iPhone…"
            return
        }

        session.transferUserInfo(payload)
        confirmLogged(message: "Queued — will sync when iPhone is nearby.", showsConfirmation: false)
    }

    private func confirmLogged(message: String, showsConfirmation: Bool) {
        WKInterfaceDevice.current().play(.success)
        statusMessage = message
        showConfirmation = showsConfirmation

        let now = Date.now
        lastLoggedDate = now
        Self.saveLastLoggedDate(now)

        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
            self?.showConfirmation = false
        }
    }

    private static let lastLoggedKey = "lastWatchLoggedDate"

    private static func loadLastLoggedDate() -> Date? {
        let interval = HeadacheAppGroup.userDefaults.double(forKey: lastLoggedKey)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    private static func saveLastLoggedDate(_ date: Date) {
        HeadacheAppGroup.userDefaults.set(date.timeIntervalSince1970, forKey: lastLoggedKey)
    }
}

extension WatchConnectivityController: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            self?.statusMessage = error.localizedDescription
        }
    }
}
