import Foundation
import WatchConnectivity
import WatchKit

/// Sends log requests to the paired iPhone (which runs capture with Health + location there).
@MainActor
final class WatchConnectivityController: NSObject, ObservableObject {
    @Published var statusMessage: String?
    @Published var showConfirmation = false
    private var clearTask: Task<Void, Never>?

    func activate() {
        guard WCSession.isSupported() else {
            statusMessage = "Watch Connectivity unavailable."
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func requestLogFromPhone() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            statusMessage = "Connecting to iPhone…"
            return
        }
        let payload: [String: Any] = [
            "action": "headacheLog",
            "requestID": UUID().uuidString,
            "timestamp": Date.now.timeIntervalSince1970
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] _ in
                Task { @MainActor in self?.confirmLogged() }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.clearTask?.cancel()
                    self?.showConfirmation = false
                    self?.statusMessage = error.localizedDescription
                }
            })
            statusMessage = "Sending…"
        } else {
            do {
                try session.updateApplicationContext(payload)
                confirmLogged()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func confirmLogged() {
        WKInterfaceDevice.current().play(.success)
        statusMessage = "Logged."
        showConfirmation = true
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
            self?.showConfirmation = false
        }
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
