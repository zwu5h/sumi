import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var sources: SourceStore
    @State private var query = ""
    private var results: [InstalledSource] {
        sources.installed.filter { query.isEmpty || $0.manifest.name.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GlassSearch(text: $query, prompt: "Search sources")
                    NavigationLink { SourcesView() } label: {
                        Label("Manage sources", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered)
                    if sources.installed.isEmpty {
                        ContentUnavailableView("No sources", systemImage: "network", description: Text("Add a source to browse and save manga."))
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ForEach(results) { source in
                            NavigationLink { SourceCatalogView(sourceID: source.id) } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "books.vertical").foregroundStyle(Design.accent)
                                    Text(source.manifest.name).font(Design.font(.headline)).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }.padding(20).frame(minHeight: 64).glassSurface()
                            }.buttonStyle(PressStyle())
                        }
                    }
                }.padding(Design.spacing).frame(maxWidth: 840).frame(maxWidth: .infinity)
            }.pageBackground().navigationTitle("Discover")
                .scrollDismissesKeyboard(.interactively)
        }
    }
}

struct UpdatesView: View {
    @EnvironmentObject private var store: LibraryStore
    private var titles: [Manga] { store.library.filter { $0.remote != nil } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if titles.isEmpty {
                        ContentUnavailableView("No saved manga", systemImage: "bookmark", description: Text("Save manga from Discover to find their chapters here."))
                    } else {
                        Text("Open a manga to refresh its chapters.")
                            .font(Design.font(.subheadline)).foregroundStyle(.secondary)
                        ForEach(titles) { manga in
                            NavigationLink { MangaDetailView(manga: manga) } label: {
                                HStack(spacing: 16) {
                                    CoverArt(manga: manga).frame(width: 64, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text(manga.title).font(Design.font(.headline)).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(Design.font(.caption)).foregroundStyle(.secondary)
                                }.padding(.vertical, 8)
                            }.buttonStyle(PressStyle())
                            Divider()
                        }
                    }
                }.padding(Design.spacing).frame(maxWidth: 840).frame(maxWidth: .infinity)
            }.pageBackground().navigationTitle("Updates")
        }
    }
}

struct OfflineView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var toRemove: Manga?
    var body: some View {
        NavigationStack {
            List {
                Section("Imported PDFs · \(store.imported.count)") {
                    if store.imported.isEmpty {
                        ContentUnavailableView("No downloads", systemImage: "arrow.down.document", description: Text("Import PDFs with + in Library."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(store.imported) { manga in
                        NavigationLink(value: manga) {
                            HStack(spacing: 14) {
                                CoverArt(manga: manga).frame(width: 48, height: 68).clipShape(RoundedRectangle(cornerRadius: 5))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(manga.title).font(Design.font(.headline))
                                }
                            }.padding(.vertical, 10)
                        }.swipeActions {
                            Button("Delete", role: .destructive) { toRemove = manga }
                        }.listRowBackground(Color.clear)
                    }
                }
            }.listStyle(.insetGrouped).scrollContentBackground(.hidden).pageBackground().navigationTitle("Downloads")
                .navigationDestination(for: Manga.self) { MangaDetailView(manga: $0) }
                .confirmationDialog("Delete imported manga?", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }), titleVisibility: .visible) {
                    Button("Delete from this device", role: .destructive) {
                        if let manga = toRemove { store.removeImport(manga) }; toRemove = nil
                    }
                } message: { Text("This removes the imported PDF and its reading progress. Your original file is unchanged.") }
                .alert("Couldn’t delete the document", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("verticalReading") private var verticalReading = false
    @AppStorage("rightToLeft") private var rightToLeft = true
    @AppStorage("hideControls") private var hideControls = true
    @AppStorage("keepAwake") private var keepAwake = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    QuietPanel {
                        NavigationLink { SourcesView() } label: {
                            Label("Sources & repositories", systemImage: "network").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    SectionHeading(title: "Appearance")
                    QuietPanel {
                        ThemePicker(selection: $appearance)
                    }
                    SectionHeading(title: "Reading")
                    QuietPanel {
                        Toggle(isOn: $verticalReading) { Label("Vertical scrolling", systemImage: "arrow.down") }.frame(minHeight: 44)
                        Divider()
                        Toggle(isOn: $rightToLeft) { Label("Read right to left", systemImage: "arrow.left.to.line") }.frame(minHeight: 44).disabled(verticalReading)
                        Divider()
                        Toggle(isOn: $hideControls) { Label("Automatically hide controls", systemImage: "rectangle.dashed") }.frame(minHeight: 44)
                        Divider()
                        Toggle(isOn: $keepAwake) { Label("Keep screen awake", systemImage: "sun.max") }.frame(minHeight: 44)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            AppLogo(size: 44)
                            Text("Sumi").font(Design.section)
                        }
                        Text("PDFs work offline; sources require internet.")
                            .font(Design.font(.footnote)).foregroundStyle(.secondary).lineSpacing(3)
                        Text("Version 1.0").font(Design.font(.caption)).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }.padding(Design.spacing).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.pageBackground().navigationTitle("Settings")
        }
    }
}

private struct ThemePicker: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private let choices = ["light", "dark", "system"]
    var body: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 3
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            ForEach(choices, id: \.self) { theme in
                Button {
                    withAnimation(Motion(reduced: reduceMotion).standard) { selection = theme }
                } label: {
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(
                                LinearGradient(colors: theme == "light"
                                               ? [Color.cyan.opacity(0.5), Color.mint.opacity(0.5), .white]
                                               : [Color(red: 0.03, green: 0.12, blue: 0.24), Color.cyan.opacity(0.45)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                            if theme == "system" {
                                UnevenRoundedRectangle(bottomTrailingRadius: 14, topTrailingRadius: 14)
                                    .fill(Color.cyan.opacity(0.65)).frame(width: 36).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            Image(systemName: theme == "dark" ? "moon" : theme == "light" ? "sun.max" : "circle.lefthalf.filled")
                                .font(Design.font(.title2)).foregroundStyle(theme == "light" ? Color.black : Color.white)
                        }.frame(height: 76).accessibilityHidden(true)
                        HStack(spacing: 4) {
                            Text(theme.capitalized).font(Design.font(.subheadline).weight(.medium))
                            if selection == theme { Image(systemName: "checkmark.circle.fill").font(Design.font(.caption)).foregroundStyle(Design.accent) }
                        }.foregroundStyle(.primary)
                    }.padding(8).frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selection == theme ? Design.accent : .clear, lineWidth: 1.5))
                }.buttonStyle(PressStyle()).accessibilityLabel("\(theme.capitalized) appearance")
                    .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
    }
}
