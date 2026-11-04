import Foundation

/// Every redirect is checked before a request is sent to its new destination.
final class SourceRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let hosts: [String]
    init(hosts: [String]) { self.hosts = hosts }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, (try? SourcePolicy.check(url, hosts: hosts)) != nil else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

enum SourceNetwork {
    static func get(_ url: URL, hosts: [String], limit: Int = 4_000_000) async throws -> Data {
        try SourcePolicy.check(url, hosts: hosts)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let delegate = SourceRedirectPolicy(hosts: hosts)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Sumi/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw SourceError.invalid("The source returned an unsuccessful response. Please try again later.")
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
