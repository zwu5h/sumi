import Foundation

/// Every redirect is checked before a request is sent to its new destination.
final class SourceRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let hosts: [String]
    let imageReferer: URL?
    init(hosts: [String], imageReferer: URL? = nil) { self.hosts = hosts; self.imageReferer = imageReferer }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, (try? SourcePolicy.check(url, hosts: hosts)) != nil else {
            completionHandler(nil); return
        }
        var redirected = request
        redirected.setValue(imageReferer?.absoluteString, forHTTPHeaderField: "Referer")
        completionHandler(redirected)
    }
}

enum SourceNetwork {
    static func request(_ url: URL, hosts: [String], imageReferer: URL? = nil) throws -> URLRequest {
        try SourcePolicy.check(url, hosts: hosts)
        if let imageReferer { try SourcePolicy.check(imageReferer) }
        var request = URLRequest(url: url)
        request.setValue("Sumi/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(imageReferer?.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    static func get(_ url: URL, hosts: [String], limit: Int = 4_000_000, imageReferer: URL? = nil) async throws -> Data {
        let request = try request(url, hosts: hosts, imageReferer: imageReferer)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let delegate = SourceRedirectPolicy(hosts: hosts, imageReferer: imageReferer)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SourceError.invalid("The source returned an invalid response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SourceError.invalid("The source returned HTTP \(response.statusCode). Please try again later.")
        }
        guard response.expectedContentLength <= limit else { throw SourceError.invalid("The source response is too large.") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw SourceError.invalid("The source response is too large.") }
            data.append(byte)
        }
        return data
    }
}
