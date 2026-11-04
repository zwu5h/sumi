import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var covers
    @State private var genre = "All"
    @State private var query = ""
    private let genres = ["All", "Adventure", "Slice of life", "Fantasy"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    EditorialHeader(eyebrow: "The reading room", title: "Find your next world.", subtitle: "Small escapes. Lasting impressions.")
                    NavigationLink { SourcesView() } label: {
                        Label("Browse your sources", systemImage: "network").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                    if query.isEmpty, genre == "All", let featured = LibraryStore.samples.last {
                        NavigationLink(value: featured) {
                            DiscoveryFeature(manga: featured)
                        }.buttonStyle(PressStyle())
                    }
                    SelectionRail(items: genres, selection: $genre)
                    let results = LibraryStore.samples.filter { (genre == "All" || $0.genre == genre) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
                    SectionHeading(title: "Sumi originals", subtitle: "Sample collection · \(results.count) stories")
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(results) { manga in
                        NavigationLink(value: manga) {
                            HStack(alignment: .top, spacing: 20) {
                                CoverArt(manga: manga).frame(width: 115, height: 172)
                                    .clipShape(RoundedRectangle(cornerRadius: Design.coverCorner))
                                    .coverTransitionSource(id: manga.id, namespace: covers, reducedMotion: reduceMotion)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(manga.genre.uppercased()).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(Design.accent)
                                    Text(manga.title).font(.system(.title3, design: .rounded, weight: .semibold)).foregroundStyle(.primary)
                                    Text(manga.synopsis).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                    Text("\(manga.chapterCount) chapters").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(PressStyle())
                    }
                    Text("Import your own manga PDFs from the + button in Library.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.vertical)
                }.padding(Design.spacing).frame(maxWidth: 840).frame(maxWidth: .infinity)
            }.pageBackground().navigationTitle("Discover")
                .safeAreaInset(edge: .top, spacing: 0) {
                    GlassSearch(text: $query).padding(.horizontal, Design.spacing).padding(.vertical, 8).frame(maxWidth: 840)
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationDestination(for: Manga.self) { manga in
                    MangaDetailView(manga: manga)
                        .coverNavigationTransition(id: manga.id, namespace: covers, reducedMotion: reduceMotion)
                }
        }
    }
}

private struct DiscoveryFeature: View {
    let manga: Manga
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverArt(manga: manga)
            VStack(alignment: .leading, spacing: 12) {
                Text("IN THE SPOTLIGHT").font(Design.eyebrow).tracking(2).foregroundStyle(Design.accent)
                Text(manga.title).font(Design.title).foregroundStyle(.primary)
                HStack {
                    Text("\(manga.genre) · Sumi original").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(Design.accent).frame(width: 44, height: 44)
                        .glassSurface(radius: 22)
                }
            }.padding(20).glassSurface(radius: 24).padding(12)
        }.frame(minHeight: typeSize.isAccessibilitySize ? 520 : 320)
            .clipShape(RoundedRectangle(cornerRadius: Design.corner)).accessibilityElement(children: .combine)
    }
}

struct UpdatesView: View {
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    EditorialHeader(eyebrow: "One more chapter", title: "Waiting in the wings.", subtitle: "Pick up a story from your collection.", symbol: "text.book.closed")
                    SectionHeading(title: "Available to read", subtitle: "Sample chapters · on your shelf")
                    let samples = store.library.filter(\.isSample)
                    if samples.isEmpty {
                        ContentUnavailableView("You’re all caught up", systemImage: "checkmark.circle", description: Text("Add a sample story from Discover to see its available chapters."))
                    }
                    ForEach(samples) { manga in
                        NavigationLink(value: manga) {
                            HStack(spacing: 16) {
                                CoverArt(manga: manga).frame(width: 64, height: 92).clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(manga.title).font(.headline).foregroundStyle(.primary)
                                    Text("\(manga.chapterCount) preview chapters available").font(.subheadline).foregroundStyle(.secondary)
                                    Text("Sumi original").font(.caption).foregroundStyle(Design.accent)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                        }.buttonStyle(PressStyle())
                        Divider()
                    }
                    Text("Open a title from your sources to refresh its chapter list.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top)
                }.padding(Design.spacing).frame(maxWidth: 840).frame(maxWidth: .infinity)
            }.pageBackground().navigationTitle("Updates")
                .navigationDestination(for: Manga.self) { MangaDetailView(manga: $0) }
        }
    }
}

struct OfflineView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var toRemove: Manga?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    EditorialHeader(eyebrow: "Made for the way there", title: "Stories to go.", subtitle: "Your imported PDFs, ready wherever you are.", symbol: "arrow.down.circle")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    QuietPanel {
                        HStack(spacing: 14) {
                            Image(systemName: "internaldrive").font(.title2).foregroundStyle(Design.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("On this device").font(.headline)
                                Text("\(store.imported.count) documents · available offline").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }.listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section("Imported documents · \(store.imported.count)") {
                    if store.imported.isEmpty {
                        ContentUnavailableView("Take your stories with you", systemImage: "arrow.down.document", description: Text("Use + in Library to import a PDF. It will appear here, ready for offline reading."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(store.imported) { manga in
                        NavigationLink(value: manga) {
                            HStack(spacing: 14) {
                                CoverArt(manga: manga).frame(width: 48, height: 68).clipShape(RoundedRectangle(cornerRadius: 5))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(manga.title).font(.headline)
                                    Text("Available offline").font(.caption).foregroundStyle(.secondary)
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
    @AppStorage("rightToLeft") private var rightToLeft = true
    @AppStorage("hideControls") private var hideControls = true
    @AppStorage("keepAwake") private var keepAwake = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    EditorialHeader(eyebrow: "Make yourself at home", title: "A little more you.", subtitle: "Set the mood for your next chapter.", symbol: "moonphase.waning.crescent")
                    QuietPanel {
                        NavigationLink { SourcesView() } label: {
                            Label("Sources & repositories", systemImage: "network").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    SectionHeading(title: "Appearance", subtitle: "The right light for every story.")
                    QuietPanel {
                        ThemePicker(selection: $appearance)
                    }
                    SectionHeading(title: "Your reading ritual")
                    QuietPanel {
                        Toggle(isOn: $rightToLeft) { Label("Read right to left", systemImage: "arrow.left.to.line") }.frame(minHeight: 44)
                        Divider()
                        Toggle(isOn: $hideControls) { Label("Automatically hide controls", systemImage: "rectangle.dashed") }.frame(minHeight: 44)
                        Divider()
                        Toggle(isOn: $keepAwake) { Label("Keep screen awake", systemImage: "sun.max") }.frame(minHeight: 44)
                    }
                    Text("Tap a page to reveal controls. Swipe to turn pages. Your place is saved automatically.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                    SectionHeading(title: "Comfort, built in")
                    QuietPanel {
                        Label("Follows your accessibility settings", systemImage: "accessibility").font(.headline)
                        Text("Text size, Reduce Motion, Reduce Transparency and increased contrast follow your device preferences.")
                            .font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Sumi · Space for stories")
                        Text("The included titles and illustrations are original samples. Import PDFs for offline reading, or add sources to browse online. Online chapters require an internet connection.")
                            .font(.footnote).foregroundStyle(.secondary).lineSpacing(3)
                        Text("Version 1.0").font(.caption).foregroundStyle(.secondary)
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
                                .font(.title2).foregroundStyle(theme == "light" ? Color.black : Color.white)
                        }.frame(height: 76).accessibilityHidden(true)
                        HStack(spacing: 4) {
                            Text(theme.capitalized).font(.subheadline.weight(.medium))
                            if selection == theme { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Design.accent) }
                        }.foregroundStyle(.primary)
                    }.padding(8).frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selection == theme ? Design.accent : .clear, lineWidth: 1.5))
                }.buttonStyle(PressStyle()).accessibilityLabel("\(theme.capitalized) appearance")
                    .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
    }
}
