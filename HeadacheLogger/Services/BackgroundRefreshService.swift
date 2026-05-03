import BackgroundTasks
import Foundation

/// Schedules and runs the periodic forecast check that powers Proactive Alerts.
final class BackgroundRefreshService: Sendable {
    static let shared = BackgroundRefreshService()
    static let weatherCheckIdentifier = "com.jackwallner.headachelogger.weatherCheck"

    /// Aim for ~3 hour intervals; iOS may run us more or less often based on usage.
    private let earliestInterval: TimeInterval = 3 * 60 * 60

    private init() {}

    /// Must be called from `application(_:didFinishLaunchingWithOptions:)` — registering after
    /// launch silently no-ops and the background task will never fire.
    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.weatherCheckIdentifier, using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(task: task)
        }
    }

    func scheduleNextCheck() {
        let request = BGAppRefreshTaskRequest(identifier: Self.weatherCheckIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskSchedulerErrorDomain.unavailable is expected on simulator and fine.
            print("BackgroundRefreshService.schedule failed: \(error)")
        }
    }

    private func handle(task: BGAppRefreshTask) {
        // Always queue the next run before doing work so a crash doesn't stop the cycle.
        scheduleNextCheck()

        // BGAppRefreshTask isn't Sendable, but iOS only delivers it to one handler at a time and
        // we only call `setTaskCompleted` from a single Task. Wrap so Swift 6 strict concurrency
        // is satisfied without changing Apple's API contract.
        let box = BGTaskBox(task: task)
        let work = Task {
            let fired = await ProactiveAlertsEngine.runIfEligible()
            box.task.setTaskCompleted(success: fired || !Task.isCancelled)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }
}

private struct BGTaskBox: @unchecked Sendable {
    let task: BGAppRefreshTask
}
