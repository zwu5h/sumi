import Foundation
import SwiftUI

struct ReaderProfile: Identifiable, Codable, Equatable {
    let id: String
    var name: String
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [ReaderProfile]
    @Published private(set) var activeID: String = "default"
    private let defaults: UserDefaults
    private let suitePrefix: String

    init(defaults: UserDefaults = .standard, suitePrefix: String = "com.sumi.reader.profile.") {
        self.defaults = defaults
        self.suitePrefix = suitePrefix
        let stored = StoredData.array(ReaderProfile.self, key: "readerProfiles", defaults: defaults)
        var seen = Set<String>()
        profiles = stored.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted }
        if !profiles.contains(where: { $0.id == "default" }) {
            profiles.insert(ReaderProfile(id: "default", name: "Default"), at: 0)
        }
        let savedID = defaults.string(forKey: "activeReaderProfile") ?? "default"
        activeID = profiles.contains(where: { $0.id == savedID }) ? savedID : "default"
        persist()
    }

    var activeProfile: ReaderProfile { profiles.first { $0.id == activeID }! }
    var activeDefaults: UserDefaults { storage(for: activeID) }

    func storage(for id: String) -> UserDefaults {
        // Retain the existing library and preferences without copying or deleting data.
        id == "default" ? defaults : UserDefaults(suiteName: suitePrefix + id)!
    }

    @discardableResult
    func create(name: String) -> Bool {
        guard let name = validName(name) else { return false }
        let profile = ReaderProfile(id: UUID().uuidString, name: name)
        profiles.append(profile)
        activeID = profile.id
        persist()
        return true
    }

    @discardableResult
    func rename(_ id: String, to name: String) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              let name = validName(name, excluding: id) else { return false }
        profiles[index].name = name
        persist()
        return true
    }

    func select(_ id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        persist()
    }

    private func validName(_ input: String, excluding id: String? = nil) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40,
              !profiles.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { return nil }
        return name
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(profiles), forKey: "readerProfiles")
        defaults.set(activeID, forKey: "activeReaderProfile")
    }
}
