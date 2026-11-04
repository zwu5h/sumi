import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum SourceNetworkChecks {
    static func run() throws {
        let hosts = ["toontop.io", "api.toontop.io", "rx.toontop.io"]
        let image = URL(string: "https://rx.toontop.io/page.webp")!
        let referer = URL(string: "https://toontop.io/")!
        let request = try SourceNetwork.request(image, hosts: hosts, imageReferer: referer)
        precondition(request.value(forHTTPHeaderField: "Referer") == referer.absoluteString)
        precondition(request.value(forHTTPHeaderField: "User-Agent") == "Sumi/1.0")
        let plain = try SourceNetwork.request(URL(string: "https://api.toontop.io/titles/example/chapters")!, hosts: hosts)
        precondition(plain.value(forHTTPHeaderField: "Referer") == nil, "Metadata requests must not get an image referer")
        let legacy = try SourceNetwork.request(image, hosts: hosts)
        precondition(legacy.value(forHTTPHeaderField: "Referer") == nil)
        do {
            _ = try SourceNetwork.request(URL(string: "https://evil.org/page.webp")!, hosts: hosts, imageReferer: referer)
            preconditionFailure("Undeclared image host must be rejected")
        } catch { }

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: image) // Not resumed; only exercises redirect policy.
        let response = HTTPURLResponse(url: image, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let delegate = SourceRedirectPolicy(hosts: hosts, imageReferer: referer)
        var allowedRedirect = false
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "https://rx.toontop.io/next.webp")!)) { redirected in
            precondition(redirected?.value(forHTTPHeaderField: "Referer") == referer.absoluteString)
            allowedRedirect = true
        }
        precondition(allowedRedirect)
        for destination in ["https://evil.org/page.webp", "http://rx.toontop.io/page.webp", "https://rx.toontop.io.evil.org/page.webp"] {
            var rejected = false
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                newRequest: URLRequest(url: URL(string: destination)!)) { redirected in
                precondition(redirected == nil)
                rejected = true
            }
            precondition(rejected)
        }
        print("PASS: image referer request header, legacy requests, allowed redirects and denied redirect hosts")
    }
}
