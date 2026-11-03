#if os(macOS)
import Foundation
import Network
@testable import SloppyClient

final class BrowserHTTPFixture: @unchecked Sendable {
    private let consentSuite = "BrowserHTTPFixture.\(UUID())"
    private let requestLock = NSLock()
    private var requests = 0
    var requestCount: Int { requestLock.withLock { requests } }
    private let redirectURL: URL?
    private let listener: NWListener
    private let responseDelay: Double
    private let contentSecurityPolicy: String?
    private let customHTML: String?
    private let responses: [String: (contentType: String, body: Data)]
    private let queue = DispatchQueue(label: "sloppy.browser.fixture")

    init(responseDelay: Double = 0.3, contentSecurityPolicy: String? = nil, html: String? = nil, redirectURL: URL? = nil,
         responses: [String: (contentType: String, body: Data)] = [:]) throws {
        self.responses = responses
        self.redirectURL = redirectURL
        self.responseDelay = responseDelay
        self.contentSecurityPolicy = contentSecurityPolicy
        self.customHTML = html
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> URL {
        let redirectURL = redirectURL
        let responseDelay = responseDelay
        let customHTML = customHTML
        let responses = responses
        let securityHeader = contentSecurityPolicy.map { "Content-Security-Policy: \($0)\r\n" } ?? ""
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
                self?.requestLock.withLock { self?.requests += 1 }
                let path = data.flatMap { String(data: $0, encoding: .utf8)?.split(separator: " ").dropFirst().first.map(String.init) }
                if let path, let route = responses[path] {
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: \(route.contentType)\r\nContent-Length: \(route.body.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(header.utf8) + route.body,
                                    completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
                if let redirectURL {
                    let response = "HTTP/1.1 302 Found\r\nLocation: \(redirectURL.absoluteString)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
                if let data, String(decoding: data, as: UTF8.self).hasPrefix("GET /download ") {
                    let body = "Sloppy download fixture"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=source.txt\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
                // Deliberately slow response catches open() reading the previous document.
                DispatchQueue.global().asyncAfter(deadline: .now() + responseDelay) {
                    let body = customHTML ?? """
                    <!doctype html><html><head><title>Loaded through HTTP</title>
                    <style>body{font:20px system-ui;padding:40px;background:#f5f7fb;color:#172033}button,input{font:inherit;padding:12px}#result{margin-top:24px}</style></head>
                    <body><h1>Sloppy browser smoke test</h1><input id="name" placeholder="Name">
                    <button id="check" onclick="document.getElementById('result').textContent='Verified: '+document.getElementById('name').value">Check</button>
                    <div id="result">Ready</div></body></html>
                    """
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\(securityHeader)Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard let port = listener.port,
              let url = URL(string: "http://127.0.0.1:\(port.rawValue)/") else { throw URLError(.badURL) }
        return url
    }

    @MainActor
    func permissionStore() throws -> BrowserSitePermissions {
        guard let defaults = UserDefaults(suiteName: consentSuite), let port = listener.port,
              let url = URL(string: "http://127.0.0.1:\(port.rawValue)"), let origin = BrowserSiteOrigin(url) else { throw URLError(.badURL) }
        let permissions = BrowserSitePermissions(defaults: defaults)
        permissions.set(.allow, for: origin, resource: .http)
        return permissions
    }
    @MainActor func allowHTTP(in model: WorkspaceWebViewModel) throws { model.sitePermissions = try permissionStore() }
    @MainActor func allowHTTP(in state: BrowserWorkspaceState) throws { state.sitePermissions = try permissionStore() }
    @MainActor func allowHTTP(in runtime: WorkspaceBrowserToolRuntime) throws { runtime.sitePermissions = try permissionStore() }

    deinit {
        listener.cancel()
        UserDefaults(suiteName: consentSuite)?.removePersistentDomain(forName: consentSuite)
    }
}
#endif
