import SwiftUI
import CryptoKit

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var repositories: [SourceRepository] = []
    @Published private(set) var installed: [InstalledSource] = []
    @Published private(set) var busy = false
    @Published var error: String?
    private let file: URL

    private struct State: Codable {
        var repositories: [SourceRepository]
        var installed: [InstalledSource]
    }

    init() {
        file = LibraryStore.documents.appendingPathComponent("sources-v1.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
            for repository in state.repositories {
                try SourcePolicy.check(repository.url)
                try RepositoryIndex(schemaVersion: 1, name: repository.name, extensions: repository.extensions).validate()
            }
            for source in state.installed {
                try source.manifest.validate()
                guard Self.digest(Data(source.code.utf8)) == source.manifest.sha256.lowercased() else {
                    throw SourceError.invalid("An installed extension failed its integrity check.")
                }
            }
            repositories = state.repositories
            installed = state.installed
        } catch { self.error = "Couldn’t restore sources: \(error.localizedDescription)" }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func commit(repositories: [SourceRepository], installed: [InstalledSource]) throws {
        let data = try JSONEncoder().encode(State(repositories: repositories, installed: installed))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        self.repositories = repositories
        self.installed = installed
    }

    func addRepository(_ text: String) async {
        guard !busy else { return }
        error = nil
        busy = true; defer { busy = false }
        do {
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SourceError.invalid("Enter the HTTPS URL of a Sumi repository JSON file.")
            }
            try SourcePolicy.check(url)
            let data = try await SourceNetwork.get(url, hosts: [url.host!.lowercased()], limit: 500_000)
            let index = try JSONDecoder().decode(RepositoryIndex.self, from: data)
            try index.validate()
            let repository = SourceRepository(url: url, name: index.name, extensions: index.extensions)
            var updated = repositories.filter { $0.url != url }; updated.append(repository)
            try commit(repositories: updated, installed: installed)
        } catch { self.error = error.localizedDescription }
    }

    func install(_ manifest: SourceManifest, from repository: SourceRepository) async {
        guard !busy else { return }
        error = nil
        busy = true; defer { busy = false }
        do {
            try manifest.validate()
            if let existing = installed.first(where: { $0.id == manifest.id }), existing.repositoryURL != repository.url {
                throw SourceError.invalid("Another repository already owns this extension ID. Remove that extension first.")
            }
            let data = try await SourceNetwork.get(manifest.script, hosts: [manifest.script.host!.lowercased()], limit: 1_000_000)
            guard Self.digest(data) == manifest.sha256.lowercased(), let code = String(data: data, encoding: .utf8) else {
                throw SourceError.invalid("The extension failed its SHA-256 integrity check. Refresh the repository and try again.")
            }
            let source = InstalledSource(manifest: manifest, repositoryURL: repository.url, code: code)
            let valid = try await SourceRuntime(hosts: manifest.hosts).call("__validate", input: [:], source: source, as: Bool.self)
            guard valid else {
                throw SourceError.invalid("This extension must implement search, chapters and pages for Sumi Source API v1.")
            }
            try commit(repositories: repositories, installed: installed.filter { $0.id != source.id } + [source])
        } catch { self.error = error.localizedDescription }
    }

    func removeSource(_ id: String) {
        guard !busy else { return }
        do { try commit(repositories: repositories, installed: installed.filter { $0.id != id }) }
        catch { self.error = error.localizedDescription }
    }

    func removeRepository(_ url: URL) {
        guard !busy else { return }
        do {
            try commit(repositories: repositories.filter { $0.url != url }, installed: installed.filter { $0.repositoryURL != url })
        } catch { self.error = error.localizedDescription }
    }

    func source(_ id: String) throws -> InstalledSource {
        guard let source = installed.first(where: { $0.id == id }) else {
            throw SourceError.invalid("This source is not installed. Install it again in Settings → Sources.")
        }
        return source
    }

    func filters(sourceID: String) async throws -> SourceFilters {
        let source = try source(sourceID)
        let filters = try await SourceRuntime(hosts: source.manifest.hosts).call("__filters", input: [:], source: source, as: SourceFilters.self)
        try filters.validate()
        try ensureCurrent(source)
        return filters
    }

    func search(sourceID: String, query: String, selection: SourceSearchSelection = .init()) async throws -> [Manga] {
        let source = try source(sourceID)
        var input = selection.input
        input["query"] = query
        let titles = try await SourceRuntime(hosts: source.manifest.hosts).call("search", input: input, source: source, as: [SourceTitle].self)
        guard titles.count <= 200, Set(titles.map(\.id)).count == titles.count,
              titles.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 500 && !$0.title.isEmpty }) else {
            throw SourceError.invalid("The extension returned an invalid title list.")
        }
        for title in titles { if let cover = title.cover { try SourcePolicy.check(cover, hosts: source.manifest.hosts) } }
        try ensureCurrent(source)
        return titles.map { $0.manga(sourceID: sourceID) }
    }

    func chapters(_ reference: RemoteMangaReference) async throws -> [SourceChapter] {
        let source = try source(reference.sourceID)
        let chapters = try await SourceRuntime(hosts: source.manifest.hosts).call("chapters", input: ["mangaID": reference.mangaID], source: source, as: [SourceChapter].self)
        guard !chapters.isEmpty, chapters.count <= 10_000, Set(chapters.map(\.id)).count == chapters.count,
              chapters.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty }) else {
            throw SourceError.invalid("This title has no readable chapters or returned invalid chapter data.")
        }
        try ensureCurrent(source)
        return chapters
    }

    func pages(_ reference: RemoteMangaReference, chapterID: String) async throws -> [URL] {
        let source = try source(reference.sourceID)
        let pages = try await SourceRuntime(hosts: source.manifest.hosts).call("pages", input: ["mangaID": reference.mangaID, "chapterID": chapterID], source: source, as: [URL].self)
        guard !pages.isEmpty, pages.count <= 500 else { throw SourceError.invalid("This chapter returned no pages or too many pages.") }
        for page in pages { try SourcePolicy.check(page, hosts: source.manifest.hosts) }
        try ensureCurrent(source)
        return pages
    }

    private func ensureCurrent(_ source: InstalledSource) throws {
        guard installed.contains(where: { $0.id == source.id && $0.manifest == source.manifest }) else {
            throw SourceError.invalid("The source changed or was removed. Open it again to continue.")
        }
    }
}
