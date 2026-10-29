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
    private var sendTimeoutTask: Task<Void, Never>?
    /// M15: prevent re-assigning the delegate / re-activating on every `onAppear`. The first
    /// successful activate "sticks"; repeated calls are cheap no-ops.
    private var didActivate = false

    func activate() {
        guard !didActivate else { return }
        guard WCSession.isSupported() else {
            statusMessage = String(localized: "Watch Connectivity unavailable.")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        didActivate = true
        lastLoggedDate = Self.loadLastLoggedDate()
    }

    func requestLogFromPhone() {
        guard !isSending else { return }

        let session = WCSession.default
        guard session.activationState == .activated else {
            statusMessage = String(localized: "Connecting to iPhone…")
            return
        }

        isSending = true
        armSendTimeout()
        let payload: [String: Any] = [
            "action": "headacheLog",
            "requestID": UUID().uuidString,
            "timestamp": Date.now.timeIntervalSince1970
        ]

        if session.isReachable {
            statusMessage = String(localized: "Sending…")
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self else { return }
                    self.cancelSendTimeout()
                    self.isSending = false
                    if reply["status"] as? String == "ok" {
                        self.confirmLogged(message: String(localized: "Logged."), showsConfirmation: true)
                    } else {
                        self.clearTask?.cancel()
                        self.showConfirmation = false
                        self.statusMessage = String(localized: "Could not save event. Try again.")
                    }
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.cancelSendTimeout()
                    self.isSending = false
                    self.clearTask?.cancel()
                    self.showConfirmation = false
                    self.statusMessage = String(localized: "Couldn't reach your iPhone. Try again.")
                    let fallbackSession = WCSession.default
                    if fallbackSession.activationState == .activated {
                        fallbackSession.transferUserInfo(payload)
                    }
                }
            })
        } else {
            cancelSendTimeout()
            queueForLater(payload: payload, session: session, fallbackError: nil)
            isSending = false
        }
    }

    /// C6: fall back after 10s if neither replyHandler nor errorHandler fires, so the Log button
    /// never stays disabled indefinitely (WC occasionally drops callbacks across session transitions).
    private func armSendTimeout() {
        sendTimeoutTask?.cancel()
        sendTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.isSending else { return }
            self.isSending = false
            self.clearTask?.cancel()
            self.showConfirmation = false
            self.statusMessage = String(localized: "Timed out. Try again.")
        }
    }

    private func cancelSendTimeout() {
        sendTimeoutTask?.cancel()
        sendTimeoutTask = nil
    }

    private func queueForLater(payload: [String: Any], session: WCSession, fallbackError: Error?) {
        guard session.activationState == .activated else {
            clearTask?.cancel()
            showConfirmation = false
            statusMessage = fallbackError == nil
                ? String(localized: "Connecting to iPhone…")
                : String(localized: "Couldn't reach your iPhone. Try again.")
            return
        }

        session.transferUserInfo(payload)
        confirmLogged(message: String(localized: "Queued. It will sync when your iPhone is nearby."), showsConfirmation: false)
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
        let isActivated = activationState == .activated
        Task { @MainActor [weak self] in
            guard let self else { return }
            if error != nil {
                self.statusMessage = String(localized: "Couldn't reach your iPhone. Try again.")
                return
            }
            // M14: clear any stale "Connecting to iPhone…" once the session is actually activated.
            if isActivated, self.statusMessage == String(localized: "Connecting to iPhone…") {
                self.statusMessage = nil
            }
        }
    }
}
