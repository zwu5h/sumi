import Foundation
import WebKit

/// Each operation gets a fresh, nonpersistent WebKit process context. No app data,
/// files, credentials or device APIs are passed to extension code.
@MainActor
final class SourceRuntime: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private var webView: WKWebView!
    private var ready: CheckedContinuation<Void, Error>?
    private var pending: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var requests: [UUID: Task<Void, Never>] = [:]
    private var requestCount = 0
    private let hosts: [String]
    private var closed = false

    init(hosts: [String]) {
        self.hosts = hosts
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "request")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
    }

    func call<T: Decodable>(_ operation: String, input: [String: String], source: InstalledSource, as type: T.Type) async throws -> T {
        defer { close() }
        let result: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(35)) } catch { return }
                    self?.finish(.failure(SourceError.invalid("The extension took too long to respond.")))
                    self?.close()
                }
                Task { [self] in
                    do {
                        try Task.checkCancellation()
                        guard !closed else { throw CancellationError() }
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            ready = continuation
                            // The CSP prevents script-created fetches, images, frames, forms or external scripts.
                            webView.loadHTMLString("<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; connect-src 'none'; form-action 'none'; base-uri 'none'\"><title>Sumi extension</title>", baseURL: nil)
                        }
                        guard !closed else { throw CancellationError() }
                        let body = """
                        const stringify = JSON.stringify.bind(JSON);
                        const api = Object.freeze({request: async (url) => {
                            const text = await window.webkit.messageHandlers.request.postMessage({url});
                            return {text, json: () => JSON.parse(text)};
                        }});
                        const source = new Function('"use strict";\\n' + code + '\\n;return source;')();
                        if (operation === '__validate') {
                            return stringify(typeof source === 'object' && source !== null &&
                                typeof source.search === 'function' && typeof source.chapters === 'function' && typeof source.pages === 'function');
                        }
                        if (operation === '__filters') {
                            const value = stringify(typeof source.filters === 'function'
                                ? await source.filters(input, api) : {tags: [], statuses: [], sortOrders: []});
                            if (typeof value !== 'string' || value.length > 4000000) throw new Error('Invalid extension result');
                            return value;
                        }
                        if (typeof source !== 'object' || typeof source[operation] !== 'function') {
                            throw new Error('Extension does not implement ' + operation);
                        }
                        const value = stringify(await source[operation](input, api));
                        if (typeof value !== 'string' || value.length > 4000000) throw new Error('Invalid extension result');
                        return value;
                        """
                        webView.callAsyncJavaScript(body, arguments: ["operation": operation, "input": input, "code": source.code], in: nil, in: .page) { [weak self] result in
                            switch result {
                            case .success(let value):
                                guard let string = value as? String, string.utf8.count <= 4_000_000 else {
                                    self?.finish(.failure(SourceError.invalid("The extension returned invalid data."))); return
                                }
                                self?.finish(.success(string))
                            case .failure(let error): self?.finish(.failure(error))
                            }
                        }
                    } catch { finish(.failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())); self?.close() }
        }
        return try JSONDecoder().decode(type, from: Data(result.utf8))
    }

    private func finish(_ result: Result<String, Error>) {
        let continuation = pending
        pending = nil
        timeout?.cancel()
        continuation?.resume(with: result)
    }

    private func close() {
        guard !closed else { return }
        closed = true
        ready?.resume(throwing: CancellationError()); ready = nil
        requests.values.forEach { $0.cancel() }; requests.removeAll()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "request", contentWorld: .page)
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready?.resume(); ready = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        ready?.resume(throwing: error); ready = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        ready?.resume(throwing: error); ready = nil
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(SourceError.invalid("The extension stopped unexpectedly."))); close()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard !closed, requestCount < 30, requests.count < 4,
              let body = message.body as? [String: Any], let value = body["url"] as? String, value.utf8.count <= 16_384,
              let url = URL(string: value), (try? SourcePolicy.check(url, hosts: hosts)) != nil else {
            replyHandler(nil, "Request denied: check extension hosts or request limits."); return
        }
        requestCount += 1
        let id = UUID()
        requests[id] = Task { [self] in
            defer { requests[id] = nil }
            do {
                let data = try await SourceNetwork.get(url, hosts: hosts)
                guard let text = String(data: data, encoding: .utf8) else { throw SourceError.invalid("Expected UTF-8 text.") }
                replyHandler(text, nil)
            } catch { replyHandler(nil, error.localizedDescription) }
        }
    }
}
