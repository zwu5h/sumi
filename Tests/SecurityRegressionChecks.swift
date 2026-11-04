import Foundation

enum SecurityRegressionChecks {
    @MainActor static func run(fixture: URL) async throws {
        let name = "sumi-security." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = LibraryStore.documents.deletingLastPathComponent().appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyPDF = legacy.appendingPathComponent("migration.pdf")
        try Data("legacy PDF".utf8).write(to: legacyPDF)
        try LibraryStore.migrateDocuments()
        let migratedPDF = LibraryStore.documents.appendingPathComponent("migration.pdf")
        let migratedData = try Data(contentsOf: migratedPDF)
        precondition(migratedData == Data("legacy PDF".utf8))
        precondition(!FileManager.default.fileExists(atPath: legacyPDF.path))
        // A conflicting legacy copy must never overwrite private data.
        try Data("conflict".utf8).write(to: legacyPDF)
        try LibraryStore.migrateDocuments()
        let preservedData = try Data(contentsOf: migratedPDF)
        precondition(preservedData == Data("legacy PDF".utf8))
        precondition(FileManager.default.fileExists(atPath: legacyPDF.path))
        let original = LibraryStore(defaults: defaults)
        await original.importPDF(fixture)
        let manga = original.imported[0]
        let valid = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manga))
        let damaged = try JSONSerialization.data(withJSONObject: [valid, ["id": "broken"]])
        defaults.set(damaged, forKey: "imported")
        let recovered = LibraryStore(defaults: defaults)
        precondition(recovered.imported.count == 1 && recovered.imported[0].id == manga.id)
        precondition(defaults.data(forKey: "imported.recovery") == damaged)
        let profileData = try JSONSerialization.data(withJSONObject: [["id":"default", "name":"Default"], ["id":"other", "name":"Other"], ["id":"broken"]])
        defaults.set(profileData, forKey: "readerProfiles")
        precondition(ProfileStore(defaults: defaults).profiles.count == 2)
        precondition(defaults.data(forKey: "readerProfiles.recovery") == profileData)
        var forged = manga
        for file in ["sources-v1.json", "../other.pdf", "folder/other.pdf", "folder\\other.pdf"] {
            forged.fileName = file
            precondition(forged.documentURL == nil)
        }
        let first = SourceChapter(id: "first", title: "First", credit: "")
        let second = SourceChapter(id: "second", title: "Second", credit: "")
        var remote = Manga(id: "source:test:old", title: "Old", author: "", synopsis: "", genre: "", chapterCount: 1,
                           remote: RemoteMangaReference(sourceID: "test", mangaID: "old", cover: nil))
        defaults.set(try JSONEncoder().encode([remote]), forKey: "remoteTitles")
        defaults.set(try JSONEncoder().encode([remote.id: ReadingPosition(chapter: 1, page: 7, pageCount: 12)]), forKey: "positions")
        let migrated = LibraryStore(defaults: defaults)
        remote.remote?.chapters = [first]
        migrated.rememberRemote(remote)
        precondition(migrated.chapterPosition(remote, chapter: 1)?.page == 7)
        migrated.positions[remote.id] = ReadingPosition(chapter: Int.min)
        remote.remote?.chapters = [second]
        migrated.rememberRemote(remote) // Must not overflow, even for a live corrupted value.
        precondition(migrated.positions[remote.id] == nil)
        let stagedName = UUID().uuidString + ".pdf"
        let staging = LibraryStore.documents.appendingPathComponent(".imports")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent(stagedName)
        try Data("partial".utf8).write(to: staged)
        defaults.set([stagedName], forKey: "pendingPDFImports")
        _ = LibraryStore(defaults: defaults)
        precondition(!FileManager.default.fileExists(atPath: staged.path))
        defaults.set(try JSONEncoder().encode(manga), forKey: "pendingPDFImportRecord")
        defaults.set(Data("[]".utf8), forKey: "imported")
        let interrupted = LibraryStore(defaults: defaults)
        precondition(interrupted.imported.contains(where: { $0.id == manga.id }))
        precondition(interrupted.savedIDs.contains(manga.id))
        interrupted.removeImport(manga)
        print("PASS: corrupt-index recovery, original-byte backup, invalid filenames, chapter migration/overflow, interrupted import recovery")
    }
}
