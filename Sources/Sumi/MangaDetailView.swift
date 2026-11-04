import SwiftUI

struct MangaDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let manga: Manga
    @State private var readingSelection: ChapterSelection?
    @State private var expanded = false
    @State private var headerCollapsed = false
    @State private var confirmingReset = false

    var body: some View {
        if manga.remote != nil {
            SourceMangaDetailView(manga: manga)
        } else {
            localBody
        }
    }

    private var localBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 26) {
                    SaveMangaButton(manga: manga)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) {
                        metadata("Chapters", value: "\(manga.chapterCount)")
                        Divider().frame(height: 32)
                        metadata("Genre", value: manga.genre)
                        Divider().frame(height: 32)
                        metadata("Format", value: "PDF")
                        }
                        VStack(spacing: 16) {
                            metadata("Chapters", value: "\(manga.chapterCount)")
                            metadata("Genre", value: manga.genre)
                            metadata("Format", value: "PDF")
                        }
                    }.padding(20).glassSurface()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(manga.synopsis).font(Design.font(.body)).foregroundStyle(.secondary).lineSpacing(5)
                            .lineLimit(expanded ? nil : 3)
                        Button(expanded ? "Show less" : "Read more") {
                            withAnimation(Motion(reduced: reduceMotion).standard) { expanded.toggle() }
                        }.font(Design.font(.subheadline).weight(.medium)).frame(minHeight: 44)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeading(title: "Chapters")
                        Text("\(manga.chapterCount)").font(Design.font(.title2).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(1...manga.chapterCount, id: \.self) { chapter in
                            Button { readingSelection = ChapterSelection(number: chapter) } label: {
                                chapterRow(chapter)
                            }.buttonStyle(PressStyle())
                            if chapter < manga.chapterCount { Divider().padding(.leading, 56) }
                        }
                    }
                }.padding(.horizontal, Design.spacing)
            }.padding(.bottom, 28).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "detail")
        .background(alignment: .top) {
            if !reduceTransparency {
                CoverArt(manga: manga).frame(height: 680).blur(radius: 60).opacity(0.15)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .pageBackground()
        .onPreferenceChange(HeaderOffsetKey.self) { bottom in headerCollapsed = bottom < 60 }
        .navigationTitle(headerCollapsed ? manga.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = manga.documentURL {
                    ShareLink(item: url) { Label("Export PDF", systemImage: "square.and.arrow.up") }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if store.positions[manga.id] != nil {
                    Menu {
                        Button("Mark as unread", systemImage: "arrow.counterclockwise") { confirmingReset = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }.accessibilityLabel("Reading actions")
                }
            }
        }
        .confirmationDialog("Mark as unread?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset reading progress", role: .destructive) { store.markUnread(manga) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clears your saved chapter and page for this story. Your library entry and imported file are kept.")
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                readingSelection = ChapterSelection(number: store.isComplete(manga) ? 1 : store.positions[manga.id]?.chapter ?? 1,
                                                    resumePosition: !store.isComplete(manga))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.pages.fill").foregroundStyle(Design.accent)
                        .frame(width: 40, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.positions[manga.id] == nil ? "Start reading" : store.isComplete(manga) ? "Read again" : "Continue reading")
                        Text("Chapter \(store.isComplete(manga) ? 1 : store.positions[manga.id]?.chapter ?? 1)")
                            .font(Design.font(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                }.font(Design.font(.headline)).padding(.horizontal, 18).padding(.vertical, 12).foregroundStyle(.primary).glassSurface(radius: 32, interactive: true)
            }.buttonStyle(PressStyle()).padding(.horizontal, 20).padding(.vertical, 8)
                .frame(maxWidth: 600)
        }
        .fullScreenCover(item: $readingSelection) { selection in
            ReaderView(manga: manga, initialChapter: selection.number, resumePosition: selection.resumePosition)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 250)
            Text("PDF")
                .font(Design.eyebrow).tracking(1.8).foregroundStyle(.white.opacity(0.85))
            Text(manga.title).font(Design.title).tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(manga.author).font(Design.font(.subheadline)).foregroundStyle(.white.opacity(0.85))
        }.padding(Design.spacing).padding(.bottom, 24)
            .frame(maxWidth: .infinity, minHeight: 440, alignment: .bottomLeading)
            .background {
                GeometryReader { proxy in
                    let offset = proxy.frame(in: .named("detail")).minY
                    CoverArt(manga: manga)
                        .frame(width: proxy.size.width, height: proxy.size.height + (reduceMotion ? 0 : max(0, offset)))
                        .offset(y: reduceMotion ? 0 : -max(0, offset))
                        .overlay {
                            LinearGradient(stops: [.init(color: .black.opacity(0.08), location: 0), .init(color: .black.opacity(0.15), location: 0.35), .init(color: .black.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom)
                        }
                        .preference(key: HeaderOffsetKey.self, value: proxy.frame(in: .named("detail")).maxY)
                }
            }.clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Design.background(scheme)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40).allowsHitTesting(false)
            }
    }

    private func metadata(_ label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(Design.font(.subheadline).weight(.semibold))
            Text(label).font(Design.font(.caption)).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }

    private func chapterRow(_ number: Int) -> some View {
        HStack(spacing: 16) {
            Text(number.formatted(.number.precision(.integerLength(2))))
                .font(Design.font(.title3).monospacedDigit()).foregroundStyle(.secondary).frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(Design.font(.body).weight(.medium)).foregroundStyle(.primary)
                Text(store.positions[manga.id]?.chapter == number ? "Continue where you left off" : "Available offline")
                    .font(Design.font(.caption)).foregroundStyle(.secondary)
                ChapterProgressView(position: store.chapterPosition(manga, chapter: number))
            }
            Spacer(minLength: 4)
            Image(systemName: store.positions[manga.id]?.chapter == number ? "book.fill" : "chevron.right")
                .font(Design.font(.caption)).foregroundStyle(.secondary)
        }.padding(.vertical, 18).frame(minHeight: 68).contentShape(Rectangle())
    }
}

struct ChapterSelection: Identifiable {
    let number: Int
    var resumePosition = true
    var id: Int { number }
}

struct ChapterProgressView: View {
    let position: ReadingPosition?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let position {
                Text(position.chapterProgress == 1 ? "Completed" : "Page \(position.page + 1) / \(position.pageCount) · \(Int(position.chapterProgress * 100))%")
                    .font(Design.font(.caption)).foregroundStyle(.secondary)
                ProgressView(value: position.chapterProgress).tint(Design.accent).frame(maxWidth: 160)
            } else {
                Text("Unread").font(Design.font(.caption)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HeaderOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
