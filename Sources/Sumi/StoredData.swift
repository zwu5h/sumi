import Foundation

/// Keep the exact original bytes before repairing an unreadable preference.
enum StoredData {
    static func preserve(_ data: Data, key: String, defaults: UserDefaults) {
        let backup = key + ".recovery"
        if let previous = defaults.data(forKey: backup), previous != data {
            defaults.set(data, forKey: backup + "." + UUID().uuidString)
        } else { defaults.set(data, forKey: backup) }
    }

    static func read<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { preserve(data, key: key, defaults: defaults); return nil }
    }

    static func array<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> [T] {
        guard let data = defaults.data(forKey: key) else { return [] }
        if let result = try? JSONDecoder().decode([T].self, from: data) { return result }
        preserve(data, key: key, defaults: defaults)
        guard let values = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return values.compactMap {
            guard let bytes = try? JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed) else { return nil }
            return try? JSONDecoder().decode(type, from: bytes)
        }
    }
}
