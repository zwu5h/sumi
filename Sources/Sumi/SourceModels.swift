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

struct SourceFilterOption: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct SourceFilters: Codable {
    var tags: [SourceFilterOption] = []
    var statuses: [SourceFilterOption] = []
    var sortOrders: [SourceFilterOption] = []
    var isEmpty: Bool { tags.isEmpty && statuses.isEmpty && sortOrders.isEmpty }

    func validate() throws {
        for options in [tags, statuses, sortOrders] {
            guard options.count <= 500, Set(options.map(\.id)).count == options.count,
                  options.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 500 && !$0.name.isEmpty && $0.name.count <= 120 }) else {
                throw SourceError.invalid("The source returned invalid search filters.")
            }
        }
    }
}

struct SourceSearchSelection: Equatable {
    var tags: Set<String> = []
    var tagMode = "AND"
    var status = ""
    var sort = ""
    var count: Int { tags.count + (status.isEmpty ? 0 : 1) + (sort.isEmpty ? 0 : 1) }
    var input: [String: String] {
        ["tags": String(data: try! JSONEncoder().encode(tags.sorted()), encoding: .utf8)!,
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
