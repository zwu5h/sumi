import SwiftUI
import ImageIO

struct SourcesView: View {
    @EnvironmentObject private var sources: SourceStore
    @State private var repositoryURL = ""
    @State private var installation: SourceInstallation?
    @State private var removing: SourceRepository?

    var body: some View {
        List {
            Section {
                Text("Add a repository, then choose the sources you want to install.")
                    .foregroundStyle(.secondary)
                TextField("https://example.org/repository.json", text: $repositoryURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityLabel("Repository URL")
                Button("Add repository") {
                    Task { await sources.addRepository(repositoryURL) }
                }.disabled(sources.busy || repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if sources.busy { ProgressView("Updating sources…") }
            } header: { Text("Repository URL") } footer: {
                Text("Use a Sumi-format repository. Paperback repositories use a different extension API.")
            }
            Section("Installed sources") {
                if sources.installed.isEmpty { Text("No sources installed yet").foregroundStyle(.secondary) }
                ForEach(sources.installed) { source in
                    NavigationLink { SourceCatalogView(sourceID: source.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(source.manifest.name).font(Design.font(.headline))
                            Text("Version \(source.manifest.version) · \(source.manifest.author)").font(Design.font(.caption)).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.swipeActions {
                        Button("Remove", role: .destructive) { sources.removeSource(source.id) }
                            .disabled(sources.busy)
                    }
                }
            }
            ForEach(sources.repositories) { repository in
                Section {
                    ForEach(repository.extensions) { manifest in
                        Button { installation = SourceInstallation(manifest: manifest, repository: repository) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(manifest.name).font(Design.font(.headline))
                                    Text("\(manifest.version) · \(manifest.author)").font(Design.font(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: sources.installed.contains(where: { $0.manifest == manifest && $0.repositoryURL == repository.url }) ? "checkmark.circle" : "arrow.down.circle")
                            }.frame(minHeight: 44)
                        }.disabled(sources.busy)
                    }
                    Button("Refresh repository") { Task { await sources.addRepository(repository.url.absoluteString) } }
                        .disabled(sources.busy)
                    Button("Remove repository", role: .destructive) { removing = repository }.disabled(sources.busy)
                } header: { Text(repository.name) } footer: { Text(repository.url.absoluteString) }
            }
        }.scrollContentBackground(.hidden).pageBackground().navigationTitle("Sources")
            .sheet(item: $installation) { selection in SourceInstallView(selection: selection) }
            .confirmationDialog("Remove this repository and its installed sources?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove repository", role: .destructive) {
                    if let repository = removing { sources.removeRepository(repository.url) }; removing = nil
                }
            } message: { Text("Saved titles and reading progress stay in your library. Reinstall their source to read them again.") }
            .alert("Couldn’t update sources", isPresented: Binding(get: { sources.error != nil }, set: { if !$0 { sources.error = nil } })) {
                Button("OK") { sources.error = nil }
            } message: { Text(sources.error ?? "") }
    }
}

struct SourceInstallation: Identifiable {
    let manifest: SourceManifest
    let repository: SourceRepository
    var id: String { repository.id + ":" + manifest.id }
}

private struct SourceInstallView: View {
    @EnvironmentObject private var sources: SourceStore
    @Environment(\.dismiss) private var dismiss
    let selection: SourceInstallation
    var body: some View {
        NavigationStack {
            List {
                Section(selection.manifest.name) {
                    LabeledContent("Version", value: selection.manifest.version)
                    LabeledContent("Author", value: selection.manifest.author)
                    Text(selection.repository.url.absoluteString).font(Design.font(.caption)).foregroundStyle(.secondary)
                    Link("Source website", destination: selection.manifest.website)
                    if let imageReferer = selection.manifest.imageReferer {
                        LabeledContent("Image website reference", value: imageReferer.absoluteString)
                    }
                }
                Section("Can connect to") {
                    ForEach(selection.manifest.hosts, id: \.self) { host in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(host).textSelection(.enabled)
                            if host.hasPrefix("*.") {
                                Text("All subdomains of \(host.dropFirst(2))").font(Design.font(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("This installs third-party JavaScript that can request data from these hosts. Your IP address and search terms may be visible to them. Install only sources you trust.")
                    Text("Updates require another installation. Sumi does not send your library, local files or account credentials to extensions.")
                    Button(sources.busy ? "Installing…" : "Trust and install") {
                        Task {
                            await sources.install(selection.manifest, from: selection.repository)
                            if sources.error == nil { dismiss() }
                        }
                    }.disabled(sources.busy)
                    if let error = sources.error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle("Install source").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(sources.busy) } }
        }.interactiveDismissDisabled(sources.busy)
    }
}

private enum SourceCatalogLayout: String, CaseIterable {
    case grid = "Two columns"
    case compactGrid = "Three columns"
    case list = "List"

    var symbol: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .compactGrid: return "square.grid.3x3"
        case .list: return "list.bullet"
        }
    }

    var columnCount: Int { self == .compactGrid ? 3 : 2 }
}

struct SourceCatalogView: View {
    @EnvironmentObject private var sources: SourceStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("sourceCatalogLayout") private var layout: SourceCatalogLayout = .grid
    @AppStorage("sourceCatalogShowDetails") private var showDetails = false
    let sourceID: String
    @State private var query = ""
    @State private var results: [Manga] = []
    @State private var retry = 0
    @State private var loading = false
    @State private var error: String?
    @State private var filters = SourceFilters()
    @State private var selection = SourceSearchSelection()
    @State private var showingFilters = false
    @State private var filterError: String?
    @State private var loadingFilters = false
    private var source: InstalledSource? { sources.installed.first { $0.id == sourceID } }
    private var sourceKey: String { sourceID + ":" + (source.map { String($0.manifest.hashValue) } ?? "removed") }
    private var allowNSFW: Bool { sources.nsfwSourceIDs.contains(sourceID) }
    private var taskKey: String { sourceKey + ":" + query + ":\(retry):\(allowNSFW):" + selection.tags.sorted().joined(separator: ",") + ":" + selection.tagMode + ":" + selection.status + ":" + selection.sort }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if source != nil {
                    Section {
                        Toggle("Show NSFW content", isOn: Binding(
                            get: { allowNSFW },
                            set: { sources.setAllowNSFW($0, sourceID: sourceID) }
                        ))
                    } header: { Text("Content") } footer: {
                        Text("Saved for this source. Requires an extension that supports NSFW content; update the source if needed.")
                    }
                }
                if selection.count > 0 {
                    Section {
                        Text(activeFilters).font(Design.font(.subheadline)).foregroundStyle(.secondary)
                        Button("Clear filters") { selection = SourceSearchSelection() }
                    }
                }
                if source == nil {
                    ContentUnavailableView("Source removed", systemImage: "network.slash", description: Text("Install this source again in Settings → Sources."))
                } else if loading {
                    ProgressView("Searching source…")
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { retry += 1 }
                } else if results.isEmpty {
                    ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try another title or change your filters."))
                } else {
                    Text("\(results.count) titles").font(Design.section).accessibilityAddTraits(.isHeader)
                    if layout == .list {
                        ForEach(results) { manga in
                            NavigationLink { MangaDetailView(manga: manga) } label: {
                                HStack(spacing: 16) {
                                    CoverArt(manga: manga).frame(width: 64, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    titleInfo(manga)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(PressStyle())
                        }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
                                                 count: typeSize.isAccessibilitySize ? 1 : layout.columnCount),
                                  alignment: .leading, spacing: 24) {
                            ForEach(results) { manga in
                                NavigationLink { MangaDetailView(manga: manga) } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        CoverArt(manga: manga).aspectRatio(0.67, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: Design.coverCorner))
                                        titleInfo(manga)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(PressStyle())
                            }
                        }
                    }
                }
            }.padding(Design.spacing).frame(maxWidth: Design.contentWidth)
                .frame(maxWidth: .infinity, alignment: .top)
        }.pageBackground()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(source?.manifest.name ?? "Source")
            .searchable(text: $query, prompt: "Search this source")
            .alert("Couldn’t save source setting", isPresented: Binding(get: { sources.error != nil }, set: { if !$0 { sources.error = nil } })) {
                Button("OK") { sources.error = nil }
            } message: { Text(sources.error ?? "") }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Layout", selection: $layout) {
                            ForEach(SourceCatalogLayout.allCases, id: \.self) { option in
                                Label(option.rawValue, systemImage: option.symbol).tag(option)
                            }
                        }
                        Toggle("Show author and genre", isOn: $showDetails)
                    } label: {
                        Label("Display options", systemImage: layout.symbol)
                    }.accessibilityLabel("Display options")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingFilters = true } label: {
                        Label(selection.count > 0 ? "Filters (\(selection.count))" : "Filters", systemImage: selection.count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }.disabled(source == nil)
                }
            }
            .sheet(isPresented: $showingFilters) {
                SourceFilterView(filters: filters, selection: $selection, loading: loadingFilters, error: filterError) {
                    Task { await loadFilters() }
                }
            }
            .task(id: sourceKey) {
                filters = SourceFilters(); selection = SourceSearchSelection()
                await loadFilters()
            }
            .task(id: taskKey) {
                loading = true; results = []; error = nil
                do { try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation(); await search() }
                catch { }
            }
    }

    private func titleInfo(_ manga: Manga) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(manga.title).font(Design.font(.subheadline).weight(.semibold)).foregroundStyle(.primary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if showDetails {
                if !manga.author.isEmpty {
                    Text(manga.author).font(Design.font(.caption)).foregroundStyle(.secondary)
                }
                if !manga.genre.isEmpty {
                    Text(manga.genre).font(Design.font(.caption)).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeFilters: String {
        var labels = filters.tags.filter { selection.tags.contains($0.id) }.map(\.name)
        if let status = filters.statuses.first(where: { $0.id == selection.status }) { labels.append(status.name) }
        if let sort = filters.sortOrders.first(where: { $0.id == selection.sort }) { labels.append(sort.name) }
        return labels.joined(separator: " · ")
    }

    @MainActor private func loadFilters() async {
        let key = sourceKey
        loadingFilters = true; filterError = nil
        do {
            let value = try await sources.filters(sourceID: sourceID)
            try Task.checkCancellation()
            guard key == sourceKey else { return }
            filters = value; loadingFilters = false
        } catch {
            guard !Task.isCancelled, key == sourceKey else { return }
            filterError = error.localizedDescription; loadingFilters = false
        }
    }

    @MainActor private func search() async {
        let key = taskKey
        loading = true; error = nil
        do {
            let value = try await sources.search(sourceID: sourceID, query: query, selection: selection)
            try Task.checkCancellation()
            guard key == taskKey else { return }
            results = value; loading = false
        } catch {
            guard !Task.isCancelled, key == taskKey else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
}

private struct SourceFilterView: View {
    @Environment(\.dismiss) private var dismiss
    let filters: SourceFilters
    @Binding var selection: SourceSearchSelection
    let loading: Bool
    let error: String?
    let retry: () -> Void
    @State private var draft = SourceSearchSelection()
    @State private var tagQuery = ""

    private var visibleTags: [SourceFilterOption] {
        let term = tagQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return filters.tags.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Loading filters…") }
                else if let error {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again", action: retry)
                } else if filters.isEmpty {
                    ContentUnavailableView("No filters available", systemImage: "line.3.horizontal.decrease.circle", description: Text("This source does not provide search filters. If an update is available, refresh its repository and install the updated source."))
                } else {
                    if !filters.statuses.isEmpty {
                        Section("Publication") {
                            Picker("Status", selection: $draft.status) {
                                Text("Any status").tag("")
                                ForEach(filters.statuses) { Text($0.name).tag($0.id) }
                            }
                        }
                    }
                    if !filters.sortOrders.isEmpty {
                        Section("Sort") {
                            Picker("Sort by", selection: $draft.sort) {
                                Text("Source default").tag("")
                                ForEach(filters.sortOrders) { Text($0.name).tag($0.id) }
                            }
                        }
                    }
                    if !filters.tags.isEmpty {
                        Section {
                            Picker("Match tags", selection: $draft.tagMode) {
                                Text("All selected").tag("AND")
                                Text("Any selected").tag("OR")
                            }
                            TextField("Search tags", text: $tagQuery).autocorrectionDisabled()
                                .accessibilityLabel("Search tags")
                            if visibleTags.isEmpty { Text("No matching tags").foregroundStyle(.secondary) }
                            ForEach(visibleTags) { tag in
                                Button {
                                    if !draft.tags.insert(tag.id).inserted { draft.tags.remove(tag.id) }
                                } label: {
                                    HStack {
                                        Text(tag.name).foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: draft.tags.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                    }.frame(minHeight: 44)
                                }.accessibilityAddTraits(draft.tags.contains(tag.id) ? [.isSelected] : [])
                            }
                        } header: { Text("Tags (\(draft.tags.count) selected)") }
                    }
                    Section { Button("Reset filters") { draft = SourceSearchSelection(); tagQuery = "" } }
                }
            }.scrollContentBackground(.hidden).pageBackground()
                .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { selection = draft; dismiss() }.disabled(loading || error != nil || filters.isEmpty)
                    }
                }
                .onAppear { draft = selection }
        }
    }
}

struct SourceImage: View {
    @EnvironmentObject private var sources: SourceStore
    let url: URL?
    let sourceID: String
    var fill = false
    var fitWidth = false
    var onLoaded: () -> Void = {}
    var onRetry: (() -> Void)? = nil
    @State private var image: UIImage?
    @State private var error: String?
    @State private var retry = 0
    private var source: InstalledSource? { sources.installed.first { $0.id == sourceID } }
    private var key: String { "\(source.map { String($0.manifest.hashValue) } ?? "removed"):\(url?.absoluteString ?? ""):\(retry)" }

    var body: some View {
        Group {
            if let image {
                if fill { Image(uiImage: image).resizable().scaledToFill() }
                else if fitWidth { Image(uiImage: image).resizable().scaledToFit() }
                else { ZoomableSourcePage(image: image) }
            } else if error != nil {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                    if !fill { Text(error ?? "Couldn’t load page").font(Design.font(.caption)).multilineTextAlignment(.center) }
                    Button("Retry") {
                        if let onRetry { onRetry() } else { retry += 1 }
                    }.frame(minHeight: 44)
                }.foregroundStyle(.secondary).padding()
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(minHeight: fitWidth && image == nil ? 320 : nil)
        .task(id: key) {
            image = nil; error = nil
            do {
                guard let url else { throw SourceError.invalid("No cover available.") }
                let source = try sources.source(sourceID)
                let data = try await SourceNetwork.get(url, hosts: source.manifest.hosts, limit: 20_000_000,
                                                       imageReferer: source.manifest.imageReferer)
                try Task.checkCancellation()
                let decoded = await Task.detached(priority: .userInitiated) {
                    guard let input = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: fill ? 720 : 3600
                          ] as CFDictionary) else { return UIImage?.none }
                    return UIImage(cgImage: thumbnail)
                }.value
                try Task.checkCancellation()
                guard let decoded else { throw SourceError.invalid("The source returned an unreadable image.") }
                image = decoded; onLoaded()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ZoomableSourcePage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> SourcePageScrollView {
        SourcePageScrollView()
    }
    func updateUIView(_ view: SourcePageScrollView, context: Context) {
        guard view.pageImage.image !== image else { return }
        view.setZoomScale(1, animated: false)
        view.pageImage.image = image
    }
}

private final class SourcePageScrollView: UIScrollView, UIScrollViewDelegate {
    let pageImage = UIImageView()
    private var viewport = CGSize.zero
    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1; maximumZoomScale = 4
        pageImage.contentMode = .scaleAspectFit
        addSubview(pageImage)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Offset and zoom changes must not rewrite a transformed image frame.
        guard bounds.size != viewport else { return }
        viewport = bounds.size
        setZoomScale(1, animated: false)
        pageImage.frame = CGRect(origin: .zero, size: viewport)
        contentSize = viewport
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { pageImage }
}
