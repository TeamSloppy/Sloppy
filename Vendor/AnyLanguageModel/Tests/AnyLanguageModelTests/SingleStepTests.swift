import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AnyLanguageModel

private final class SingleStepHTTPProtocol: URLProtocol, @unchecked Sendable {
    struct Fixture {
        var bodies: [Data]
        var status: [Int]
        var contentType: String
        var requests: [URLRequest] = []
        var holdOpen: Bool
        var stops = 0
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: Fixture] = [:]

    static func install(bodies: [Data], status: [Int] = [200], contentType: String = "application/json",
                        holdOpen: Bool = false) -> (URL, URLSession) {
        let host = UUID().uuidString.lowercased() + ".invalid"
        lock.withLock { fixtures[host] = .init(bodies: bodies, status: status, contentType: contentType, holdOpen: holdOpen) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return (URL(string: "https://" + host + "/v1")!, URLSession(configuration: configuration))
    }
    static func requests(_ url: URL) -> [URLRequest] { lock.withLock { fixtures[url.host!]!.requests } }
    static func stops(_ url: URL) -> Int { lock.withLock { fixtures[url.host!]!.stops } }
    static func remove(_ url: URL) { _ = lock.withLock { fixtures.removeValue(forKey: url.host!) } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.lock.withLock { () -> (Data, Int, String, Bool) in
            let host = request.url!.host!
            var fixture = Self.fixtures[host]!
            let index = fixture.requests.count
            fixture.requests.append(request)
            Self.fixtures[host] = fixture
            return (fixture.bodies[min(index, fixture.bodies.count - 1)],
                    fixture.status[min(index, fixture.status.count - 1)], fixture.contentType, fixture.holdOpen)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.1,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": reply.2])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.0)
        if !reply.3 { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {
        Self.lock.withLock {
            let host = request.url!.host!
            guard var fixture = Self.fixtures[host] else { return }
            fixture.stops += 1
            Self.fixtures[host] = fixture
        }
    }
}

private final class StepCredentials: @unchecked Sendable {
    private let lock = NSLock()
    private var token = "old-key"
    func current() -> String { lock.withLock { token } }
    func refresh() { lock.withLock { token = "new-key" } }
}

@Suite("AnyLanguageModel single-step API")
struct SingleStepTests {
    private static let toolResponse = #"{"status":"completed","output":[{"type":"reasoning","encrypted_content":"opaque"},{"type":"function_call","call_id":"call-1","name":"inspect","arguments":"{broken"}],"usage":{"input_tokens":12,"output_tokens":3}}"#

    @Test(arguments: [false, true])
    func oneGenerationReturnsRawCallsAndContinuationWithoutFollowingThem(streaming: Bool) async throws {
        let json = Self.toolResponse
        let body = streaming ? "data: {\"type\":\"response.completed\",\"response\":" + json + "}\n\n" : json
        let (url, session) = SingleStepHTTPProtocol.install(bodies: [Data(body.utf8)],
            contentType: streaming ? "text/event-stream" : "application/json")
        defer { session.invalidateAndCancel(); SingleStepHTTPProtocol.remove(url) }
        let provider: any LanguageModelStepProvider = HTTPModelStepProvider(providerID: "account", model: "model",
            baseURL: url, token: { "key" }, session: session)
        var finals: [LanguageModelStepResponse] = []
        var starts = 0
        for try await event in provider.streamStep(.init(messages: [.init(role: .user, text: "Inspect")],
            tools: [.init(name: "inspect", parameters: .object(["type": .string("object")]))])) {
            switch event {
            case .started: starts += 1
            case .final(let response): finals.append(response)
            default: break
            }
        }
        let response = try #require(finals.first)
        #expect(starts == 1)
        #expect(finals.count == 1)
        #expect(SingleStepHTTPProtocol.requests(url).count == 1)
        #expect(response.stopReason == .toolCalls)
        #expect(response.toolCalls == [.init(id: "call-1", name: "inspect", rawArguments: "{broken")])
        #expect(response.usage?.prompt == 12)
        #expect(response.usage?.completion == 3)
        #expect(response.continuation?.content.asArray?.first?.asObject?["encrypted_content"] == .string("opaque"))
    }

    @Test
    func foreignContinuationFailsBeforeNetwork() async throws {
        let (url, session) = SingleStepHTTPProtocol.install(bodies: [Data(Self.toolResponse.utf8)])
        defer { session.invalidateAndCancel(); SingleStepHTTPProtocol.remove(url) }
        let provider = HTTPModelStepProvider(providerID: "account", model: "model", baseURL: url, token: { "key" }, session: session)
        do {
            for try await _ in provider.streamStep(.init(messages: [.init(role: .assistant,
                continuation: .init(providerId: "another-account", modelId: "model", format: "responses-v1", content: .array([])))])) {}
            Issue.record("Foreign continuation was accepted")
        } catch let failure as LanguageModelStepFailure {
            #expect(failure.code == "incompatible_continuation")
        }
        #expect(SingleStepHTTPProtocol.requests(url).isEmpty)
    }

    @Test(arguments: [false, true])
    func authenticationRefreshIsExplicitAndBounded(denyAgain: Bool) async throws {
        let (url, session) = SingleStepHTTPProtocol.install(bodies: [Data(Self.toolResponse.utf8)], status: denyAgain ? [401, 401] : [401, 200])
        defer { session.invalidateAndCancel(); SingleStepHTTPProtocol.remove(url) }
        let credentials = StepCredentials()
        let provider = HTTPModelStepProvider(providerID: "account", model: "model", baseURL: url,
            token: { credentials.current() }, session: session, refreshAuthentication: { credentials.refresh() })
        var starts = 0
        var finals = 0
        do {
            for try await event in provider.streamStep(.init(messages: [.init(role: .user, text: "Hello")])) {
                if case .started = event { starts += 1 }
                if case .final = event { finals += 1 }
            }
            #expect(!denyAgain)
        } catch let failure as LanguageModelStepFailure {
            #expect(denyAgain)
            #expect(failure.category == .authentication)
        }
        #expect(starts == 1)
        #expect(finals == (denyAgain ? 0 : 1))
        #expect(SingleStepHTTPProtocol.requests(url).count == 2)
        #expect(SingleStepHTTPProtocol.requests(url).first?.value(forHTTPHeaderField: "Authorization") == "Bearer old-key")
        #expect(SingleStepHTTPProtocol.requests(url).last?.value(forHTTPHeaderField: "Authorization") == "Bearer new-key")
    }

    @Test
    func cancellationStopsUnderlyingRequest() async throws {
        let (url, session) = SingleStepHTTPProtocol.install(bodies: [Data()], holdOpen: true)
        defer { session.invalidateAndCancel(); SingleStepHTTPProtocol.remove(url) }
        let provider = HTTPModelStepProvider(providerID: "account", model: "model", baseURL: url, token: { "key" }, session: session)
        let task = Task {
            for try await _ in provider.streamStep(.init(messages: [.init(role: .user, text: "Hello")])) {}
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while SingleStepHTTPProtocol.requests(url).isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(SingleStepHTTPProtocol.requests(url).count == 1)
        task.cancel()
        _ = await task.result
        while SingleStepHTTPProtocol.stops(url) == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(SingleStepHTTPProtocol.stops(url) == 1)
    }

    @Test
    func oldSessionRespondAPIStillUsesConfiguredHTTP() async throws {
        let body = #"{"id":"chat-1","object":"chat.completion","created":1,"model":"model","choices":[{"index":0,"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
        let (url, transport) = SingleStepHTTPProtocol.install(bodies: [Data(body.utf8)])
        defer { transport.invalidateAndCancel(); SingleStepHTTPProtocol.remove(url) }
        let model = OpenAILanguageModel(baseURL: url, apiKey: "key", model: "model", session: transport)
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: "Hello")
        #expect(response.content == "Hello")
        #expect(SingleStepHTTPProtocol.requests(url).count == 1)
    }

    @Test
    func oldSessionStreamingAPIStillUsesConfiguredHTTP() async throws {
        let body = "data: {\"id\":\"chat-1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"model\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chat-1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"model\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" +
            "data: [DONE]\n\n"
        let (url, transport) = SingleStepHTTPProtocol.install(bodies: [Data(body.utf8)], contentType: "text/event-stream")
        defer { transport.invalidateAndCancel(); SingleStepHTTPProtocol.remove(url) }
        let model = OpenAILanguageModel(baseURL: url, apiKey: "key", model: "model", session: transport)
        let session = LanguageModelSession(model: model)
        var last = ""
        for try await snapshot in session.streamResponse(to: "Hello") { last = snapshot.content }
        #expect(last == "Hello")
        #expect(SingleStepHTTPProtocol.requests(url).count == 1)
    }
}
