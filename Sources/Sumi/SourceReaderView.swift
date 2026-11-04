import SwiftUI

struct SourceMangaDetailView: View {
    @EnvironmentObject private var sources: SourceStore
    @EnvironmentObject private var library: LibraryStore
    let manga: Manga
    @State private var chapters: [SourceChapter] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selection: ChapterSelection?
    @State private var retry = 0
    private var reference: RemoteMangaReference { manga.remote! }
    private var source: InstalledSource? { sources.installed.first { $0.id == reference.sourceID } }
    private var key: String { "\(source.map { String($0.manifest.hashValue) } ?? "removed"):\(retry)" }
    private var resolved: Manga {
        var value = manga
        value.chapterCount = max(1, chapters.count)
        value.remote?.chapters = chapters
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CoverArt(manga: manga).frame(height: 340).clipShape(RoundedRectangle(cornerRadius: Design.corner))
                Text(manga.title).font(Design.title).accessibilityAddTraits(.isHeader)
                Text(manga.author).font(.headline).foregroundStyle(.secondary)
                if let source { Link(source.manifest.name, destination: source.manifest.website) }
                Text(manga.synopsis).foregroundStyle(.secondary).lineSpacing(4)
                if loading { ProgressView("Loading chapters…") }
                else if let error {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { retry += 1 }.frame(minHeight: 44)
                } else {
                    Button {
                        selection = ChapterSelection(number: library.isComplete(resolved) ? 1 : library.positions[manga.id]?.chapter ?? 1,
                                                     resumePosition: !library.isComplete(resolved))
                    } label: {
                        Label(library.positions[manga.id] == nil ? "Start reading" : library.isComplete(resolved) ? "Read again" : "Continue reading", systemImage: "book")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent)
                    SectionHeading(title: "Chapters", subtitle: "\(chapters.count) chapters · internet required")
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button { selection = ChapterSelection(number: index + 1) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(chapter.title).foregroundStyle(.primary)
                                        if !chapter.credit.isEmpty { Text(chapter.credit).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }.frame(minHeight: 60).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(PressStyle())
                            Divider()
                        }
                    }
                }
            }.padding(Design.spacing).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }.pageBackground().navigationTitle(manga.title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { library.toggleSaved(resolved) } label: {
                        Image(systemName: library.savedIDs.contains(manga.id) ? "bookmark.fill" : "bookmark")
                    }.disabled(loading || error != nil)
                        .accessibilityLabel(library.savedIDs.contains(manga.id) ? "Remove from library" : "Add to library")
                }
            }
            .task(id: key) {
                loading = true; error = nil
                do {
                    let value = try await sources.chapters(reference)
                    try Task.checkCancellation()
                    chapters = value
                    library.rememberRemote(resolved)
                    loading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = error.localizedDescription; loading = false
                }
            }
            .fullScreenCover(item: $selection) { selection in
                SourceReaderView(manga: resolved, chapters: chapters, initialChapter: selection.number, resume: selection.resumePosition)
            }
    }
}

struct SourceReaderView: View {
    @EnvironmentObject private var sources: SourceStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("verticalReading") private var verticalReading = false
    @AppStorage("rightToLeft") private var rightToLeft = true
    @AppStorage("hideControls") private var autoHide = true
    @AppStorage("keepAwake") private var keepAwake = false
    let manga: Manga
    let chapters: [SourceChapter]
    let resume: Bool
    @State private var chapter: Int
    @State private var page = 0
    @State private var pages: [URL] = []
    @State private var loaded: Set<Int> = []
    @State private var loading = true
    @State private var error: String?
    @State private var controls = true
    @State private var choosingChapter = false
    @State private var finished = false
    @State private var scrubbing = false
    @State private var retry = 0
    @State private var firstLoad = true
    @State private var loadedChapter: Int?
    @State private var landAtEnd = false
    @State private var hideTask: Task<Void, Never>?

    init(manga: Manga, chapters: [SourceChapter], initialChapter: Int, resume: Bool) {
        self.manga = manga; self.chapters = chapters; self.resume = resume
        _chapter = State(initialValue: min(max(1, initialChapter), max(1, chapters.count)))
    }
    private var reference: RemoteMangaReference { manga.remote! }
    private var revision: String { sources.installed.first { $0.id == reference.sourceID }.map { String($0.manifest.hashValue) } ?? "removed" }
    private var key: String { "\(chapter):\(revision):\(retry)" }
    private var indices: [Int] { rightToLeft ? Array(pages.indices.reversed()) : Array(pages.indices) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if loading { ProgressView("Loading chapter…").tint(.white) }
            else if let error {
                VStack(spacing: 20) {
                    Text("Couldn’t load this chapter").font(.headline)
                    Text(error).font(.subheadline).multilineTextAlignment(.center)
                    Button("Try again") { retry += 1 }.buttonStyle(.bordered)
                }.padding()
            } else if verticalReading {
                VerticalReaderPages(count: pages.count, page: $page) { index, width in
                    SourceImage(url: pages[index], sourceID: reference.sourceID, fitWidth: true, onLoaded: {
                        loaded.insert(index)
                        if index == page { save() }
                    }, onRetry: { save(); retry += 1 })
                        .frame(width: width)
                        .contentShape(Rectangle()).onTapGesture { toggleControls() }
                        .accessibilityLabel("Page \(index + 1)")
                        .accessibilityAction(named: "Show reading controls") { controls = true; resetTimer() }
                }.id(chapter).ignoresSafeArea()
            } else {
                TabView(selection: $page) {
                    ForEach(indices, id: \.self) { index in
                        Group {
                            if abs(index - page) <= 1 {
                                SourceImage(url: pages[index], sourceID: reference.sourceID, onLoaded: {
                                    loaded.insert(index)
                                    if index == page { save() }
                                }, onRetry: { save(); retry += 1 })
                            } else { Color.clear }
                        }.tag(index).contentShape(Rectangle()).onTapGesture { toggleControls() }
                            .accessibilityLabel("Page \(index + 1)")
                            .accessibilityAction(named: "Show reading controls") { controls = true; resetTimer() }
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never)).id(chapter).ignoresSafeArea()
            }
        }.foregroundStyle(.white).preferredColorScheme(.dark).statusBarHidden(!controls)
            .overlay(alignment: .top) {
                if controls {
                    HStack(spacing: 12) {
                        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 48, height: 48) }.accessibilityLabel("Close reader")
                        VStack(spacing: 4) {
                            Text(manga.title).font(.headline).lineLimit(2)
                            Text(chapters[chapter - 1].title).font(.caption).lineLimit(2)
                        }.frame(maxWidth: .infinity)
                        Button { choosingChapter = true } label: { Image(systemName: "list.bullet").frame(width: 48, height: 48) }.accessibilityLabel("Choose chapter")
                    }.padding(8).glassSurface(radius: 28).padding().frame(maxWidth: 680)
                }
            }
            .overlay(alignment: .bottom) {
                if controls && !loading && error == nil {
                    VStack(spacing: 4) {
                        ReaderModeButton()
                        HStack {
                            Button { previous() } label: { Image(systemName: "chevron.backward").frame(width: 48, height: 48) }
                                .disabled(chapter == 1 && page == 0).accessibilityLabel("Previous page")
                            Text("\(page + 1) / \(pages.count)").monospacedDigit().frame(maxWidth: .infinity)
                            Button { next() } label: { Image(systemName: "chevron.forward").frame(width: 48, height: 48) }
                                .accessibilityLabel("Next page")
                        }
                        Slider(value: Binding(get: { Double(page) }, set: { page = Int($0) }), in: 0...Double(max(1, pages.count - 1)), step: 1) { editing in
                            scrubbing = editing; resetTimer()
                        }.disabled(pages.count < 2).accessibilityLabel("Page").accessibilityValue("\(page + 1) of \(pages.count)")
                    }.padding(16).glassSurface(radius: 28).padding().frame(maxWidth: 520)
                }
            }
            .task(id: key) { await load() }
            .onChange(of: page) { _, _ in save(); resetTimer() }
            .onChange(of: choosingChapter) { _, _ in resetTimer() }
            .onChange(of: finished) { _, _ in resetTimer() }
            .onChange(of: voiceOver) { _, enabled in if enabled { controls = true }; resetTimer() }
            .onChange(of: autoHide) { _, enabled in if !enabled { controls = true }; resetTimer() }
            .onChange(of: scenePhase) { _, phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .active && keepAwake
                save(); resetTimer()
            }
            .onChange(of: keepAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && value }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && keepAwake }
            .onDisappear { hideTask?.cancel(); save(); UIApplication.shared.isIdleTimerDisabled = false }
            .sheet(isPresented: $choosingChapter) {
                NavigationStack {
                    List(Array(chapters.enumerated()), id: \.element.id) { index, item in
                        Button { changeChapter(index + 1); choosingChapter = false } label: {
                            HStack { Text(item.title); Spacer(); if chapter == index + 1 { Image(systemName: "checkmark") } }
                        }
                    }.navigationTitle("Chapters")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { choosingChapter = false } } }
                }
            }
            .alert("You’ve reached the end", isPresented: $finished) {
                Button("Back to story") { dismiss() }
                Button("Stay here", role: .cancel) { controls = true }
            }
    }

    @MainActor private func load() async {
        let previousPage = loadedChapter == chapter ? page : nil
        loading = true; error = nil; controls = true; loaded = []; hideTask?.cancel()
        let generation = key
        do {
            let urls = try await sources.pages(reference, chapterID: chapters[chapter - 1].id)
            try Task.checkCancellation()
            guard generation == key else { return }
            pages = urls
            if firstLoad && resume, let position = library.positions[manga.id], position.chapter == chapter {
                page = min(max(0, position.page), urls.count - 1)
            } else { page = landAtEnd ? urls.count - 1 : min(previousPage ?? 0, urls.count - 1) }
            loadedChapter = chapter
            firstLoad = false; landAtEnd = false; loading = false; resetTimer()
        } catch {
            guard !Task.isCancelled, generation == key else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
    private func save() {
        guard !loading, error == nil, loaded.contains(page), !pages.isEmpty else { return }
        library.record(manga, chapter: chapter, page: page, count: pages.count)
    }
    private func changeChapter(_ number: Int, end: Bool = false) {
        guard number != chapter else { controls = true; resetTimer(); return }
        save(); loading = true; loaded = []; landAtEnd = end; chapter = number; controls = true
        resetTimer()
    }
    private func previous() {
        if page > 0 { page -= 1 }
        else if chapter > 1 { changeChapter(chapter - 1, end: true) }
    }
    private func next() {
        guard loaded.contains(page) else { controls = true; return }
        if page + 1 < pages.count { page += 1 }
        else if chapter < chapters.count { changeChapter(chapter + 1) }
        else { save(); finished = true; controls = true }
    }
    private func toggleControls() {
        controls = voiceOver ? true : !controls
        resetTimer()
    }
    private func resetTimer() {
        hideTask?.cancel()
        guard autoHide, !voiceOver, controls, !loading, error == nil, !choosingChapter, !finished, !scrubbing, scenePhase == .active else { return }
        hideTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            controls = false
        }
    }
}
