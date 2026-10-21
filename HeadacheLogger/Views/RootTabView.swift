import SwiftUI

struct RootTabView: View {
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @StateObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var selectedTab = Self.initialTab
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The container's width and fold, measured so the unfolded iPhone Duo can
    /// put One Tap and History on opposite sides of the fold.
    @State private var paneGeometry = PaneGeometry()
    /// History's year filter, owned here because History moves between its tab
    /// and its own pane when the Duo folds or unfolds.
    @State private var historyYear: Int?

    private static var initialTab: Int {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-HeadacheScreenshotPatterns") {
            return 2
        }
        #endif
        return 0
    }

    /// Unfolded, History has its own pane beside One Tap, so it is never a tab.
    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(
            width: paneGeometry.width,
            isRegularWidth: horizontalSizeClass == .regular,
            fold: paneGeometry.fold
        )
    }

    /// Each unfolded pane is phone-width, so its screen lays out as on a phone.
    /// Applied to the tab contents, not the `TabView`, whose own bar placement
    /// is left to the system.
    private var paneSizeClass: UserInterfaceSizeClass? {
        split == nil ? horizontalSizeClass : .compact
    }

    var body: some View {
        // Opening or closing the Duo only moves these frames, so the tab view is
        // never rebuilt. History's year lives here for its move between tab and pane.
        ZStack(alignment: .topLeading) {
            tabs
                .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)
            if let split {
                NavigationStack { HistoryView(selectedYear: $historyYear) }
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(width: split.secondaryWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, split.secondaryX)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { paneGeometry = $0 }
        .onChange(of: split != nil) { _, isSplit in
            if isSplit, selectedTab == 1 { selectedTab = 0 }
        }
        #if DEBUG
        .task { await runDuoTour() }
        #endif
        .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
        .preferredColorScheme(AppAppearance.from(storageValue: appearanceRaw).preferredColorScheme)
        .onAppear { reviewPromptCoordinator.isOnHomeTab = selectedTab == 0 }
        .onChange(of: selectedTab) { _, tab in
            reviewPromptCoordinator.isOnHomeTab = tab == 0
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .environment(\.horizontalSizeClass, paneSizeClass)
            .tag(0)
            .tabItem {
                Label(HeadacheBrand.name, systemImage: "brain.head.profile")
            }

            if split == nil {
                NavigationStack {
                    HistoryView(selectedYear: $historyYear)
                }
                .environment(\.horizontalSizeClass, paneSizeClass)
                .tag(1)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }

            NavigationStack {
                InsightsView()
            }
            .environment(\.horizontalSizeClass, paneSizeClass)
            .tag(2)
            .tabItem {
                Label("Patterns", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                SettingsView()
            }
            .environment(\.horizontalSizeClass, paneSizeClass)
            .tag(3)
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
    }

    #if DEBUG
    /// `-HeadacheDuoTour`: walks the main screens for headless capture runs,
    /// which can't tap and whose `simctl openurl` stops on a confirmation alert.
    /// Moves one stop every 22 s from launch (gh-sim relaunches after
    /// unfolding): folded History, Patterns, a pattern's detail and Settings;
    /// unfolded, where History already has its own pane, Patterns, the detail,
    /// Settings and back to One Tap. `HEADACHEDUOTOUR` lines map shots to stops.
    private func runDuoTour() async {
        guard ProcessInfo.processInfo.arguments.contains("-HeadacheDuoTour") else { return }
        let start = ContinuousClock.now
        for step in 0..<4 {
            try? await Task.sleep(until: start + .seconds(22 * (step + 1)), clock: .continuous)
            guard !Task.isCancelled else { return }
            let isSplit = split != nil
            NSLog("HEADACHEDUOTOUR t=%ld split=%ld step=%ld", 22 * (step + 1), isSplit ? 1 : 0, step)
            withAnimation(.easeInOut(duration: 0.3)) {
                switch (isSplit, step) {
                case (false, 0): selectedTab = 1
                case (false, 1), (true, 0): selectedTab = 2
                case (false, 2), (true, 1):
                    NotificationCenter.default.post(name: .headacheDebugShowFirstPattern, object: nil)
                case (true, 3): selectedTab = 0
                default: selectedTab = 3
                }
            }
        }
    }
    #endif
}
