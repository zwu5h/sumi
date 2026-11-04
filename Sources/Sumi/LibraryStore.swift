import Foundation
import PDFKit
import SwiftUI

struct PDFImportProgress {
    var completed: Int
    let total: Int
    let currentFile: String
    var fraction: Double { Double(completed) / Double(max(1, total)) }
}

struct Manga: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var author: String
    var synopsis: String
    var genre: String
    var palette: Int = 0
    var chapterCount: Int = 6
    var fileName: String? = nil
    var remote: RemoteMangaReference? = nil
    var isSample: Bool { fileName == nil && remote == nil }
    var artResourceName: String { palette == 1 ? "rain" : palette == 2 ? "night" : "moonlit" }
    var documentURL: URL? { fileName.map { LibraryStore.documents.appendingPathComponent($0) } }
    var thumbnailURL: URL? { fileName.map { LibraryStore.documents.appendingPathComponent($0 + ".png") } }
}

@MainActor
final class LibraryStore: ObservableObject {
    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    @Published var imported: [Manga] = []
    @Published private(set) var remoteTitles: [Manga] = []
    @Published var savedIDs: Set<String> = ["moon", "rain"]
    @Published var positions: [String: ReadingPosition] = [:]
    @Published var error: String?
    @Published private(set) var importProgress: PDFImportProgress?
    @Published private(set) var isCancellingImport = false
    var isImporting: Bool { importProgress != nil }

    func cancelImport() {
        guard isImporting else { return }
        isCancellingImport = true
    }

    private func checkImportCancellation() throws {
        try Task.checkCancellation()
        if isCancellingImport { throw CancellationError() }
    }

    static let samples: [Manga] = [
        Manga(id: "moon", title: "Under a Paper Moon", author: "Sumi Studio", synopsis: "Above a city that has forgotten the stars, a wandering cartographer follows a trail of paper lanterns. A quiet journey through memory, rooftops, and the spaces between words.", genre: "Adventure", chapterCount: 6),
        Manga(id: "rain", title: "The Sound of Rain", author: "Sumi Studio", synopsis: "An abandoned station. A letter without a name. Two strangers return to a mountain town with a story neither of them remembers.", genre: "Slice of life", palette: 1, chapterCount: 4),
        Manga(id: "night", title: "Where the Night Ends", author: "Sumi Studio", synopsis: "At the edge of the sleeping city, a keeper of lanterns discovers that every light holds a story.", genre: "Fantasy", palette: 2, chapterCount: 5)
    ]

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "imported"), let items = try? JSONDecoder().decode([Manga].self, from: data) { imported = items }
        if let data = defaults.data(forKey: "remoteTitles"), let items = try? JSONDecoder().decode([Manga].self, from: data) { remoteTitles = items }
        if let ids = defaults.stringArray(forKey: "savedIDs") { savedIDs = Set(ids) }
        if let data = defaults.data(forKey: "positions"), let items = try? JSONDecoder().decode([String: ReadingPosition].self, from: data) { positions = items }
    }

    var catalog: [Manga] { imported + remoteTitles + Self.samples }
    var library: [Manga] { catalog.filter { savedIDs.contains($0.id) } }
    var recent: Manga? {
        library.filter { positions[$0.id] != nil && !isComplete($0) }
            .max { positions[$0.id]!.updatedAt < positions[$1.id]!.updatedAt }
    }
    func progress(for manga: Manga) -> Double {
        guard let p = positions[manga.id] else { return 0 }
        return p.progress(chapterCount: manga.chapterCount)
    }
    func isComplete(_ manga: Manga) -> Bool {
        positions[manga.id]?.isComplete(chapterCount: manga.chapterCount) ?? false
    }
    func toggleSaved(_ manga: Manga) {
        if manga.remote != nil { rememberRemote(manga) }
        if savedIDs.contains(manga.id) { savedIDs.remove(manga.id) } else { savedIDs.insert(manga.id) }
        persist()
    }
    func rememberRemote(_ manga: Manga) {
        guard manga.remote != nil else { return }
        if let previous = remoteTitles.first(where: { $0.id == manga.id }),
           let old = previous.remote?.chapters, let updated = manga.remote?.chapters,
           let position = positions[manga.id], old != updated {
            if old.indices.contains(position.chapter - 1),
               let index = updated.firstIndex(where: { $0.id == old[position.chapter - 1].id }) {
                var remapped = position
                remapped.chapter = index + 1
                positions[manga.id] = remapped
            } else { positions[manga.id] = nil }
        }
        remoteTitles.removeAll { $0.id == manga.id }
        remoteTitles.append(manga)
        persist()
    }
    func markUnread(_ manga: Manga) {
        positions.removeValue(forKey: manga.id)
        persist()
    }
    func record(_ manga: Manga, chapter: Int, page: Int, count: Int) {
        positions[manga.id] = ReadingPosition(chapter: chapter, page: page, pageCount: count)
            .normalized(chapterCount: manga.chapterCount)
        persist()
    }
    func persist() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(imported), forKey: "imported")
        defaults.set(try? JSONEncoder().encode(remoteTitles), forKey: "remoteTitles")
        defaults.set(Array(savedIDs), forKey: "savedIDs")
        defaults.set(try? JSONEncoder().encode(positions), forKey: "positions")
    }

    func importPDF(_ url: URL) async {
        await importPDFs([url])
    }

    /// Imports independently so one unreadable document does not discard the others.
    func importPDFs(_ urls: [URL]) async {
        guard !isImporting, !urls.isEmpty else { return }
        error = nil
        isCancellingImport = false
        importProgress = PDFImportProgress(completed: 0, total: urls.count, currentFile: urls[0].lastPathComponent)
        defer { importProgress = nil; isCancellingImport = false }
        var failures: [String] = []
        var succeeded = 0
        for (index, url) in urls.enumerated() {
            if Task.isCancelled || isCancellingImport { break }
            importProgress = PDFImportProgress(completed: index, total: urls.count, currentFile: url.lastPathComponent)
            // Let progress render before doing PDFKit's main-actor work.
            await Task.yield()
            do {
                try await importDocument(url)
                succeeded += 1
            } catch is CancellationError {
                break
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            importProgress = PDFImportProgress(completed: index + 1, total: urls.count, currentFile: url.lastPathComponent)
        }
        if !failures.isEmpty {
            let summary = succeeded > 0 ? "Imported \(succeeded) of \(urls.count) PDFs.\n\n" : ""
            error = summary + failures.joined(separator: "\n\n")
        }
    }

    private func importDocument(_ url: URL) async throws {
        try checkImportCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let id = UUID().uuidString
        let filename = id + ".pdf"
        let destination = Self.documents.appendingPathComponent(filename)
        let thumbnail = Self.documents.appendingPathComponent(filename + ".png")
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.removeItem(at: thumbnail)
            }
        }
        // Copy outside the main actor; PDF parsing and UIKit thumbnail rendering stay isolated.
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: Self.documents, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
        }.value
        try checkImportCancellation()
        guard let document = PDFDocument(url: destination), document.pageCount > 0, !document.isLocked else {
            throw ImportError.invalidPDF
        }
        if let page = document.page(at: 0), let data = page.thumbnail(of: CGSize(width: 480, height: 720), for: .cropBox).pngData() {
            try? data.write(to: thumbnail, options: .atomic)
        }
        try checkImportCancellation()
        let manga = Manga(id: id, title: url.deletingPathExtension().lastPathComponent, author: "Local document", synopsis: "Your imported manga. Available on this device, even when you’re offline.", genre: "Imported", chapterCount: 1, fileName: filename)
        imported.insert(manga, at: 0)
        savedIDs.insert(id)
        persist()
        committed = true
    }

    func removeImport(_ manga: Manga) {
        // Keep the record if deletion fails so the user can retry.
        do {
            if let url = manga.documentURL, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            if let thumbnail = manga.thumbnailURL { try? FileManager.default.removeItem(at: thumbnail) }
            imported.removeAll { $0.id == manga.id }
            savedIDs.remove(manga.id)
            positions.removeValue(forKey: manga.id)
            persist()
        } catch { self.error = error.localizedDescription }
    }
}

enum ImportError: LocalizedError {
    case invalidPDF
    var errorDescription: String? { "This PDF is empty, locked, or unreadable. Please choose an unlocked PDF." }
}
