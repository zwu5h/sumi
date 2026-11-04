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
    var chapterCount: Int = 6
    var fileName: String? = nil
    var remote: RemoteMangaReference? = nil
    var documentURL: URL? {
        guard let name = fileName, name.lowercased().hasSuffix(".pdf"),
              !name.contains("/"), !name.contains("\\"), !name.contains(":"), !name.hasPrefix(".") else { return nil }
        return LibraryStore.documents.appendingPathComponent(name)
    }
    var thumbnailURL: URL? { documentURL.map { $0.appendingPathExtension("png") } }
}

@MainActor
final class LibraryStore: ObservableObject {
    nonisolated static var documents: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sumi", isDirectory: true)
    }
    nonisolated static func migrateDocuments() throws {
        let manager = FileManager.default
        let legacy = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try manager.createDirectory(at: documents, withIntermediateDirectories: true)
        guard legacy != documents, manager.fileExists(atPath: legacy.path) else { return }
        for item in try manager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: [.isRegularFileKey]) {
            let name = item.lastPathComponent
            guard name == "sources-v1.json" || name.lowercased().hasSuffix(".pdf") || name.lowercased().hasSuffix(".pdf.png"),
                  try item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let target = documents.appendingPathComponent(name)
            // Never overwrite a newer private file or discard a conflicting legacy copy.
            if !manager.fileExists(atPath: target.path) { try manager.moveItem(at: item, to: target) }
        }
    }
    @Published var imported: [Manga] = []
    @Published private(set) var remoteTitles: [Manga] = []
    @Published var savedIDs: Set<String> = []
    @Published var positions: [String: ReadingPosition] = [:]
    @Published private(set) var chapterPositions: [String: [String: ReadingPosition]] = [:]
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do { try Self.migrateDocuments() } catch { self.error = "Couldn’t migrate documents: \(error.localizedDescription)" }
        imported = StoredData.array(Manga.self, key: "imported", defaults: defaults)
        remoteTitles = StoredData.array(Manga.self, key: "remoteTitles", defaults: defaults)
        if let pending = StoredData.read(Manga.self, key: "pendingPDFImportRecord", defaults: defaults),
           let url = pending.documentURL, FileManager.default.fileExists(atPath: url.path), !imported.contains(where: { $0.id == pending.id }) {
            // Final files are moved out of staging only after PDF validation.
            imported.insert(pending, at: 0)
        }
        for index in imported.indices { imported[index].chapterCount = min(10_000, max(1, imported[index].chapterCount)) }
        for index in remoteTitles.indices { remoteTitles[index].chapterCount = min(10_000, max(1, remoteTitles[index].chapterCount)) }
        if let ids = defaults.stringArray(forKey: "savedIDs") { savedIDs = Set(ids) }
        if let pending = StoredData.read(Manga.self, key: "pendingPDFImportRecord", defaults: defaults), imported.contains(where: { $0.id == pending.id }) { savedIDs.insert(pending.id) }
        positions = StoredData.read([String: ReadingPosition].self, key: "positions", defaults: defaults) ?? [:]
        chapterPositions = StoredData.read([String: [String: ReadingPosition]].self, key: "chapterPositions", defaults: defaults) ?? [:]
        for manga in catalog {
            positions[manga.id] = positions[manga.id]?.normalized(chapterCount: manga.chapterCount)
            chapterPositions[manga.id] = chapterPositions[manga.id]?.mapValues { $0.normalized(chapterCount: manga.chapterCount) }
        }
        let staging = Self.documents.appendingPathComponent(".imports", isDirectory: true)
        for name in defaults.stringArray(forKey: "pendingPDFImports") ?? [] where name.hasSuffix(".pdf") && UUID(uuidString: String(name.dropLast(4))) != nil {
            try? FileManager.default.removeItem(at: staging.appendingPathComponent(name))
            try? FileManager.default.removeItem(at: staging.appendingPathComponent(name + ".png"))
        }
        defaults.removeObject(forKey: "pendingPDFImports")
        if (try? FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: staging)
        }
        // Migrate only the known chapter; a later chapter does not prove earlier ones were read.
        for (id, position) in positions {
            if let manga = (imported + remoteTitles).first(where: { $0.id == id }),
               chapterPositions[id] == nil {
                chapterPositions[id] = [chapterKey(manga, chapter: position.chapter): position]
            }
        }
        // Remove only the retired bundled demos; imported and online titles stay intact.
        for id in ["moon", "rain", "night"] where !catalog.contains(where: { $0.id == id }) {
            savedIDs.remove(id)
            positions.removeValue(forKey: id)
            chapterPositions.removeValue(forKey: id)
        }
        persist()
        defaults.removeObject(forKey: "pendingPDFImportRecord")
    }

    var catalog: [Manga] { imported + remoteTitles }
    var library: [Manga] { catalog.filter { savedIDs.contains($0.id) } }
    var recent: Manga? {
        library.filter { positions[$0.id] != nil && !isComplete($0) }
            .max { positions[$0.id]!.updatedAt < positions[$1.id]!.updatedAt }
    }
    func progress(for manga: Manga) -> Double {
        (1...max(1, manga.chapterCount)).reduce(0.0) { total, chapter in
            total + (chapterPosition(manga, chapter: chapter)?.chapterProgress ?? 0)
        } / Double(max(1, manga.chapterCount))
    }
    func isComplete(_ manga: Manga) -> Bool {
        (1...max(1, manga.chapterCount)).allSatisfy { chapterPosition(manga, chapter: $0)?.chapterProgress == 1 }
    }
    private func chapterKey(_ manga: Manga, chapter: Int) -> String {
        if chapter > 0, let chapters = manga.remote?.chapters, chapters.indices.contains(chapter - 1) {
            return "remote:" + chapters[chapter - 1].id
        }
        return "chapter:\(chapter)"
    }
    func chapterPosition(_ manga: Manga, chapter: Int) -> ReadingPosition? {
        chapterPositions[manga.id]?[chapterKey(manga, chapter: chapter)]
    }
    func toggleSaved(_ manga: Manga) {
        if savedIDs.contains(manga.id) {
            savedIDs.remove(manga.id)
        } else {
            if manga.remote != nil { rememberRemote(manga) }
            savedIDs.insert(manga.id)
        }
        persist()
    }
    func rememberRemote(_ manga: Manga) {
        guard manga.remote != nil else { return }
        if manga.remote?.chapters == nil, remoteTitles.contains(where: { $0.id == manga.id && $0.remote?.chapters != nil }) { return }
        if let previous = remoteTitles.first(where: { $0.id == manga.id }),
           let old = previous.remote?.chapters, let updated = manga.remote?.chapters,
           let position = positions[manga.id], old != updated {
            if position.chapter > 0, old.indices.contains(position.chapter - 1),
               let index = updated.firstIndex(where: { $0.id == old[position.chapter - 1].id }) {
                var remapped = position
                remapped.chapter = index + 1
                positions[manga.id] = remapped
            } else { positions[manga.id] = nil }
        }
        if let updated = manga.remote?.chapters {
            for (index, chapter) in updated.enumerated() {
                let legacyKey = "chapter:\(index + 1)"
                if let legacy = chapterPositions[manga.id]?[legacyKey] {
                    if chapterPositions[manga.id]?["remote:" + chapter.id] == nil {
                        chapterPositions[manga.id, default: [:]]["remote:" + chapter.id] = legacy
                    }
                    chapterPositions[manga.id]?[legacyKey] = nil
                }
            }
        }
        remoteTitles.removeAll { $0.id == manga.id }
        remoteTitles.append(manga)
        persist()
    }
    func markUnread(_ manga: Manga) {
        positions.removeValue(forKey: manga.id)
        chapterPositions.removeValue(forKey: manga.id)
        persist()
    }
    func record(_ manga: Manga, chapter: Int, page: Int, count: Int) {
        positions[manga.id] = ReadingPosition(chapter: chapter, page: page, pageCount: count)
            .normalized(chapterCount: manga.chapterCount)
        chapterPositions[manga.id, default: [:]][chapterKey(manga, chapter: chapter)] = positions[manga.id]
        persist()
    }
    func persist() {
        defaults.set(try? JSONEncoder().encode(imported), forKey: "imported")
        defaults.set(try? JSONEncoder().encode(remoteTitles), forKey: "remoteTitles")
        defaults.set(Array(savedIDs), forKey: "savedIDs")
        defaults.set(try? JSONEncoder().encode(positions), forKey: "positions")
        defaults.set(try? JSONEncoder().encode(chapterPositions), forKey: "chapterPositions")
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
        let manga = Manga(id: id, title: url.deletingPathExtension().lastPathComponent, author: "Local document", synopsis: "Your imported manga. Available on this device, even when you’re offline.", genre: "Imported", chapterCount: 1, fileName: filename)
        defaults.set(try JSONEncoder().encode(manga), forKey: "pendingPDFImportRecord")
        let destination = Self.documents.appendingPathComponent(filename)
        let staging = Self.documents.appendingPathComponent(".imports", isDirectory: true)
        let staged = staging.appendingPathComponent(filename)
        let thumbnail = staged.appendingPathExtension("png")
        // A hard interruption leaves only a staging copy, never an invisible library PDF.
        let pendingKey = "pendingPDFImports"
        var pending = defaults.stringArray(forKey: pendingKey) ?? []
        for name in pending where UUID(uuidString: String(name.dropLast(4))) != nil && name.hasSuffix(".pdf") {
            try? FileManager.default.removeItem(at: staging.appendingPathComponent(name))
        }
        pending = [filename]
        defaults.set(pending, forKey: pendingKey)
        var committed = false
        defer {
            try? FileManager.default.removeItem(at: staged)
            try? FileManager.default.removeItem(at: thumbnail)
            if (try? FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: staging)
            }
            defaults.removeObject(forKey: pendingKey)
            defaults.removeObject(forKey: "pendingPDFImportRecord")
            if !committed {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.removeItem(at: thumbnail)
            }
        }
        // Copy outside the main actor; PDF parsing and UIKit thumbnail rendering stay isolated.
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: Self.documents, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let resolved = url.resolvingSymlinksInPath()
            try FileManager.default.copyItem(at: resolved, to: staged)
        }.value
        try checkImportCancellation()
        guard let document = PDFDocument(url: staged), document.pageCount > 0, !document.isLocked else {
            throw ImportError.invalidPDF
        }
        if let page = document.page(at: 0), let data = page.thumbnail(of: CGSize(width: 480, height: 720), for: .cropBox).pngData() {
            try? data.write(to: thumbnail, options: .atomic)
        }
        try checkImportCancellation()
        try FileManager.default.moveItem(at: staged, to: destination)
        if FileManager.default.fileExists(atPath: thumbnail.path) {
            try? FileManager.default.moveItem(at: thumbnail, to: destination.appendingPathExtension("png"))
        }
        imported.insert(manga, at: 0)
        savedIDs.insert(id)
        persist()
        committed = true
    }

    func removeImport(_ manga: Manga) {
        // Keep the record if deletion fails so the user can retry.
        do {
            guard imported.contains(where: { $0.id == manga.id && $0.fileName == manga.fileName }), manga.documentURL != nil else {
                throw ImportError.invalidPDF
            }
            if let url = manga.documentURL, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            if let thumbnail = manga.thumbnailURL { try? FileManager.default.removeItem(at: thumbnail) }
            imported.removeAll { $0.id == manga.id }
            savedIDs.remove(manga.id)
            positions.removeValue(forKey: manga.id)
            chapterPositions.removeValue(forKey: manga.id)
            persist()
        } catch { self.error = error.localizedDescription }
    }
}

enum ImportError: LocalizedError {
    case invalidPDF
    var errorDescription: String? { "This PDF is empty, locked, or unreadable. Please choose an unlocked PDF." }
}
