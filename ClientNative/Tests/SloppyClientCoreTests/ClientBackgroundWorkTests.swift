import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Background presentation work")
struct ClientBackgroundWorkTests {
    @Test @MainActor func leavesMainActor() async throws {
        let isMainThread = try await ClientBackgroundWork.run { Thread.isMainThread }
        #expect(!isMainThread)
    }

    @Test @MainActor func cancellationPreventsPublishingResult() async {
        let task = Task {
            try await ClientBackgroundWork.run {
                // Enough work to allow cancellation during preparation.
                var value = 0
                for index in 0..<1_000_000 { value &+= index }
                return value
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled preparation returned a result")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct DecodingThreadProbe: Decodable, Sendable {
    let wasOnMainThread: Bool
    init(from decoder: any Decoder) throws {
        wasOnMainThread = Thread.isMainThread
    }
}

private final class BackgroundProbeURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension ClientBackgroundWorkTests {
    @Test @MainActor func apiDecodesOffMainActor() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackgroundProbeURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let http = BackendHTTPClient(baseURL: URL(string: "https://background.test")!, session: session,
                                     authSessionStore: AuthSessionStore(persistence: .memory))
        let probe: DecodingThreadProbe = try await http.get("/probe")
        #expect(!probe.wasOnMainThread)
    }
}
