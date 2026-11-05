import SwiftUI

@main
struct SumiApp: App {
    @StateObject private var profiles = ProfileStore()
    @StateObject private var sources = SourceStore()

    var body: some Scene {
        WindowGroup {
            ProfileRootView(defaults: profiles.activeDefaults)
                .id(profiles.activeID)
                .defaultAppStorage(profiles.activeDefaults)
                .environmentObject(profiles)
                .font(Design.font(.body))
                .environmentObject(sources)
                .tint(Design.accent)
        }
    }
}

private struct ProfileRootView: View {
    @StateObject private var library: LibraryStore
    @AppStorage("appearance") private var appearance = "light"

    init(defaults: UserDefaults) {
        _library = StateObject(wrappedValue: LibraryStore(defaults: defaults))
    }

    var body: some View {
        RootView()
            .environmentObject(library)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
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
