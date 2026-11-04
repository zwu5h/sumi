import SwiftUI
import UniformTypeIdentifiers

enum ShelfFilter: String, CaseIterable { case all = "All", reading = "Reading", unread = "Unread", completed = "Completed" }

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var filter: ShelfFilter = .all
    @State private var sortByTitle = false
    @State private var importing = false
    @Namespace private var covers
    @Environment(\.dynamicTypeSize) private var typeSize

    private var books: [Manga] {
        let books = store.library.filter {
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query)) &&
            matchesFilter($0)
        }
        return sortByTitle ? books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : books
    }

    private func matchesFilter(_ manga: Manga) -> Bool {
        switch filter {
        case .all: return true
        case .reading: return store.positions[manga.id] != nil && !store.isComplete(manga)
        case .unread: return store.positions[manga.id] == nil
        case .completed: return store.isComplete(manga)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 8) {
                        Image(systemName: "water.waves").foregroundStyle(Design.accent)
                        Text("Sumi").font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(Design.accent)
                        Spacer()
                    }.accessibilityElement(children: .combine)
                    if let progress = store.importProgress {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(store.isCancellingImport ? "Stopping import…" : "Importing \(min(progress.completed + 1, progress.total)) of \(progress.total)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button("Cancel", role: .cancel) { store.cancelImport() }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .disabled(store.isCancellingImport)
                                    .accessibilityLabel("Cancel PDF import")
                            }
                            Text(progress.currentFile).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            ProgressView(value: progress.fraction).accessibilityLabel("PDF import progress")
                        }.padding(18).glassSurface()
                    }
                    if query.isEmpty, filter == .all, let manga = store.recent ?? store.library.first {
                        NavigationLink(value: manga) { ContinueFeature(manga: manga) }.buttonStyle(PressStyle())
                    }
                    SelectionRail(items: ShelfFilter.allCases.map(\.rawValue), selection: Binding(
                        get: { filter.rawValue }, set: { filter = ShelfFilter(rawValue: $0) ?? .all }))
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeading(title: filter == .all ? "On your shelf" : filter.rawValue, subtitle: "\(books.count) stories · always within reach")
                        Menu {
                            Picker("Show", selection: $filter) {
                                ForEach(ShelfFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            Toggle("Sort by title", isOn: $sortByTitle)
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44).glassSurface(radius: 22, interactive: true)
                        }.accessibilityLabel("Filter and sort collection")
                    }
                    if books.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "A little room for a new story" : "No matching stories", systemImage: "books.vertical", description: Text(query.isEmpty ? "Find a title in Discover, or import a manga PDF." : "Try another title or change your filters."))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 145, maximum: 300), spacing: 16)], alignment: .leading, spacing: 26) {
                            ForEach(books) { manga in
                                NavigationLink(value: manga) {
                                    MangaTile(manga: manga, progress: store.progress(for: manga))
                                        .coverTransitionSource(id: manga.id, namespace: covers, reducedMotion: reduceMotion)
                                }.buttonStyle(PressStyle())
                            }
                        }
                    }
                    Text("A quiet place for your next chapter.")
                        .font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.padding(Design.spacing).frame(maxWidth: Design.contentWidth)
                    .frame(maxWidth: .infinity)
            }
            .pageBackground()
            .navigationTitle("Library")
            .safeAreaInset(edge: .top, spacing: 0) {
                GlassSearch(text: $query, prompt: "Search your collection")
                    .padding(.horizontal, Design.spacing).padding(.vertical, 8)
                    .frame(maxWidth: Design.contentWidth)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: {
                        if store.isImporting { ProgressView() } else { Image(systemName: "plus") }
                    }.disabled(store.isImporting).accessibilityLabel("Import manga PDFs")
                }
            }
            .navigationDestination(for: Manga.self) { manga in
                MangaDetailView(manga: manga)
                    .coverNavigationTransition(id: manga.id, namespace: covers, reducedMotion: reduceMotion)
            }
            .animation(Motion(reduced: reduceMotion).standard, value: filter)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task { await store.importPDFs(urls) }
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .alert("Couldn’t complete the request", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}

struct ContinueFeature: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let manga: Manga
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverArt(manga: manga)
            VStack(alignment: .leading, spacing: 12) {
                Text(store.positions[manga.id] == nil ? "YOUR NEXT ESCAPE" : store.isComplete(manga) ? "READ AGAIN" : "CONTINUE READING")
                    .font(.caption2.weight(.bold)).tracking(2).foregroundStyle(Design.accent)
                Text(manga.title).font(Design.title).tracking(-0.7).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Chapter \(store.isComplete(manga) ? 1 : store.positions[manga.id]?.chapter ?? 1) · \(manga.genre)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "book.pages.fill").font(.headline).foregroundStyle(Design.accent)
                        .frame(width: 44, height: 44).glassSurface(radius: 22)
                }
                if store.positions[manga.id] != nil {
                    ProgressView(value: store.progress(for: manga)).tint(Design.accent)
                        .accessibilityLabel("Reading progress")
                }
            }.padding(20).glassSurface(radius: 24).padding(12)
        }.frame(minHeight: typeSize.isAccessibilitySize ? 540 : 390)
            .clipShape(RoundedRectangle(cornerRadius: Design.corner))
            .accessibilityElement(children: .combine)
    }
}
