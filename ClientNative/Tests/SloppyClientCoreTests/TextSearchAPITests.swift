import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Text search API", .serialized)
struct TextSearchAPITests {
    @Test func preservesLiteralCodePunctuationAndDocumentIDs() async throws {
        let query = "C++ /tmp/file_name.swift?x=1&y=привет #tag"
        let capture = TextSearchRequestCapture()
        TextSearchURLProtocol.install { request in
            capture.set(request.url)
            let path = request.url?.path ?? ""
            return path.hasSuffix("/document")
                ? #"{"hit":{"id":"one","source":"agent","sessionId":"s","title":"Chat","eventId":"e","before":"100","kind":"message","createdAt":"2026-10-26T10:00:00Z","snippet":"hello"},"text":"hello"}"#
                : #"{"items":[],"hasMore":false,"indexing":false,"indexedSources":4,"failedSources":0,"durationMs":1.2}"#
        }
        defer { TextSearchURLProtocol.install(nil) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TextSearchURLProtocol.self]
        let client = SloppyAPIClient(baseURL: URL(string: "https://search.sloppy.test")!, session: URLSession(configuration: config),
                                    authSessionStore: AuthSessionStore(persistence: .memory))
        let response = try await client.searchText(query, mode: .words, offset: 50)
        #expect(response.indexedSources == 4)
        let url = try #require(capture.url)
        let parameters = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(parameters.first { $0.name == "q" }?.value == query)
        #expect(parameters.first { $0.name == "offset" }?.value == "50")
        #expect(!url.absoluteString.contains("C++"))
        let documentID = "agents/a+b/sessions/x.jsonl#event%?"
        #expect(try await client.fetchSearchDocument(id: documentID).text == "hello")
        let documentURL = try #require(capture.url)
        #expect(URLComponents(url: documentURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == documentID)
    }
}

private final class TextSearchRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: URL?
    var url: URL? { lock.withLock { storage } }
    func set(_ value: URL?) { lock.withLock { storage = value } }
}

private final class TextSearchURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> String)?
    static func install(_ handler: (@Sendable (URLRequest) -> String)?) { lock.withLock { self.handler = handler } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "search.sloppy.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.lock.withLock({ Self.handler }), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(handler(request).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
