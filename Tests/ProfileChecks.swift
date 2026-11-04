import Foundation

enum ProfileChecks {
    @MainActor static func run(fixture: URL) async throws {
        let domain = "sumi-profile-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let prefix = domain + "."
        let profiles = ProfileStore(defaults: defaults, suitePrefix: prefix)
        defer {
            for profile in profiles.profiles where profile.id != "default" {
                defaults.removePersistentDomain(forName: prefix + profile.id)
            }
            defaults.removePersistentDomain(forName: domain)
        }

        // Existing installations retain both their collection and preferences.
        let original = LibraryStore(defaults: defaults)
        await original.importPDF(fixture)
        let manga = original.imported[0]
        original.record(manga, chapter: 1, page: 1, count: 3)
        defaults.set("dark", forKey: "appearance")
        precondition(profiles.activeID == "default")
        precondition(LibraryStore(defaults: profiles.activeDefaults).savedIDs.contains(manga.id))
        precondition(!profiles.create(name: " \n "))
        precondition(!profiles.create(name: String(repeating: "a", count: 41)))
        precondition(profiles.create(name: "  Alex  "))
        let alexID = profiles.activeID
        precondition(profiles.activeProfile.name == "Alex")
        precondition(!profiles.create(name: "alex"))
        let alex = LibraryStore(defaults: profiles.activeDefaults)
        precondition(alex.catalog.isEmpty && alex.savedIDs.isEmpty && alex.positions.isEmpty)
        precondition(profiles.activeDefaults.string(forKey: "appearance") == nil)
        profiles.activeDefaults.set("light", forKey: "appearance")
        await alex.importPDF(fixture)
        let alexManga = alex.imported[0]
        precondition(alexManga.id != manga.id && alexManga.fileName != manga.fileName)
        alex.record(alexManga, chapter: 1, page: 2, count: 3)
        precondition(profiles.rename(alexID, to: "Alexandra"))
        precondition(!profiles.rename(alexID, to: "Default"))

        let restored = ProfileStore(defaults: defaults, suitePrefix: prefix)
        precondition(restored.activeID == alexID && restored.activeProfile.name == "Alexandra")
        precondition(LibraryStore(defaults: restored.activeDefaults).positions[alexManga.id]?.page == 2)
        restored.select("nonexistent")
        precondition(restored.activeID == alexID)
        restored.select("default")
        let restoredOriginal = LibraryStore(defaults: restored.activeDefaults)
        precondition(restoredOriginal.imported == original.imported)
        precondition(restoredOriginal.positions[manga.id]?.page == 1)
        precondition(restored.activeDefaults.string(forKey: "appearance") == "dark")
        alex.removeImport(alexManga)
        precondition(FileManager.default.fileExists(atPath: manga.documentURL!.path))
        precondition(LibraryStore(defaults: restored.activeDefaults).savedIDs.contains(manga.id))
        original.removeImport(manga)
        defaults.set("missing", forKey: "activeReaderProfile")
        precondition(ProfileStore(defaults: defaults, suitePrefix: prefix).activeID == "default")
        print("PASS: profile validation, legacy data, isolated libraries/preferences/files, rename, switching and relaunch")
    }
}
