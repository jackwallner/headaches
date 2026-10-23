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
        if let screen = DuoScreen.requested { return screen.tab }
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
                    .environment(\.isUnfoldedPane, true)
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
            .leadingPaneTab(sizeClass: paneSizeClass, isSplit: split != nil)
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
            .leadingPaneTab(sizeClass: paneSizeClass, isSplit: split != nil)
            .tag(2)
            .tabItem {
                Label("Patterns", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                SettingsView()
            }
            .leadingPaneTab(sizeClass: paneSizeClass, isSplit: split != nil)
            .tag(3)
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
    }
}

private extension View {
    /// A tab in the leading pane: a phone layout and phone bars, with its
    /// screens clear of the floating tab bar while split.
    func leadingPaneTab(sizeClass: UserInterfaceSizeClass?, isSplit: Bool) -> some View {
        environment(\.horizontalSizeClass, sizeClass)
            .environment(\.isUnfoldedPane, isSplit)
            .horizontalBarsInPane(isSplit)
    }
}

#if DEBUG
/// `-HeadacheDuoScreen <name>`: the surface a capture run opens at launch, read
/// once (gh-sim relaunches per `--screen`, folded and unfolded). `pattern`
/// opens Patterns and pushes the top pattern's detail.
enum DuoScreen: String {
    case log, history, patterns, pattern, settings

    static let requested = UserDefaults.standard.string(forKey: "HeadacheDuoScreen").flatMap(DuoScreen.init)

    var tab: Int {
        switch self {
        case .log: 0
        case .history: 1
        case .patterns, .pattern: 2
        case .settings: 3
        }
    }
}
#endif
