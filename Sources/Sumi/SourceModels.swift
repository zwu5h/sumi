import Foundation

enum SourceError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct SourceManifest: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let version: String
    let apiVersion: Int
    let script: URL
    let sha256: String
    let hosts: [String]
    let website: URL
    let author: String
    let imageReferer: URL?

    func validate() throws {
        guard apiVersion == 1, !id.isEmpty, id.count <= 100,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }),
              !name.isEmpty, name.count <= 120, !version.isEmpty, !author.isEmpty,
              sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }),
              !hosts.isEmpty, hosts.count <= 20, Set(hosts).count == hosts.count else {
            throw SourceError.invalid("This extension has an invalid or unsupported manifest.")
        }
        for host in hosts {
            let domain = host.hasPrefix("*.") ? String(host.dropFirst(2)) : host
            guard host == host.lowercased(), SourcePolicy.validDomain(domain) else {
                throw SourceError.invalid("Declare a valid host name or a scoped subdomain permission such as *.example.org.")
            }
        }
        try SourcePolicy.check(script)
        try SourcePolicy.check(website)
        if let imageReferer {
            try SourcePolicy.check(imageReferer)
            guard imageReferer.host?.lowercased() == website.host?.lowercased(),
                  imageReferer.path.isEmpty || imageReferer.path == "/",
                  imageReferer.query == nil, imageReferer.fragment == nil else {
                throw SourceError.invalid("An image referer must be the source website’s HTTPS origin, without a path or query.")
            }
        }
    }
}

struct SourceRepository: Codable, Identifiable {
    let url: URL
    let name: String
    let extensions: [SourceManifest]
    var id: String { url.absoluteString }
}

struct RepositoryIndex: Codable {
    let schemaVersion: Int
    let name: String
    let extensions: [SourceManifest]

    func validate() throws {
        guard schemaVersion == 1, !name.isEmpty, name.count <= 120, extensions.count <= 100,
              Set(extensions.map(\.id)).count == extensions.count else {
            throw SourceError.invalid("This is not a supported Sumi source repository.")
        }
        try extensions.forEach { try $0.validate() }
    }
}

struct InstalledSource: Codable, Identifiable {
    let manifest: SourceManifest
    let repositoryURL: URL
    let code: String
    var id: String { manifest.id }
}

struct RemoteMangaReference: Codable, Hashable {
    let sourceID: String
    let mangaID: String
    let cover: URL?
    var chapters: [SourceChapter]? = nil
}

struct SourceTitle: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let synopsis: String
    let genre: String
    let cover: URL?

    func manga(sourceID: String, chapterCount: Int = 1) -> Manga {
        Manga(id: "source:\(sourceID):\(id)", title: title, author: author, synopsis: synopsis,
              genre: genre, chapterCount: chapterCount,
              remote: RemoteMangaReference(sourceID: sourceID, mangaID: id, cover: cover))
    }
}

/// Legacy extensions return an array; paginated extensions return this envelope.
struct SourceSearchResult: Decodable {
    let titles: [SourceTitle]
    let nextPage: String?

    private enum CodingKeys: String, CodingKey { case titles, nextPage }

    init(from decoder: Decoder) throws {
        if let values = try? decoder.unkeyedContainer() {
            var values = values
            var titles: [SourceTitle] = []
            while !values.isAtEnd { titles.append(try values.decode(SourceTitle.self)) }
            self.titles = titles; nextPage = nil
        } else {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            titles = try values.decode([SourceTitle].self, forKey: .titles)
            nextPage = try values.decodeIfPresent(String.self, forKey: .nextPage)
        }
    }
}

struct SourceCatalogPage {
    let titles: [Manga]
    let nextPage: String?
}

struct SourceFilterOption: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct SourceFilterGroup: Codable, Identifiable {
    let id: String
    let name: String
    let options: [SourceFilterOption]
    var multiple: Bool = false

    private enum CodingKeys: String, CodingKey { case id, name, options, multiple }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        options = try values.decode([SourceFilterOption].self, forKey: .options)
        multiple = try values.decodeIfPresent(Bool.self, forKey: .multiple) ?? false
    }
}

struct SourceFilters: Codable {
    var tags: [SourceFilterOption] = []
    var statuses: [SourceFilterOption] = []
    var sortOrders: [SourceFilterOption] = []
    var supportsNSFW = false
    var supportsExcludedTags = false
    var tagModes = ["AND", "OR"]
    var groups: [SourceFilterGroup] = []
    var isEmpty: Bool { tags.isEmpty && statuses.isEmpty && sortOrders.isEmpty && groups.isEmpty }

    init(tags: [SourceFilterOption] = [], statuses: [SourceFilterOption] = [],
         sortOrders: [SourceFilterOption] = [], supportsNSFW: Bool = false) {
        self.tags = tags; self.statuses = statuses; self.sortOrders = sortOrders
        self.supportsNSFW = supportsNSFW
    }

    private enum CodingKeys: String, CodingKey { case tags, statuses, sortOrders, supportsNSFW, supportsExcludedTags, tagModes, groups }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tags = try values.decodeIfPresent([SourceFilterOption].self, forKey: .tags) ?? []
        statuses = try values.decodeIfPresent([SourceFilterOption].self, forKey: .statuses) ?? []
        sortOrders = try values.decodeIfPresent([SourceFilterOption].self, forKey: .sortOrders) ?? []
        supportsNSFW = try values.decodeIfPresent(Bool.self, forKey: .supportsNSFW) ?? false
        supportsExcludedTags = try values.decodeIfPresent(Bool.self, forKey: .supportsExcludedTags) ?? false
        tagModes = try values.decodeIfPresent([String].self, forKey: .tagModes) ?? ["AND", "OR"]
        groups = try values.decodeIfPresent([SourceFilterGroup].self, forKey: .groups) ?? []
    }

    func validate() throws {
        guard groups.count <= 30, Set(groups.map(\.id)).count == groups.count,
              groups.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && !$0.name.isEmpty && $0.name.count <= 120 }),
              !tagModes.isEmpty, Set(tagModes).count == tagModes.count, tagModes.allSatisfy({ ["AND", "OR"].contains($0) }) else {
            throw SourceError.invalid("The source returned invalid search filter groups.")
        }
        for options in [tags, statuses, sortOrders] + groups.map(\.options) {
            guard options.count <= 500, Set(options.map(\.id)).count == options.count,
                  options.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 500 && !$0.name.isEmpty && $0.name.count <= 120 }) else {
                throw SourceError.invalid("The source returned invalid search filters.")
            }
        }
    }
}

struct SourceSearchSelection: Equatable {
    var tags: Set<String> = []
    var excludedTags: Set<String> = []
    var tagMode = "AND"
    var status = ""
    var sort = ""
    var values: [String: Set<String>] = [:]
    var count: Int { tags.count + excludedTags.count + values.values.reduce(0) { $0 + $1.count } + (status.isEmpty ? 0 : 1) + (sort.isEmpty ? 0 : 1) }
    var key: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return String(data: try! encoder.encode(input), encoding: .utf8)!
    }
    var input: [String: String] {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return ["tags": String(data: try! encoder.encode(tags.sorted()), encoding: .utf8)!,
         "excludedTags": String(data: try! JSONEncoder().encode(excludedTags.sorted()), encoding: .utf8)!,
         "filters": String(data: try! encoder.encode(values.mapValues { $0.sorted() }), encoding: .utf8)!,
         "tagMode": tagMode, "status": status, "sort": sort]
    }
}

struct SourceChapter: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let credit: String
}

enum SourcePolicy {
    static func validDomain(_ host: String) -> Bool {
        host.contains(".") && host.count <= 253 && !host.hasSuffix(".local") &&
        !host.hasSuffix(".localhost") && !host.hasSuffix(".internal") &&
        !host.allSatisfy({ $0.isNumber || $0 == "." }) &&
        !host.split(separator: ".").allSatisfy({ label in
            label.allSatisfy(\.isNumber) || (label.hasPrefix("0x") && label.dropFirst(2).allSatisfy(\.isHexDigit))
        }) &&
        host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") &&
            $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    static func allows(_ host: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            if pattern.hasPrefix("*.") {
                let domain = String(pattern.dropFirst(2))
                return validDomain(domain) && host.hasSuffix("." + domain)
            }
            return pattern == host
        }
    }

    static func check(_ url: URL, hosts: [String]? = nil) throws {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              validDomain(host), hosts == nil || allows(host, patterns: hosts!) else {
            throw SourceError.invalid("Only HTTPS URLs on the permitted hosts are allowed.")
        }
    }
}
