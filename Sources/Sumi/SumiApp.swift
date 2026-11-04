import SwiftUI

@main
struct SumiApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var sources = SourceStore()
    @AppStorage("appearance") private var appearance = "light"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(sources)
                .tint(Design.accent)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
        }
    }
}

struct RootView: View {
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView().tag(0).tabItem { Label("Library", systemImage: "books.vertical") }
            DiscoverView().tag(1).tabItem { Label("Discover", systemImage: "sparkle.magnifyingglass") }
            UpdatesView().tag(2).tabItem { Label("Updates", systemImage: "clock") }
            OfflineView().tag(3).tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            SettingsView().tag(4).tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}
