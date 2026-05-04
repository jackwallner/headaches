import SwiftData
import SwiftUI
import UIKit

@main
struct HeadacheLoggerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var captureCoordinator = CaptureCoordinator()
    @StateObject private var storeKitService = StoreKitService()

    var body: some Scene {
        WindowGroup {
            HeadacheLoggerRootContent()
                .environmentObject(captureCoordinator)
                .environmentObject(storeKitService)
        }
        .modelContainer(HeadacheModelStore.sharedModelContainer)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundRefreshService.shared.registerTasks()
        return true
    }
}

/// Hosts onboarding vs main UI and always wires Watch → phone capture so the watch can log before iPhone onboarding finishes.
private struct HeadacheLoggerRootContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator
    @EnvironmentObject private var storeKitService: StoreKitService
    @AppStorage(HeadacheStorageKey.hasCompletedOnboarding.rawValue, store: HeadacheAppGroup.userDefaults) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if AppEnvironment.bypassOnboarding || hasCompletedOnboarding {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            #if os(iOS)
            PhoneWatchSession.shared.onWatchRequestedCapture = { [captureCoordinator] tapDate in
                captureCoordinator.captureHeadache(
                    in: modelContext,
                    fromWatch: true,
                    watchTapDate: tapDate
                )
            }
            if !AppEnvironment.isUITesting {
                PhoneWatchSession.shared.start()
            }
            #endif
            runWidgetEnrichmentIfReady()
            scheduleBackgroundIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                runWidgetEnrichmentIfReady()
            } else if phase == .background {
                scheduleBackgroundIfNeeded()
            }
        }
        .onChange(of: storeKitService.isProUnlocked) { _, _ in
            scheduleBackgroundIfNeeded()
        }
    }

    private func runWidgetEnrichmentIfReady() {
        guard AppEnvironment.bypassOnboarding || hasCompletedOnboarding else { return }
        captureCoordinator.enrichPendingCapturesIfNeeded(in: modelContext)
    }

    private func scheduleBackgroundIfNeeded() {
        guard storeKitService.isProUnlocked else { return }
        let prefs = ProAlertPreferenceValues.current()
        guard prefs.alertsEnabled else { return }
        BackgroundRefreshService.shared.scheduleNextCheck()
    }
}
