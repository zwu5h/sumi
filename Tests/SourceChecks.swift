import Foundation

enum SourceChecks {
    @MainActor static func run() throws {
        func rejects(_ operation: () throws -> Void) {
            do { try operation(); preconditionFailure("Expected rejection") } catch { }
        }
        let allowed = ["api.example.org"]
        try SourcePolicy.check(URL(string: "https://api.example.org/catalog")!, hosts: allowed)
        for text in ["http://api.example.org/catalog", "file:///tmp/test", "https://api.example.org.evil.org/",
                     "https://images.example.org/", "https://user:password@api.example.org/",
                     "https://api.example.org:444/", "https://127.0.0.1/", "https://[::1]/", "https://device.local/"] {
            rejects { try SourcePolicy.check(URL(string: text)!, hosts: allowed) }
        }
        let raw = """
        {"schemaVersion":1,"name":"Test","extensions":[{"id":"org.example.test","name":"Test","version":"1.0","apiVersion":1,"script":"https://example.org/source.js","sha256":"\(String(repeating: "a", count: 64))","hosts":["api.example.org"],"website":"https://example.org/","author":"Test author"}]}
        """
        func index(_ text: String) throws -> RepositoryIndex {
            try JSONDecoder().decode(RepositoryIndex.self, from: Data(text.utf8))
        }
        let valid = try index(raw)
        try valid.validate()
        try index(raw.replacingOccurrences(of: "api.example.org", with: "*.example.org")).validate()
        try SourcePolicy.check(URL(string: "https://node.cdn.example.org/page.png")!, hosts: ["*.example.org"])
        for denied in ["https://example.org/", "https://evil-example.org/", "https://node.example.org.evil.org/",
                       "https://user:secret@node.example.org/", "https://node.example.org:444/", "https://*.example.org/"] {
            rejects { try SourcePolicy.check(URL(string: denied)!, hosts: ["*.example.org"]) }
        }
        for changed in [raw.replacingOccurrences(of: "\"apiVersion\":1", with: "\"apiVersion\":2"),
                        raw.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
                        raw.replacingOccurrences(of: "api.example.org", with: "*.org"),
                        raw.replacingOccurrences(of: "api.example.org", with: "api.*.example.org"),
                        raw.replacingOccurrences(of: "api.example.org", with: "api..example.org"),
                        raw.replacingOccurrences(of: "api.example.org", with: "127.0.0.1"),
                        raw.replacingOccurrences(of: String(repeating: "a", count: 64), with: "wrong")] {
            rejects { try index(changed).validate() }
        }
        rejects { try RepositoryIndex(schemaVersion: 1, name: "Duplicate", extensions: [valid.extensions[0], valid.extensions[0]]).validate() }

        let tag = SourceFilterOption(id: "adventure", name: "Adventure")
        try SourceFilters(tags: [tag]).validate()
        rejects { try SourceFilters(tags: [tag, tag]).validate() }
        rejects { try SourceFilters(statuses: [.init(id: "", name: "Invalid")]).validate() }
        rejects { try SourceFilters(sortOrders: [.init(id: "title", name: "")]).validate() }
        var selection = SourceSearchSelection()
        precondition(selection.count == 0)
        selection.tags = ["fantasy", "adventure"]
        selection.tagMode = "OR"; selection.status = "completed"; selection.sort = "title"
        precondition(selection.count == 4)
        let selectedTags = try JSONDecoder().decode([String].self, from: Data(selection.input["tags"]!.utf8))
        precondition(selectedTags == ["adventure", "fantasy"])
        precondition(selection.input["tagMode"] == "OR" && selection.input["status"] == "completed" && selection.input["sort"] == "title")

        // Older local PDFs have no remote field; the existing library must still decode.
        let legacy = Data("""
        {"id":"legacy","title":"Old PDF","author":"Local","synopsis":"","genre":"Imported","palette":0,"chapterCount":1,"fileName":"old.pdf"}
        """.utf8)
        let local = try JSONDecoder().decode(Manga.self, from: legacy)
        precondition(local.remote == nil && local.fileName == "old.pdf")

        let store = LibraryStore()
        let first = SourceChapter(id: "one", title: "One", credit: "Creator")
        let second = SourceChapter(id: "two", title: "Two", credit: "Creator")
        var manga = Manga(id: "source:test:book", title: "Remote book", author: "Creator", synopsis: "", genre: "Test", chapterCount: 2,
                          remote: RemoteMangaReference(sourceID: "test", mangaID: "book", cover: nil, chapters: [first, second]))
        precondition(manga.remote != nil && manga.documentURL == nil)
        store.rememberRemote(manga)
        store.toggleSaved(manga)
        store.record(manga, chapter: 2, page: 1, count: 4)
        manga.remote?.chapters = [second, first]
        store.rememberRemote(manga)
        precondition(store.positions[manga.id]?.chapter == 1 && store.positions[manga.id]?.page == 1)
        let restored = LibraryStore()
        precondition(restored.library.contains { $0.id == manga.id })
        precondition(restored.remoteTitles.first { $0.id == manga.id }?.remote?.chapters == [second, first])
        store.toggleSaved(manga)
        precondition(!LibraryStore().library.contains { $0.id == manga.id }, "Unsaving must persist")
        store.toggleSaved(manga)
        let defaults = UserDefaults.standard
        defaults.set(Array(store.savedIDs.union(["moon", "rain", "night"])), forKey: "savedIDs")
        var legacyPositions = store.positions
        legacyPositions["moon"] = ReadingPosition(page: 1, pageCount: 4)
        defaults.set(try JSONEncoder().encode(legacyPositions), forKey: "positions")
        let migrated = LibraryStore()
        precondition(migrated.savedIDs.isDisjoint(with: ["moon", "rain", "night"]))
        precondition(migrated.positions["moon"] == nil)
        precondition(migrated.library.contains { $0.id == manga.id })
        precondition(migrated.imported.count == store.imported.count)
        manga.remote?.chapters = [first]
        store.rememberRemote(manga)
        precondition(store.positions[manga.id] == nil, "Removed chapter must not resume at an unrelated chapter")
        store.markUnread(manga)
        print("PASS: repository validation, exact/scoped HTTPS permissions and suffix boundaries, legacy PDF decoding, remote library persistence and stable chapter IDs")
    }
}
