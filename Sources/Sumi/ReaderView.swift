import SwiftUI
import PDFKit

struct ReaderView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("verticalReading") private var verticalReading = false
    @AppStorage("rightToLeft") private var rightToLeft = true
    @AppStorage("hideControls") private var autoHide = true
    @AppStorage("keepAwake") private var keepAwake = false
    let manga: Manga
    let initialChapter: Int
    var resumePosition = true
    @State private var chapter = 1
    @State private var page = 0
    @State private var pageCount = 1
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var document: PDFDocument?
    @State private var loadError = false
    @State private var loading = true
    @State private var showChapters = false
    @State private var finished = false
    @State private var scrubbing = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var pages: [Int] { rightToLeft ? Array((0..<pageCount).reversed()) : Array(0..<pageCount) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if loading {
                ProgressView().tint(.white).accessibilityLabel("Loading chapter")
            } else if loadError {
                ContentUnavailableView("Couldn’t open this document", systemImage: "doc.questionmark", description: Text("Return to your library and import an unlocked PDF again."))
                    .foregroundStyle(.white)
            } else if verticalReading, let document {
                ContinuousPDFView(document: document, page: $page, onTap: toggleControls)
                    .id(chapter).ignoresSafeArea()
                    .accessibilityAction(named: "Show reading controls") { revealControls() }
            } else {
                TabView(selection: $page) {
                    ForEach(pages, id: \.self) { index in
                        Group {
                            if let document, let pdfPage = document.page(at: index) {
                                PDFPageView(page: pdfPage, onTap: toggleControls)
                            } else {
                                ContentUnavailableView("Page unavailable", systemImage: "doc.questionmark")
                                    .foregroundStyle(.white)
                            }
                        }.tag(index).contentShape(Rectangle())
                            .accessibilityAction(named: "Show reading controls") { revealControls() }
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                    .id(chapter)
                    .transition(.opacity)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!controls)
        .overlay(alignment: .top) {
            if controls {
                GlassGroup {
                    HStack(alignment: .top, spacing: 10) {
                        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 48, height: 48).glassSurface(radius: 24, interactive: true) }
                            .accessibilityLabel("Close reader")
                        VStack(spacing: 4) {
                            Text(manga.title).font(Design.font(.subheadline).weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            Text("Chapter \(chapter)").font(Design.font(.caption)).foregroundStyle(.secondary)
                        }.multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 48).glassSurface(radius: 24)
                        Button { showChapters = true } label: { Image(systemName: "list.bullet").frame(width: 48, height: 48).glassSurface(radius: 24, interactive: true) }
                            .accessibilityLabel("Choose chapter")
                    }.padding(.horizontal, 16).padding(.top, 8)
                }.frame(maxWidth: 680).buttonStyle(PressStyle()).transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if controls && !loading && !loadError {
                VStack(spacing: 8) {
                    ReaderModeButton()
                    HStack {
                        Button { previousPage() } label: { Image(systemName: "chevron.backward").frame(width: 44, height: 44) }
                            .disabled(page == 0 && chapter == 1).accessibilityLabel("Previous page")
                        VStack(spacing: 2) {
                            Text("\(page + 1) of \(pageCount)").font(Design.font(.subheadline).monospacedDigit().weight(.medium))
                            Text(page == pageCount - 1 ? (chapter == manga.chapterCount ? "End of story" : "Next chapter →") : "PAGE")
                                .font(Design.font(.caption2)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                        Button { nextPage() } label: { Image(systemName: "chevron.forward").frame(width: 44, height: 44) }
                            .accessibilityLabel(page == pageCount - 1 ? "Finish chapter" : "Next page")
                    }
                    Slider(value: Binding(get: { Double(page) }, set: { page = Int($0); resetHideTimer() }), in: 0...Double(max(1, pageCount - 1)), step: 1, onEditingChanged: { editing in
                        scrubbing = editing
                        resetHideTimer()
                    })
                        .disabled(pageCount <= 1).accessibilityLabel("Page")
                        .accessibilityValue("\(page + 1) of \(pageCount)")
                }.padding(16).glassSurface(radius: 32).padding(.horizontal, 16).padding(.bottom, 8)
                    .frame(maxWidth: 520).buttonStyle(PressStyle())
                    .transition(.opacity)
            }
        }
        .task {
            chapter = min(max(1, initialChapter), max(1, manga.chapterCount))
            if let url = manga.documentURL {
                document = PDFDocument(url: url)
                pageCount = document?.pageCount ?? 0
                loadError = document == nil || pageCount == 0 || document?.isLocked == true
            } else { loadError = true }
            if resumePosition, let position = store.positions[manga.id], position.chapter == chapter {
                page = position.normalized(chapterCount: manga.chapterCount, actualPageCount: pageCount).page
            }
            loading = false
            if !loadError { savePosition() }
            UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && keepAwake
            resetHideTimer()
        }
        .onChange(of: page) { _, _ in savePosition(); resetHideTimer() }
        .onChange(of: voiceOver) { _, enabled in if enabled { revealControls() } else { resetHideTimer() } }
        .onChange(of: autoHide) { _, enabled in if enabled { resetHideTimer() } else { revealControls() } }
        .onChange(of: keepAwake) { _, enabled in UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && enabled }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active && keepAwake
            if phase == .active { resetHideTimer() } else { hideTask?.cancel(); savePosition() }
        }
        .onChange(of: showChapters) { _, _ in resetHideTimer() }
        .onChange(of: finished) { _, _ in resetHideTimer() }
        .onDisappear {
            hideTask?.cancel()
            savePosition()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $showChapters, onDismiss: resetHideTimer) {
            NavigationStack {
                List(1...manga.chapterCount, id: \.self) { number in
                    Button { changeChapter(number); showChapters = false } label: {
                        HStack { Text("Chapter \(number)"); Spacer(); if number == chapter { Image(systemName: "checkmark") } }
                    }
                }.scrollContentBackground(.hidden).pageBackground()
                    .navigationTitle("Chapters").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showChapters = false } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                .presentationCornerRadius(Design.corner)
        }
        .alert("You’ve reached the end", isPresented: $finished) {
            Button("Back to story") { dismiss() }
            Button("Stay here", role: .cancel) { revealControls() }
        } message: { Text("Your reading position is saved.") }
    }

    private func toggleControls() {
        guard !voiceOver else { revealControls(); return }
        withAnimation(Motion(reduced: reduceMotion).standard) { controls.toggle() }
        resetHideTimer()
    }
    private func revealControls() { withAnimation(Motion(reduced: reduceMotion).standard) { controls = true }; resetHideTimer() }
    private func resetHideTimer() {
        hideTask?.cancel()
        guard autoHide, !voiceOver, controls, !loading, !showChapters, !loadError, !finished, !scrubbing, scenePhase == .active else { return }
        hideTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !Task.isCancelled, !showChapters, !finished else { return }
            withAnimation(Motion(reduced: reduceMotion).standard) { controls = false }
        }
    }
    private func savePosition() {
        guard !loading, !loadError else { return }
        store.record(manga, chapter: chapter, page: page, count: pageCount)
    }
    private func changeChapter(_ number: Int) {
        withAnimation(Motion(reduced: reduceMotion).standard) { chapter = number; page = 0 }
        savePosition(); revealControls()
    }
    private func previousPage() {
        if page > 0 { withAnimation(Motion(reduced: reduceMotion).standard) { page -= 1 } }
        else if chapter > 1 { changeChapter(chapter - 1); page = pageCount - 1 }
        resetHideTimer()
    }
    private func nextPage() {
        if page < pageCount - 1 { withAnimation(Motion(reduced: reduceMotion).standard) { page += 1 } }
        else if chapter < manga.chapterCount { changeChapter(chapter + 1) }
        else { finished = true }
        resetHideTimer()
    }
}

struct PDFPageView: UIViewRepresentable {
    let page: PDFPage
    var onTap: () -> Void
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var sourcePage: PDFPage?
        var onTap: () -> Void
        init(onTap: @escaping () -> Void) { self.onTap = onTap }
        @objc func tapped() { onTap() }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (otherGestureRecognizer as? UITapGestureRecognizer)?.numberOfTapsRequired ?? 0 > 1
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.backgroundColor = .black
        view.displaysPageBreaks = false
        view.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onTap = onTap
        guard context.coordinator.sourcePage !== page else { return }
        let document = PDFDocument()
        if let copy = page.copy() as? PDFPage { document.insert(copy, at: 0) }
        view.document = document
        context.coordinator.sourcePage = page
    }
}

/// Keeps page seeking and saved progress shared between continuous and paged reading.
struct VerticalReaderPages<Content: View>: View {
    let count: Int
    @Binding var page: Int
    let content: (Int, CGFloat) -> Content
    @State private var visiblePage: Int?

    init(count: Int, page: Binding<Int>, @ViewBuilder content: @escaping (Int, CGFloat) -> Content) {
        self.count = count
        _page = page
        self.content = content
        _visiblePage = State(initialValue: page.wrappedValue)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        content(index, geometry.size.width)
                            .frame(width: geometry.size.width)
                            .id(index)
                    }
                }.scrollTargetLayout()
            }
            .scrollPosition(id: $visiblePage, anchor: .top)
            .onChange(of: visiblePage) { _, value in
                if let value, value != page { page = value }
            }
            .onChange(of: page) { _, value in
                if visiblePage != value { visiblePage = value }
            }
        }
    }
}

struct ReaderModeButton: View {
    @AppStorage("verticalReading") private var verticalReading = false

    var body: some View {
        Button { verticalReading.toggle() } label: {
            Label(verticalReading ? "Vertical scrolling" : "Paged reading",
                  systemImage: verticalReading ? "arrow.down" : "book.pages")
                .font(Design.font(.subheadline))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityHint(verticalReading ? "Switch to paged reading" : "Switch to vertical scrolling")
    }
}

struct ContinuousPDFView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    var onTap: () -> Void

    class Coordinator: PDFPageView.Coordinator {
        var selection: Binding<Int>
        init(selection: Binding<Int>, onTap: @escaping () -> Void) {
            self.selection = selection
            super.init(onTap: onTap)
        }
        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let current = view.currentPage, let document = view.document else { return }
            let index = document.index(for: current)
            if index != NSNotFound, selection.wrappedValue != index {
                selection.wrappedValue = index
            }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $page, onTap: onTap) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.backgroundColor = .black
        view.document = document
        view.autoScales = true
        if let target = document.page(at: page) { view.go(to: target) }
        NotificationCenter.default.addObserver(context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.selection = $page
        context.coordinator.onTap = onTap
        if view.document !== document { view.document = document }
        if let target = document.page(at: page), view.currentPage !== target { view.go(to: target) }
    }
}
