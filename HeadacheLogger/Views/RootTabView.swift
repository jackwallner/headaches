import SwiftUI

struct RootTabView: View {
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @StateObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tag(0)
            .tabItem {
                Label("One Tap", systemImage: "brain.head.profile")
            }

            NavigationStack {
                HistoryView()
            }
            .tag(1)
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                InsightsView()
            }
            .tag(2)
            .tabItem {
                Label("Patterns", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                SettingsView()
            }
            .tag(3)
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
        .preferredColorScheme(AppAppearance.from(storageValue: appearanceRaw).preferredColorScheme)
        .onAppear { reviewPromptCoordinator.isOnHomeTab = selectedTab == 0 }
        .onChange(of: selectedTab) { _, tab in
            reviewPromptCoordinator.isOnHomeTab = tab == 0
        }
    }
}
