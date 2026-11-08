import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AgentRuntime
import AnyLanguageModel
@testable import PluginSDK
import Protocols
import Testing
import SloppyRuntime

private typealias JSONValue = Protocols.JSONValue

private final class StepHTTPProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var body: Data
        var contentType = "text/event-stream"
        var holdOpen = false
        var chunkSize = 17
    }
    struct Recorded: Sendable {
        var headers: [String: String]
        var body: Data
        var url: URL?
    }
    struct Fixture {
        var replies: [Reply]
        var requests: [Recorded] = []
        var stops = 0
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: Fixture] = [:]

    static func install(_ replies: [Reply], host: String = "step-" + UUID().uuidString.lowercased() + ".invalid") -> (URL, URLSession) {
        lock.withLock { fixtures[host] = Fixture(replies: replies) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StepHTTPProtocol.self]
        return (URL(string: "https://\(host)/v1")!, URLSession(configuration: configuration))
    }
    static func requests(_ url: URL) -> [Recorded] { lock.withLock { fixtures[url.host ?? ""]?.requests ?? [] } }
    static func remove(_ url: URL) { _ = lock.withLock { fixtures.removeValue(forKey: url.host ?? "") } }
    static func stops(_ url: URL) -> Int { lock.withLock { fixtures[url.host ?? ""]?.stops ?? 0 } }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".invalid") == true || request.url?.host == "api.anthropic.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {
        Self.lock.withLock {
            let host = request.url?.host ?? ""
            if var fixture = Self.fixtures[host] { fixture.stops += 1; Self.fixtures[host] = fixture }
        }
    }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
        }
        let reply = Self.lock.withLock { () -> Reply? in
            let host = request.url?.host ?? ""
            guard var fixture = Self.fixtures[host], !fixture.replies.isEmpty else { return nil }
            fixture.requests.append(.init(headers: request.allHTTPHeaderFields ?? [:], body: body, url: request.url))
            let reply = fixture.replies.removeFirst()
            Self.fixtures[host] = fixture
            return reply
        }
        guard let reply, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil,
                headerFields: ["Content-Type": reply.contentType]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Split in the middle of UTF-8/JSON/SSE records to exercise transport framing.
        for offset in stride(from: 0, to: reply.body.count, by: max(1, reply.chunkSize)) {
            client?.urlProtocol(self, didLoad: reply.body.subdata(in: offset..<offset + min(max(1, reply.chunkSize), reply.body.count - offset)))
        }
        if !reply.holdOpen { client?.urlProtocolDidFinishLoading(self) }
    }
}

private func sse(_ events: [[String: JSONValue]]) throws -> Data {
    var result = Data()
    for event in events {
        result.append(Data("data: ".utf8))
        result.append(try JSONEncoder().encode(JSONValue.object(event)))
        result.append(Data("\n\n".utf8))
    }
    return result
}

private func providerRequest() -> ModelStepRequest {
    .init(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt", model: "test-model",
        projectionRevision: "1", cacheScope: "agent:a:session:s",
        messages: [.init(role: .system, text: "System instructions"), .init(role: .user, text: "Read the file")],
        tools: [.init(name: "files_read", toolId: "files.read", parameters: .object(["type": .string("object")]))])
}

private actor StepUsageRecords {
    var values: [UsageRequestRecord] = []
    func append(_ value: UsageRequestRecord) { values.append(value) }
}

private final class StepCredentials: @unchecked Sendable {
    private let lock = NSLock()
    private var token = "old-token"
    private var forced = 0
    func current() -> String { lock.withLock { token } }
    func refresh() { lock.withLock { token = "new-token"; forced += 1 } }
    var refreshCount: Int { lock.withLock { forced } }
}

@Suite("Single-request provider contracts")
struct ModelStepProviderTests {
    @Test(arguments: [false, true])
    func chatToResponsesFallbackIsAnExplicitLoopAttempt(enabled: Bool) async throws {
        let error = Data(#"{"error":{"code":"unsupported_parameter","param":"model","message":"Use the Responses endpoint for this model."}}"#.utf8)
        let final = Data(#"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done"}]}]}"#.utf8)
        let (url, session) = StepHTTPProtocol.install([
            .init(status: 400, body: error, contentType: "application/json"),
            .init(body: final, contentType: "application/json")
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(url) }
        let factory = OpenAIModelProvider(id: "openai-api", supportedModels: ["openai-api:test-model"],
            settings: .init(apiKey: { "sk-fixture" }, baseURL: url, session: session, allowResponsesAPIFallback: enabled))
        let provider = try #require(try await factory.createModelStepProvider(for: "openai-api:test-model", usageContext: nil))
        let state = RunState()
        let loop = AgentLoop(provider: provider, state: state, retryDelays: [.zero])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("format-fallback-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let stored = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: stored.id, events: [
            .init(agentId: "agent", sessionId: stored.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Read the file")]))
        ])
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: stored.id, authorizeWriter: {})
        var failure: Error?
        var response: ModelStepResponse?
        do {
            response = try await loop.run(providerRequest(), journal: journal,
                executor: .init(execute: { _, _, _, _ in throw CancellationError() }),
                config: .init(engine: .unified, requiresExplicitCompletion: false))
        } catch { failure = error }
        #expect((failure == nil) == enabled)
        let requests = StepHTTPProtocol.requests(url)
        #expect(requests.count == (enabled ? 2 : 1))
        #expect(await state.requestAttempts == (enabled ? 2 : 1))
        #expect(requests.first?.url?.path.hasSuffix("chat/completions") == true)
        if enabled {
            #expect(requests.last?.url?.path.hasSuffix("responses") == true)
            #expect(response?.text == "Done")
            #expect(response?.continuation?.format == "responses-v1")
        }
    }

    @Test
    func observedRuntimeRequestsKeepTheirRunAndTurnAcrossProviderWrappers() async throws {
        let body = try sse([["type": .string("response.completed"), "response": .object([
            "id": .string("fixture-response"), "status": .string("completed"),
            "output": .array([.object(["type": .string("message"), "role": .string("assistant"),
                "content": .array([.object(["type": .string("output_text"), "text": .string("Ready")])])])]),
            "usage": .object(["input_tokens": .number(40), "output_tokens": .number(15)])])]])
        let (url, session) = StepHTTPProtocol.install([.init(body: body), .init(body: body)])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(url) }
        let provider = OpenAIModelProvider(id: "openai-oauth", supportedModels: ["openai-oauth:test-model"],
            settings: .init(apiKey: { "fixture-bearer" }, baseURL: url, session: session,
                modelIdentifierPrefix: "openai-oauth:", useOpenAICodexOAuthPath: true))
        let wrapped: any ModelProvider = ContextLimitedModelProvider(wrapping: CompositeModelProvider(providers: [provider]), limits: [:])
        let runtime = RuntimeSystem(modelProvider: wrapped, defaultModel: "openai-oauth:test-model")
        let usage = StepUsageRecords()
        await runtime.configureUsageAccounting(onRequest: { await usage.append($0) },
            provenance: { _ in .init() }, onToolOutcome: { _, _, _ in })
        for (run, turn) in [("run-one", "turn-one"), ("run-two", "turn-two")] {
            _ = await runtime.postMessage(channelId: "agent:a:session:s", request: .init(userId: "fixture", content: "Answer this independent turn."),
                forceInlineResponse: true, nativeLoopConfig: .init(engine: .unified), runState: RunState(runID: run, userTurnID: turn))
        }
        let records = await usage.values
        #expect(records.count == 2)
        #expect(records.map(\.runId) == ["run-one", "run-two"])
        #expect(records.map(\.userTurnId) == ["turn-one", "turn-two"])
        #expect(records.allSatisfy { $0.channelId == "agent:a:session:s" && $0.usage?.total == 55 })
        #expect(Set(records.map(\.id)).count == 2)
        #expect(StepHTTPProtocol.requests(url).count == 2)
        #expect(await runtime.channelState(channelId: "agent:a:session:s")?.messages.last { $0.userId == "system" }?.content == "Ready")
    }

    @Test(arguments: [false, true])
    func oauthContinuationCannotCrossTheConfiguredEndpoint(changePath: Bool) async throws {
        let response: [String: JSONValue] = ["status": .string("completed"), "output": .array([
            .object(["type": .string("reasoning"), "encrypted_content": .string("endpoint-scoped")]),
            .object(["type": .string("message"), "role": .string("assistant"), "content": .array([
                .object(["type": .string("output_text"), "text": .string("Ready")])])])
        ])]
        let reply = StepHTTPProtocol.Reply(body: try sse([["type": .string("response.completed"), "response": .object(response)]]))
        let (firstURL, firstSession) = StepHTTPProtocol.install([reply, reply])
        let (otherURL, otherSession) = StepHTTPProtocol.install([reply])
        defer {
            firstSession.invalidateAndCancel(); otherSession.invalidateAndCancel()
            StepHTTPProtocol.remove(firstURL); StepHTTPProtocol.remove(otherURL)
        }
        let first = OpenAIOAuthModel(baseURL: firstURL, bearerToken: "fixture", model: "test-model",
            accountId: "same-account", session: firstSession)
        var request = providerRequest()
        let settled = try await AgentLoop(provider: first, state: RunState()).collectStep(request)
        request.messages.append(.init(role: .assistant, text: settled.text, continuation: settled.continuation))
        let target = changePath ? firstURL.appendingPathComponent("another-tenant") : otherURL
        let second = OpenAIOAuthModel(baseURL: target, bearerToken: "fixture", model: "test-model",
            accountId: "same-account", session: changePath ? firstSession : otherSession)
        var continued: ModelStepResponse?
        var failure: ModelStepFailure?
        do { continued = try await AgentLoop(provider: second, state: RunState()).collectStep(request) }
        catch { failure = error as? ModelStepFailure }
        #expect(failure?.code == "incompatible_continuation")
        #expect(continued == nil)
        #expect(StepHTTPProtocol.requests(firstURL).count == 1)
        #expect(StepHTTPProtocol.requests(otherURL).isEmpty)
    }

    @Test(arguments: [false, true], [false, true])
    func geminiUsageAttributesWrappedSchemasAndOnlyRealWireCallIDs(codeAssist: Bool, hasID: Bool) async throws {
        var call: [String: JSONValue] = ["name": .string("files_read"), "args": .object(["path": .string("fixture.txt")])]
        if hasID { call["id"] = .string("usage-call") }
        let first: [String: JSONValue] = ["candidates": .array([.object(["content": .object([
            "role": .string("model"), "parts": .array([.object(["functionCall": .object(call), "thoughtSignature": .string("signature")])])]),
            "finishReason": .string("STOP")])]),
            "usageMetadata": .object(["promptTokenCount": .number(20), "candidatesTokenCount": .number(5)])]
        let second: [String: JSONValue] = ["candidates": .array([.object(["content": .object([
            "role": .string("model"), "parts": .array([.object(["text": .string("Done")])])]), "finishReason": .string("STOP")])]),
            "usageMetadata": .object(["promptTokenCount": .number(25), "candidatesTokenCount": .number(2)])]
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: try sse([codeAssist ? ["response": .object(first)] : first])),
            .init(body: try sse([codeAssist ? ["response": .object(second)] : second]))
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider: any ModelProvider = GeminiModelProvider(supportedModels: ["gemini:test-model"],
            apiKey: { "fixture" }, baseURL: baseURL, session: session, nativeSession: session,
            nativeCodeAssist: codeAssist ? .init(baseURL: baseURL, projectID: { "project" }, headers: [:], userAgent: "fixture") : nil)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let usage = StepUsageRecords()
        var provenance = UsageProvenance()
        provenance.toolNameMap = ["files_read": "files.read"]
        let catalogEntry = "<available_skill>demo</available_skill>"
        provenance.skills = [.init(id: "demo", directory: "/fixture/skills/demo", catalogEntry: catalogEntry)]
        let context = ModelUsageContext(channelId: "agent:a:session:s", provider: "gemini", model: "test-model", provenance: provenance,
            onRequest: { await usage.append($0) })
        let adapter = try #require(try await factory.createModelStepProvider(for: "gemini:test-model", usageContext: context))
        var request = providerRequest()
        request.messages[0].text += "\n" + catalogEntry
        let loop = AgentLoop(provider: adapter, state: RunState())
        let response = try await loop.collectStep(request)
        let canonicalCall = try #require(response.toolCalls.first)
        request.messages += [.init(role: .assistant, toolCalls: response.toolCalls, continuation: response.continuation),
            .init(role: .tool, toolOutput: .init(callId: canonicalCall.id, name: canonicalCall.name,
                content: #"{"ok":true,"data":"full result"}"#, isError: false))]
        #expect(try await loop.collectStep(request).text == "Done")
        let records = await usage.values
        #expect(records.count == 2)
        let firstUsage = try #require(records.first)
        let secondUsage = try #require(records.last)
        #expect(firstUsage.usage?.total == 25)
        #expect(secondUsage.usage?.total == 27)
        for record in records {
            #expect(record.components.contains { $0.kind == .toolSchema && $0.tool == "files.read" && ($0.tokens ?? 0) > 0 })
            #expect(record.components.contains { $0.kind == .skillCatalog && $0.skillId == "demo" && ($0.tokens ?? 0) > 0 })
            #expect(record.complete == hasID)
        }
        if hasID {
            #expect(firstUsage.calls.contains { $0.id == "usage-call" && $0.tool == "files.read" && $0.generated })
            #expect(firstUsage.components.contains { $0.kind == .argumentsOutput && $0.toolCallId == "usage-call" && ($0.tokens ?? 0) > 0 })
            #expect(secondUsage.components.contains { $0.kind == .argumentsInput && $0.toolCallId == "usage-call" && ($0.tokens ?? 0) > 0 })
            #expect(secondUsage.components.contains { $0.kind == .resultInput && $0.toolCallId == "usage-call" && ($0.tokens ?? 0) > 0 })
            #expect(secondUsage.calls.contains { $0.id == "usage-call" && !$0.generated && $0.ok == true })
        } else {
            #expect(firstUsage.calls.isEmpty)
            #expect(secondUsage.calls.isEmpty)
            #expect(!records.flatMap(\.components).contains { $0.kind == .argumentsOutput || $0.kind == .argumentsInput || $0.kind == .resultInput })
        }
        let wire = try #require(StepHTTPProtocol.requests(baseURL).last)
        let root = try #require(try JSONDecoder().decode(JSONValue.self, from: wire.body).asObject)
        let payload = codeAssist ? try #require(root["request"]?.asObject) : root
        let result = payload["contents"]?.asArray?.last?.asObject?["parts"]?.asArray?.first?.asObject?["functionResponse"]?.asObject
        #expect(result?["id"] == (hasID ? .string("usage-call") : nil))
    }


    private final class CodeAssistProject: @unchecked Sendable {
        private let lock = NSLock()
        private var project = "project-one"
        func current() -> String? { lock.withLock { project } }
        func replace(_ value: String) { lock.withLock { project = value } }
    }

    @Test(arguments: [false, true], [false, true])
    func codeAssistBindsProjectBeforeSendingSignedContinuation(changeProject: Bool, json: Bool) async throws {
        let signed: JSONValue = .object(["role": .string("model"), "parts": .array([
            .object(["text": .string("Hello"), "thoughtSignature": .string("project-one-signature")])])])
        let first: [String: JSONValue] = ["response": .object(["candidates": .array([.object([
            "content": signed, "finishReason": .string("STOP")])]),
            "usageMetadata": .object(["promptTokenCount": .number(20), "candidatesTokenCount": .number(5)])])]
        let second: [String: JSONValue] = ["response": .object(["candidates": .array([.object([
            "content": .object(["role": .string("model"), "parts": .array([.object(["text": .string("Done")])])]),
            "finishReason": .string("STOP")])])])]
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: json ? try JSONEncoder().encode(JSONValue.object(first)) : try sse([first]),
                contentType: json ? "application/json" : "text/event-stream"), .init(body: try sse([second]))])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let project = CodeAssistProject()
        let credentials = StepCredentials()
        let provider: any ModelProvider = GeminiModelProvider(supportedModels: ["gemini:test-model"],
            apiKey: { credentials.current() }, refreshTokenIfNeeded: { throw URLError(.unsupportedURL) }, baseURL: baseURL,
            session: session, nativeSession: session,
            nativeCodeAssist: .init(baseURL: baseURL, projectID: { project.current() },
                headers: ["X-Goog-Api-Client": "fixture-client", "Client-Metadata": "fixture-metadata"], userAgent: "fixture-agent",
                refreshCredentials: { credentials.refresh() }))
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let usage = StepUsageRecords()
        let context = ModelUsageContext(channelId: "agent:a:session:s", provider: "gemini", model: "test-model",
            onRequest: { await usage.append($0) })
        let adapter = try #require(try await factory.createModelStepProvider(for: "gemini:test-model", usageContext: context))
        var request = providerRequest()
        let loop = AgentLoop(provider: adapter, state: RunState())
        var firstResponse: ModelStepResponse?
        var firstFailure: Error?
        do { firstResponse = try await loop.collectStep(request) }
        catch { firstFailure = error }
        #expect(firstFailure == nil)
        let response = try #require(firstResponse)
        #expect(response.text == "Hello")
        #expect(response.usage?.total == 25)
        request.messages.append(.init(role: .assistant, text: response.text, continuation: response.continuation))
        if changeProject { project.replace("project-two") }
        do {
            #expect(try await loop.collectStep(request).text == "Done")
            #expect(!changeProject)
        } catch {
            #expect(changeProject)
            #expect((error as? ModelStepFailure)?.code == "incompatible_continuation")
        }
        let records = StepHTTPProtocol.requests(baseURL)
        #expect(records.count == (changeProject ? 1 : 2))
        #expect(credentials.refreshCount == 2)
        #expect(await usage.values.count == (changeProject ? 1 : 2))
        let record = try #require(records.last)
        #expect(record.url?.path == "/v1/v1internal:streamGenerateContent")
        #expect(record.url?.query == "alt=sse")
        #expect(record.headers.first { $0.key.lowercased() == "authorization" }?.value == "Bearer new-token")
        #expect(record.headers.first { $0.key.lowercased() == "x-goog-api-key" } == nil)
        #expect(record.headers.first { $0.key.lowercased() == "x-goog-api-client" }?.value == "fixture-client")
        #expect(record.headers.first { $0.key.lowercased() == "client-metadata" }?.value == "fixture-metadata")
        let body = try #require(try JSONDecoder().decode(JSONValue.self, from: record.body).asObject)
        #expect(body["project"] == .string("project-one"))
        #expect(body["model"] == .string("test-model"))
        #expect(body["requestType"] == .string("agent"))
        #expect(body["userAgent"] == .string("fixture-agent"))
        #expect(body["requestId"] == .string(request.attemptId))
        let inner = try #require(body["request"]?.asObject)
        #expect(inner["generationConfig"]?.asObject?["maxOutputTokens"] == .number(1024))
        if !changeProject { #expect(inner["contents"]?.asArray?.last == signed) }
    }

    @Test(arguments: [false, true])
    func geminiRejectsUnsupportedEffortOrForeignContinuationBeforeHTTP(foreign: Bool) async throws {
        let (baseURL, session) = StepHTTPProtocol.install([])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider: any ModelProvider = GeminiModelProvider(supportedModels: ["gemini:test-model"],
            apiKey: { "fixture" }, baseURL: baseURL, session: session)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "gemini:test-model", usageContext: nil))
        var request = providerRequest()
        if foreign {
            request.messages.append(.init(role: .assistant, continuation: .init(providerId: "another-provider",
                modelId: "test-model", format: "gemini-content-v1", content: .object([
                    "role": .string("model"), "parts": .array([.object(["text": .string(""), "thoughtSignature": .string("foreign")])])]))))
        } else { request.reasoningEffort = .max }
        var failure: ModelStepFailure?
        do { _ = try await AgentLoop(provider: adapter, state: RunState()).collectStep(request) }
        catch { failure = error as? ModelStepFailure }
        #expect(failure?.code == (foreign ? "incompatible_continuation" : "unsupported_reasoning_effort"))
        #expect(StepHTTPProtocol.requests(baseURL).isEmpty)
    }


    @Test(arguments: [false, true])
    func geminiStepPreservesOrderedSignedPartsAndFunctionResults(json: Bool) async throws {
        let parts: [JSONValue] = [
            .object(["text": .string("Need the file"), "thought": .bool(true), "thoughtSignature": .string("signed-thought")]),
            .object(["functionCall": .object(["id": .string("gem-call"), "name": .string("files_read"),
                "args": .object(["path": .string("fixture.txt")])]), "thoughtSignature": .string("signed-call")]),
            .object(["text": .string(""), "thoughtSignature": .string("signed-empty")])
        ]
        let first: [String: JSONValue] = ["candidates": .array([.object(["index": .number(0),
            "content": .object(["role": .string("model"), "parts": .array(parts)]), "finishReason": .string("STOP")])]),
            "usageMetadata": .object(["promptTokenCount": .number(30), "candidatesTokenCount": .number(4),
                "thoughtsTokenCount": .number(6), "cachedContentTokenCount": .number(11), "totalTokenCount": .number(40)])]
        let second: [String: JSONValue] = ["candidates": .array([.object(["index": .number(0),
            "content": .object(["role": .string("model"), "parts": .array([.object(["text": .string("Done")])])]),
            "finishReason": .string("STOP")])])]
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: json ? try JSONEncoder().encode(JSONValue.object(first)) : try sse([first]),
                contentType: json ? "application/json" : "text/event-stream"),
            .init(body: try sse([second]))
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider: any ModelProvider = GeminiModelProvider(supportedModels: ["gemini:test-model"],
            apiKey: { "gem-key" }, baseURL: baseURL, session: session)
        let factory = provider as? any ModelStepProviderFactory
        #expect(factory?.supportsModelSteps(for: "gemini:test-model") == true)
        guard let factory else { return }
        let usage = StepUsageRecords()
        let context = ModelUsageContext(channelId: "agent:a:session:s", provider: "gemini", model: "test-model",
            onRequest: { await usage.append($0) })
        let adapter = try #require(try await factory.createModelStepProvider(for: "gemini:test-model", usageContext: context))
        var request = providerRequest()
        request.model = "gemini:test-model"
        request.reasoningEffort = .medium
        request.messages[1].images = [.init(mimeType: "image/png", data: Data([1, 2, 3]))]
        let loop = AgentLoop(provider: adapter, state: RunState())
        let response = try await loop.collectStep(request)
        #expect(response.text.isEmpty)
        #expect(response.stopReason == .toolCalls)
        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls.first?.id == "gem-call")
        #expect(response.toolCalls.first?.rawArguments == "{\"path\":\"fixture.txt\"}")
        #expect(response.continuation?.content.asObject?["parts"] == .array(parts))
        #expect(response.usage?.total == 40)
        #expect(response.usage?.reasoning == 6)
        #expect(response.usage?.cachedInput == 11)
        request.messages += [
            .init(role: .assistant, toolCalls: response.toolCalls, continuation: response.continuation),
            .init(role: .tool, toolOutput: .init(callId: "gem-call", name: "files_read", content: "Full result", isError: false))
        ]
        #expect(try await loop.collectStep(request).text == "Done")
        let records = StepHTTPProtocol.requests(baseURL)
        #expect(records.count == 2)
        let wire = try #require(records.last)
        #expect(wire.url?.path == "/v1/v1beta/models/test-model:streamGenerateContent")
        #expect(wire.url?.query == "alt=sse")
        #expect(wire.headers.first { $0.key.lowercased() == "x-goog-api-key" }?.value == "gem-key")
        #expect(wire.headers.first { $0.key.lowercased() == "authorization" } == nil)
        let body = try #require(try JSONDecoder().decode(JSONValue.self, from: wire.body).asObject)
        let contents = try #require(body["contents"]?.asArray)
        #expect(contents[1].asObject?["parts"] == .array(parts))
        #expect(contents[2].asObject?["parts"]?.asArray?.first?.asObject?["functionResponse"]?.asObject?["id"] == .string("gem-call"))
        #expect(contents[0].asObject?["parts"]?.asArray?.last?.asObject?["inlineData"]?.asObject?["data"] == .string("AQID"))
        #expect(body["generationConfig"]?.asObject?["maxOutputTokens"] == .number(1024))
        #expect(body["generationConfig"]?.asObject?["thinkingConfig"]?.asObject?["thinkingLevel"] == .string("MEDIUM"))
        #expect(body["tools"]?.asArray?.first?.asObject?["functionDeclarations"]?.asArray?.first?.asObject?["parametersJsonSchema"] == request.tools[0].parameters)
        #expect(await usage.values.count == 2)
    }

    @Test(arguments: [false, true])
    func geminiPartialAndLengthLimitedCallsNeverBecomeExecutable(length: Bool) async throws {
        var candidate: [String: JSONValue] = ["index": .number(0), "content": .object([
            "role": .string("model"), "parts": .array([.object(["functionCall": .object([
                "name": .string("files_read"), "args": .object(["path": .string("fixture.txt")])])])])])]
        if length { candidate["finishReason"] = .string("MAX_TOKENS") }
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: try sse([["candidates": .array([.object(candidate)])]]))])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider: any ModelProvider = GeminiModelProvider(supportedModels: ["gemini:test-model"],
            apiKey: { "gem-key" }, baseURL: baseURL, session: session)
        let factory = provider as? any ModelStepProviderFactory
        #expect(factory != nil)
        guard let factory else { return }
        let adapter = try #require(try await factory.createModelStepProvider(for: "gemini:test-model", usageContext: nil))
        do {
            let response = try await AgentLoop(provider: adapter, state: RunState()).collectStep(providerRequest())
            #expect(length)
            #expect(response.stopReason == .outputLimit)
            #expect(response.toolCalls.count == 1)
            #expect(response.toolCalls.first?.id == "gemini-step-0")
        } catch {
            #expect(!length)
            #expect((error as? ModelStepFailure)?.code == "stream_ended_before_final")
        }
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
    }

    @Test
    func geminiCancellationStopsTheActiveGeneration() async throws {
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: Data(), holdOpen: true)])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider: any ModelProvider = GeminiModelProvider(supportedModels: ["gemini:test-model"],
            apiKey: { "gem-key" }, baseURL: baseURL, session: session)
        let factory = provider as? any ModelStepProviderFactory
        #expect(factory != nil)
        guard let factory else { return }
        let adapter = try #require(try await factory.createModelStepProvider(for: "gemini:test-model", usageContext: nil))
        let state = RunState()
        let pending = Task { try await AgentLoop(provider: adapter, state: state).collectStep(providerRequest()) }
        for _ in 0..<600 {
            if !StepHTTPProtocol.requests(baseURL).isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await state.cancel()
        do { _ = try await pending.value; Issue.record("Cancelled request unexpectedly completed") }
        catch { #expect((error as? ModelStepFailure)?.category == .cancelled) }
        for _ in 0..<600 {
            if StepHTTPProtocol.stops(baseURL) > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(StepHTTPProtocol.stops(baseURL) > 0)
    }


    @Test(arguments: [false, true])
    func burstEventsWaitForTheConsumerWithoutLosingTheFinal(oauth: Bool) async throws {
        let answer = String(repeating: "x", count: 800)
        var events: [[String: JSONValue]] = (0..<800).map { _ in
            ["type": .string("response.output_text.delta"), "delta": .string("x")]
        }
        events.append(["type": .string("response.completed"), "response": .object([
            "status": .string("completed"), "output": .array([.object([
                "type": .string("message"), "role": .string("assistant"), "content": .array([
                    .object(["type": .string("output_text"), "text": .string(answer)])])])])])])
        let body = try sse(events)
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: body, chunkSize: body.count)])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let adapter: any ModelStepProvider
        if oauth {
            adapter = OpenAIOAuthModel(baseURL: baseURL, bearerToken: "fixture", model: "test-model", session: session)
        } else {
            adapter = NativeHTTPModelStepProvider(providerID: "fixture", model: "test-model", baseURL: baseURL,
                token: { "fixture" }, refresh: nil, session: session, instructions: "")
        }
        var previewCount = 0
        var final: ModelStepResponse?
        var caught: Error?
        do {
            for try await event in adapter.streamStep(providerRequest()) {
                switch event {
                case .textDelta:
                    previewCount += 1
                    if previewCount == 1 { try await Task.sleep(for: .milliseconds(25)) }
                    else if previewCount.isMultiple(of: 64) { try await Task.sleep(for: .milliseconds(2)) }
                case .final(let response): final = response
                default: break
                }
            }
        } catch { caught = error }
        #expect(caught == nil)
        #expect(previewCount == 800)
        #expect(final?.text == answer)
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
    }

    @Test
    func jsonAndStreamingResponsesHaveEquivalentFinalValues() async throws {
        let response: [String: JSONValue] = ["status": .string("completed"), "output": .array([
            .object(["type": .string("message"), "role": .string("assistant"), "content": .array([
                .object(["type": .string("output_text"), "text": .string("Same answer")])])])
        ]), "usage": .object(["input_tokens": .number(12), "output_tokens": .number(4)])]
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: try sse([["type": .string("response.completed"), "response": .object(response)]])),
            .init(body: try JSONEncoder().encode(JSONValue.object(response)), contentType: "application/json")
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let legacy: any LanguageModel = OpenAIOAuthModel(baseURL: baseURL, bearerToken: "fixture", model: "test-model", session: session)
        let adapter = try #require(legacy as? any ModelStepProvider)
        let loop = AgentLoop(provider: adapter, state: RunState())
        let streaming = try await loop.collectStep(providerRequest())
        var json: ModelStepResponse?
        do { json = try await loop.collectStep(providerRequest()) } catch { /* JSON parity is the next missing behavior. */ }
        #expect(json == streaming)
        #expect(StepHTTPProtocol.requests(baseURL).count == 2)
    }

    @Test(arguments: [false, true])
    func oauthRefreshesOnceAfter401AndNeverLoopsAuthentication(denyAgain: Bool) async throws {
        let denied = StepHTTPProtocol.Reply(status: 401, body: Data("{\"error\":{\"code\":\"invalid_token\",\"message\":\"Expired\"}}".utf8))
        let accepted = StepHTTPProtocol.Reply(body: try sse([["type": .string("response.completed"),
            "response": .object(["status": .string("completed"), "output": .array([])])]]))
        let (baseURL, session) = StepHTTPProtocol.install([denied, denyAgain ? denied : accepted])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let credentials = StepCredentials()
        let legacy: any LanguageModel = OpenAIOAuthModel(baseURL: baseURL, bearerTokenProvider: { credentials.current() },
            bearerTokenForceRefresh: { credentials.refresh() }, model: "test-model", session: session)
        let adapter = try #require(legacy as? any ModelStepProvider)
        var failure: ModelStepFailure?
        do { _ = try await AgentLoop(provider: adapter, state: RunState()).collectStep(providerRequest()) }
        catch { failure = error as? ModelStepFailure }
        #expect((failure != nil) == denyAgain)
        if denyAgain { #expect(failure?.category == .authentication) }
        #expect(credentials.refreshCount == 1)
        let records = StepHTTPProtocol.requests(baseURL)
        #expect(records.count == 2)
        #expect(records.first?.headers.first(where: { $0.key.lowercased() == "authorization" })?.value == "Bearer old-token")
        #expect(records.last?.headers.first(where: { $0.key.lowercased() == "authorization" })?.value == "Bearer new-token")
        #expect(records.first?.body == records.last?.body)
    }

    @Test(arguments: [false, true])
    func runCancellationReachesTheActiveURLSessionTask(apiKey: Bool) async throws {
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: Data(), holdOpen: true)])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let adapter: any ModelStepProvider
        if apiKey {
            let provider = OpenAIModelProvider(supportedModels: ["openai-api:test-model"],
                settings: .init(apiKey: { "sk-fixture" }, baseURL: baseURL, session: session))
            adapter = try #require(try await provider.createModelStepProvider(for: "openai-api:test-model", usageContext: nil))
        } else {
            let legacy: any LanguageModel = OpenAIOAuthModel(baseURL: baseURL, bearerToken: "fixture", model: "test-model", session: session)
            adapter = try #require(legacy as? any ModelStepProvider)
        }
        let state = RunState()
        let pending = Task { try await AgentLoop(provider: adapter, state: state).collectStep(providerRequest()) }
        for _ in 0..<200 where StepHTTPProtocol.requests(baseURL).isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
        await state.cancel()
        var cancelled = false
        do { _ = try await pending.value }
        catch { cancelled = error is CancellationError || (error as? ModelStepFailure)?.category == .cancelled }
        #expect(cancelled)
        for _ in 0..<200 where StepHTTPProtocol.stops(baseURL) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(StepHTTPProtocol.stops(baseURL) > 0)
    }

    @Test
    func oauthStepPreservesRawArgumentsOpaqueItemsAndUsageWithoutFollowingCalls() async throws {
        let output: [JSONValue] = [
            .object(["id": .string("reasoning"), "type": .string("reasoning"), "encrypted_content": .string("signed-opaque"), "summary": .array([])]),
            .object(["id": .string("message"), "type": .string("message"), "role": .string("assistant"), "phase": .string("commentary"),
                "content": .array([.object(["type": .string("output_text"), "text": .string("Прочитаю.")])])]),
            .object(["id": .string("function"), "type": .string("function_call"), "call_id": .string("provider-call"),
                "name": .string("files_read"), "arguments": .string("{\"path\":")])
        ]
        let first = try sse([["type": .string("response.completed"), "response": .object([
            "status": .string("completed"), "output": .array(output), "usage": .object([
                "input_tokens": .number(40), "output_tokens": .number(15),
                "input_tokens_details": .object(["cached_tokens": .number(30)]),
                "output_tokens_details": .object(["reasoning_tokens": .number(5)])
            ])])]])
        let second = try sse([["type": .string("response.completed"), "response": .object([
            "status": .string("completed"), "output": .array([.object(["type": .string("message"), "role": .string("assistant"),
                "content": .array([.object(["type": .string("output_text"), "text": .string("Done")])])])])])]])
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: first), .init(body: second)])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let legacy: any LanguageModel = OpenAIOAuthModel(baseURL: baseURL, bearerToken: "fixture", model: "test-model", accountId: "account", session: session)
        let adapter = legacy as? any ModelStepProvider
        #expect(adapter != nil)
        guard let adapter else { return }
        let loop = AgentLoop(provider: adapter, state: RunState())
        var request = providerRequest()
        let response = try await loop.collectStep(request)
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
        #expect(response.text == "Прочитаю.")
        #expect(response.stopReason == .toolCalls)
        #expect(response.toolCalls.first?.rawArguments == "{\"path\":")
        #expect(response.continuation?.content == .array(output))
        #expect(response.usage == TokenUsage(prompt: 40, completion: 15, cachedInputTokens: 30, reasoningTokens: 5))
        request.messages.append(.init(role: .assistant, text: response.text, toolCalls: response.toolCalls, continuation: response.continuation))
        request.messages.append(.init(role: .tool, toolOutput: .init(callId: "provider-call", name: "files_read", content: "invalid_tool_arguments")))
        _ = try await loop.collectStep(request)
        let records = StepHTTPProtocol.requests(baseURL)
        #expect(records.count == 2)
        let body = try JSONDecoder().decode(JSONValue.self, from: records[1].body).asObject
        let input = try #require(body?["input"]?.asArray)
        #expect(input.dropFirst().prefix(output.count).map { $0 } == output)
        #expect(body?["store"] == .bool(false))
        #expect(body?["include"]?.asArray?.contains(.string("reasoning.encrypted_content")) == true)
        #expect(records[0].headers.first(where: { $0.key.lowercased() == "chatgpt-account-id" })?.value == "account")
        let firstBody = try JSONDecoder().decode(JSONValue.self, from: records[0].body).asObject
        #expect(firstBody?["prompt_cache_key"] == body?["prompt_cache_key"])
    }

    @Test(arguments: [false, true])
    func oauthRequiresATerminalResponseAndRetainsIncompleteCalls(incomplete: Bool) async throws {
        var events: [[String: JSONValue]] = [["type": .string("response.output_text.delta"), "delta": .string("Partial")]]
        if incomplete {
            events.append(["type": .string("response.incomplete"), "response": .object([
                "status": .string("incomplete"), "incomplete_details": .object(["reason": .string("max_output_tokens")]),
                "output": .array([.object(["type": .string("function_call"), "call_id": .string("call"),
                    "name": .string("files_read"), "arguments": .string("{\"path\":\"x\"}")])])])])
        }
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: try sse(events))])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let legacy: any LanguageModel = OpenAIOAuthModel(baseURL: baseURL, bearerToken: "fixture", model: "test-model", session: session)
        let adapter = legacy as? any ModelStepProvider
        #expect(adapter != nil)
        guard let adapter else { return }
        do {
            let response = try await AgentLoop(provider: adapter, state: RunState()).collectStep(providerRequest())
            #expect(incomplete)
            #expect(response.stopReason == .outputLimit)
            #expect(response.toolCalls.count == 1)
        } catch {
            #expect(!incomplete)
            #expect((error as? ModelStepFailure)?.code == "stream_ended_before_final")
        }
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
    }

    @Test
    func factoryCapabilitySurvivesWrappersAndRecordsUsageOnce() async throws {
        let data = try sse([["type": .string("response.completed"), "response": .object([
            "id": .string("fixture-response"), "status": .string("completed"), "output": .array([]),
            "usage": .object(["input_tokens": .number(40), "output_tokens": .number(15)])])]])
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: data)])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = OpenAIModelProvider(id: "openai-oauth", supportedModels: ["openai-oauth:test-model"],
            settings: .init(apiKey: { "fixture-bearer" }, baseURL: baseURL, session: session,
                modelIdentifierPrefix: "openai-oauth:", useOpenAICodexOAuthPath: true))
        let wrapped: any ModelProvider = ContextLimitedModelProvider(wrapping: CompositeModelProvider(providers: [provider]), limits: [:])
        let factory = wrapped as? any ModelStepProviderFactory
        #expect(factory?.supportsModelSteps(for: "openai-oauth:test-model") == true)
        guard let factory else { return }
        let usage = StepUsageRecords()
        let context = ModelUsageContext(channelId: "agent:a:session:s", provider: "openai-oauth", model: "test-model",
            onRequest: { await usage.append($0) })
        let adapter = try #require(try await factory.createModelStepProvider(for: "openai-oauth:test-model", usageContext: context))
        var request = providerRequest()
        request.model = "openai-oauth:test-model"
        let response = try await AgentLoop(provider: adapter, state: RunState()).collectStep(request)
        #expect(response.usage?.total == 55)
        #expect(await usage.values.count == 1)
        #expect(await usage.values.first?.usage?.total == 55)
        #expect(await usage.values.first?.channelId == "agent:a:session:s")
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
    }
    @Test(arguments: [false, true], [false, true])
    func responsesAPIKeyStepPreservesProviderItemsAndDoesNotScheduleTools(json: Bool, responsesFlag: Bool) async throws {
        let items: [JSONValue] = [
            .object(["type": .string("reasoning"), "encrypted_content": .string("opaque-proof"), "summary": .array([])]),
            .object(["type": .string("function_call"), "call_id": .string("api-call"), "name": .string("files_read"),
                "arguments": .string("{\"path\":\"fixture.txt\"}")])
        ]
        let terminal: [String: JSONValue] = ["id": .string("api-response"), "status": .string("completed"),
            "output": .array(items), "usage": .object(["input_tokens": .number(17), "output_tokens": .number(6)])]
        let first = json ? try JSONEncoder().encode(JSONValue.object(terminal)) : try sse([
            ["type": .string("response.completed"), "response": .object(terminal)]])
        let final = try JSONEncoder().encode(JSONValue.object(["status": .string("completed"), "output": .array([])]))
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: first, contentType: json ? "application/json" : "text/event-stream"),
            .init(body: final, contentType: "application/json")
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = OpenAIModelProvider(id: "compatible", supportedModels: ["compatible:test-model"],
            settings: .init(apiKey: { "sk-fixture" }, baseURL: baseURL,
                apiVariant: responsesFlag ? .chatCompletions : .responses, session: session,
                modelIdentifierPrefix: "compatible:", allowResponsesAPIFallback: false,
                useOpenResponsesLanguageModel: responsesFlag))
        #expect(provider.supportsModelSteps(for: "compatible:test-model"))
        let usage = StepUsageRecords()
        let context = ModelUsageContext(channelId: "agent:a:session:s", provider: "compatible", model: "test-model",
            onRequest: { await usage.append($0) })
        let adapter = try #require(try await provider.createModelStepProvider(for: "compatible:test-model", usageContext: context))
        var request = providerRequest()
        request.model = "compatible:test-model"
        request.maximumOutputTokens = 2048
        let loop = AgentLoop(provider: adapter, state: RunState())
        let response = try await loop.collectStep(request)
        #expect(response.toolCalls.count == 1)
        #expect(response.stopReason == .toolCalls)
        #expect(response.continuation?.content == .array(items))
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
        request.messages.append(.init(role: .assistant, toolCalls: response.toolCalls, continuation: response.continuation))
        request.messages.append(.init(role: .tool, toolOutput: .init(callId: "api-call", name: "files_read", content: "the full file")))
        _ = try await loop.collectStep(request)
        let records = StepHTTPProtocol.requests(baseURL)
        #expect(records.count == 2)
        let body = try JSONDecoder().decode(JSONValue.self, from: records[1].body).asObject
        #expect(body?["max_output_tokens"] == .number(2048))
        #expect(records.allSatisfy { $0.url?.path == "/v1/responses" })
        #expect(body?["model"] == .string("test-model"))
        #expect(body?["input"]?.asArray?.dropFirst().prefix(items.count).map { $0 } == items)
        #expect(records[0].headers.first(where: { $0.key.lowercased() == "authorization" })?.value == "Bearer sk-fixture")
        #expect(records[0].headers.first(where: { $0.key.lowercased() == "chatgpt-account-id" }) == nil)
        #expect(await usage.values.count == 2)
        #expect(await usage.values.first?.usage?.total == 23)
    }

    @Test(arguments: [false, true])
    func chatStepKeepsOrderedCallsImagesContinuationAndUsage(json: Bool) async throws {
        let calls: [JSONValue] = [
            .object(["id": .string("first"), "type": .string("function"), "function": .object([
                "name": .string("files_read"), "arguments": .string("{\"path\":\"a\"}")])]),
            .object(["id": .string("second"), "type": .string("function"), "function": .object([
                "name": .string("files_read"), "arguments": .string("{")])])
        ]
        let message: JSONValue = .object(["role": .string("assistant"), "content": .string("Inspect"),
            "reasoning_content": .string("opaque reasoning"), "tool_calls": .array(calls)])
        let usage: JSONValue = .object(["prompt_tokens": .number(21), "completion_tokens": .number(7),
            "prompt_tokens_details": .object(["cached_tokens": .number(11)]),
            "completion_tokens_details": .object(["reasoning_tokens": .number(3)])])
        let terminal: [String: JSONValue] = ["choices": .array([.object(["index": .number(0),
            "message": message, "finish_reason": .string("tool_calls")])]), "usage": usage]
        func chunk(_ delta: [String: JSONValue], finish: JSONValue = .null) -> [String: JSONValue] {
            ["choices": .array([.object(["index": .number(0), "delta": .object(delta), "finish_reason": finish])])]
        }
        var stream = try sse([
            chunk(["role": .string("assistant"), "content": .string("In"), "reasoning_content": .string("opaque ")]),
            chunk(["content": .string("spect"), "reasoning_content": .string("reasoning"), "tool_calls": .array([
                .object(["index": .number(1), "id": .string("second"), "type": .string("function"),
                    "function": .object(["name": .string("files_read"), "arguments": .string("{")])]),
                .object(["index": .number(0), "id": .string("first"), "type": .string("function"),
                    "function": .object(["name": .string("files_"), "arguments": .string("{\"path\":")])])])]),
            chunk(["tool_calls": .array([.object(["index": .number(0), "function": .object([
                "name": .string("read"), "arguments": .string("\"a\"}")])])])], finish: .string("tool_calls")),
            ["choices": .array([]), "usage": usage]
        ])
        stream.append(Data("data: [DONE]\n\n".utf8))
        let final = try JSONEncoder().encode(JSONValue.object(["choices": .array([.object([
            "index": .number(0), "message": .object(["role": .string("assistant"), "content": .string("Done")]),
            "finish_reason": .string("stop")])])]))
        let first = json ? try JSONEncoder().encode(JSONValue.object(terminal)) : stream
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: first, contentType: json ? "application/json" : "text/event-stream"),
            .init(body: final, contentType: "application/json")
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = OpenAIModelProvider(supportedModels: ["openai-api:test-model"],
            settings: .init(apiKey: { "sk-fixture" }, baseURL: baseURL, session: session, allowResponsesAPIFallback: true))
        let records = StepUsageRecords()
        let context = ModelUsageContext(channelId: "chat-fixture", provider: "openai-api", model: "test-model", onRequest: { await records.append($0) })
        let adapter = try #require(try await provider.createModelStepProvider(for: "openai-api:test-model", usageContext: context))
        let loop = AgentLoop(provider: adapter, state: RunState())
        var request = providerRequest()
        request.model = "openai-api:test-model"
        request.maximumOutputTokens = 2048
        request.messages[1].images = [.init(mimeType: "image/png", data: Data([1, 2]))]
        let response = try await loop.collectStep(request)
        #expect(response.text == "Inspect")
        #expect(response.toolCalls.map(\.id) == ["first", "second"])
        #expect(response.toolCalls.map(\.rawArguments) == ["{\"path\":\"a\"}", "{"])
        #expect(response.continuation?.content == message)
        #expect(response.usage == .init(prompt: 21, completion: 7, cachedInputTokens: 11, reasoningTokens: 3))
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
        request.messages.append(.init(role: .assistant, text: response.text, toolCalls: response.toolCalls, continuation: response.continuation))
        request.messages.append(.init(role: .tool, toolOutput: .init(callId: "first", name: "files_read", content: "full file")))
        request.messages.append(.init(role: .tool, toolOutput: .init(callId: "second", name: "files_read", content: "invalid_tool_arguments")))
        #expect(try await loop.collectStep(request).text == "Done")
        let requests = StepHTTPProtocol.requests(baseURL)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path == "/v1/chat/completions" })
        let body = try JSONDecoder().decode(JSONValue.self, from: requests[1].body).asObject
        #expect(body?["max_completion_tokens"] == .number(2048))
        #expect(body?["stream_options"]?.asObject?["include_usage"] == .bool(true))
        #expect(body?["messages"]?.asArray?[2] == message)
        #expect(body?["messages"]?.asArray?[1].asObject?["content"]?.asArray?.last?.asObject?["image_url"]?.asObject?["url"] == .string("data:image/png;base64,AQI="))
        #expect(await records.values.count == 2)
        #expect(await records.values.first?.usage?.total == 28)
    }

    @Test(arguments: [0, 1, 2])
    func chatPartialCallsCannotBecomeExecutable(terminal: Int) async throws {
        var stream = try sse([["choices": .array([.object(["index": .number(0),
            "delta": .object(["role": .string("assistant"), "tool_calls": .array([.object([
                "index": .number(0), "id": .string("partial"), "type": .string("function"),
                "function": .object(["name": .string("files_read"), "arguments": .string("{")])])])]),
            "finish_reason": terminal == 1 ? .string("length") : .null])])]])
        if terminal != 0 { stream.append(Data("data: [DONE]\n\n".utf8)) }
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: stream)])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = OpenAIModelProvider(supportedModels: ["openai-api:test-model"],
            settings: .init(apiKey: { "sk-fixture" }, baseURL: baseURL, session: session))
        let adapter = try #require(try await provider.createModelStepProvider(for: "openai-api:test-model", usageContext: nil))
        do {
            let response = try await AgentLoop(provider: adapter, state: RunState()).collectStep(providerRequest())
            #expect(terminal == 1)
            #expect(response.stopReason == .outputLimit)
            #expect(response.toolCalls.first?.rawArguments == "{")
        } catch {
            #expect(terminal != 1)
            #expect((error as? ModelStepFailure)?.code == "stream_ended_before_final")
        }
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
    }

    @Test(arguments: [false, true], [false, true])
    func ollamaStepPreservesIndexedCallsThinkingUsageAndContext(json: Bool, booleanThinking: Bool) async throws {
        let calls: [JSONValue] = [0, 1].map { index in .object(["type": .string("function"), "function": .object([
            "index": .number(Double(index)), "name": .string("files_read"),
            "arguments": .object(["path": .string(index == 0 ? "a" : "b")])])]) }
        let message: JSONValue = .object(["role": .string("assistant"), "content": .string("Inspect"),
            "thinking": .string("reasoning"), "tool_calls": .array(calls)])
        let terminal: [String: JSONValue] = ["message": message, "done": .bool(true), "done_reason": .string("stop"),
            "prompt_eval_count": .number(20), "prompt_eval_cached_count": .number(8), "eval_count": .number(5)]
        var stream = Data()
        let chunks: [[String: JSONValue]] = [
            ["message": .object(["role": .string("assistant"), "content": .string("In"), "thinking": .string("reason")]), "done": .bool(false)],
            ["message": .object(["role": .string("assistant"), "tool_calls": .array([calls[1]])]), "done": .bool(false)],
            ["message": .object(["role": .string("assistant"), "content": .string("spect"), "thinking": .string("ing"), "tool_calls": .array([calls[0]])]),
                "done": .bool(true), "done_reason": .string("stop"), "prompt_eval_count": .number(20), "prompt_eval_cached_count": .number(8), "eval_count": .number(5)]
        ]
        for record in chunks {
            stream.append(try JSONEncoder().encode(JSONValue.object(record))); stream.append(0x0A)
        }
        let show: JSONValue = .object(["thinking": .object(["values": .array(booleanThinking
            ? [.bool(false), .bool(true)] : [.string("low"), .string("medium"), .string("high")])])])
        let tags: JSONValue = .object(["models": .array([.object(["name": .string("test-model")])])])
        let final: JSONValue = .object(["message": .object(["role": .string("assistant"), "content": .string("Done")]), "done": .bool(true)])
        let first = json ? try JSONEncoder().encode(JSONValue.object(terminal)) : stream
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: try JSONEncoder().encode(tags), contentType: "application/json"),
            .init(body: try JSONEncoder().encode(show), contentType: "application/json"),
            .init(body: first, contentType: json ? "application/json" : "application/x-ndjson"),
            .init(body: try JSONEncoder().encode(final), contentType: "application/json")
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = OllamaModelProvider(supportedModels: ["ollama:test-model"], baseURL: baseURL, session: session)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        #expect(factory.supportsModelSteps(for: "ollama:test-model"))
        let records = StepUsageRecords()
        let context = ModelUsageContext(channelId: "ollama-fixture", provider: "ollama", model: "test-model", onRequest: { await records.append($0) })
        let adapter = try #require(try await factory.createModelStepProvider(for: "ollama:test-model", usageContext: context))
        let loop = AgentLoop(provider: adapter, state: RunState())
        var request = providerRequest()
        request.model = "ollama:test-model"
        request.maximumOutputTokens = 2048
        request.reasoningEffort = .high
        request.messages[1].images = [.init(mimeType: "image/png", data: Data([1, 2]))]
        let response = try await loop.collectStep(request)
        #expect(response.text == "Inspect")
        #expect(response.toolCalls.count == 2)
        #expect(Set(response.toolCalls.map(\.id)).count == 2)
        let arguments = try response.toolCalls.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.rawArguments.utf8)) }
        #expect(arguments.map { $0.asObject?["path"]?.asString } == ["a", "b"])
        #expect(response.continuation?.content == message)
        #expect(response.usage == .init(prompt: 20, completion: 5, cachedInputTokens: 8))
        #expect(StepHTTPProtocol.requests(baseURL).filter { $0.url?.path.hasSuffix("/api/chat") == true }.count == 1)
        request.messages.append(.init(role: .assistant, text: response.text, toolCalls: response.toolCalls, continuation: response.continuation))
        for call in response.toolCalls { request.messages.append(.init(role: .tool, toolOutput: .init(callId: call.id, name: call.name, content: "full file"))) }
        #expect(try await loop.collectStep(request).text == "Done")
        let requests = StepHTTPProtocol.requests(baseURL)
        let generations = requests.filter { $0.url?.path.hasSuffix("/api/chat") == true }
        #expect(generations.count == 2)
        #expect(requests.filter { $0.url?.path.hasSuffix("/api/show") == true }.count == 1)
        let body = try JSONDecoder().decode(JSONValue.self, from: generations[1].body).asObject
        #expect(body?["options"]?.asObject?["num_predict"] == .number(2048))
        #expect(body?["think"] == (booleanThinking ? .bool(true) : .string("high")))
        #expect(body?["messages"]?.asArray?[2] == message)
        #expect(body?["messages"]?.asArray?[1].asObject?["images"] == .array([.string("AQI=")]))
        #expect(body?["messages"]?.asArray?[3].asObject?["tool_name"] == .string("files_read"))
        #expect(await records.values.count == 2)
        #expect(await records.values.first?.usage?.cachedInput == 8)
    }

    @Test(arguments: [false, true])
    func ollamaPartialResponseDoesNotAuthorizeCalls(done: Bool) async throws {
        let tags: JSONValue = .object(["models": .array([.object(["name": .string("test-model")])])])
        let partial: JSONValue = .object(["message": .object(["role": .string("assistant"), "tool_calls": .array([
            .object(["type": .string("function"), "function": .object(["name": .string("files_read"), "arguments": .object(["path": .string("a")])])])])]),
            "done": .bool(done), "done_reason": .string("length")])
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: try JSONEncoder().encode(tags), contentType: "application/json"),
            .init(body: Data("{}".utf8), contentType: "application/json"),
            .init(body: try JSONEncoder().encode(partial), contentType: "application/json")
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = OllamaModelProvider(supportedModels: ["ollama:test-model"], baseURL: baseURL, session: session)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "ollama:test-model", usageContext: nil))
        do {
            let response = try await AgentLoop(provider: adapter, state: RunState()).collectStep(providerRequest())
            #expect(done)
            #expect(response.stopReason == .outputLimit)
        } catch {
            #expect(!done)
            #expect((error as? ModelStepFailure)?.code == "stream_ended_before_final")
        }
    }

    @Test
    func ollamaRejectsAnUndeclaredThinkingLevelBeforeGeneration() async throws {
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: Data(#"{"models":[{"name":"test-model"}]}"#.utf8), contentType: "application/json"),
            .init(body: Data(#"{"thinking":{"values":["low","high"]}}"#.utf8), contentType: "application/json")
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = OllamaModelProvider(supportedModels: ["ollama:test-model"], baseURL: baseURL, session: session)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "ollama:test-model", usageContext: nil))
        var request = providerRequest()
        request.reasoningEffort = .max
        var code: String?
        do { _ = try await AgentLoop(provider: adapter, state: RunState()).collectStep(request) }
        catch { code = (error as? ModelStepFailure)?.code }
        #expect(code == "unsupported_reasoning_effort")
        #expect(!StepHTTPProtocol.requests(baseURL).contains { $0.url?.path.hasSuffix("/api/chat") == true })
    }

    @Test
    func ollamaCancellationStopsTheActiveGenerationAfterDiscovery() async throws {
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: Data(#"{"models":[{"name":"test-model"}]}"#.utf8), contentType: "application/json"),
            .init(body: Data("{}".utf8), contentType: "application/json"),
            .init(body: Data(), contentType: "application/x-ndjson", holdOpen: true)
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = OllamaModelProvider(supportedModels: ["ollama:test-model"], baseURL: baseURL, session: session)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "ollama:test-model", usageContext: nil))
        let state = RunState()
        let pending = Task { try await AgentLoop(provider: adapter, state: state).collectStep(providerRequest()) }
        for _ in 0..<200 where !StepHTTPProtocol.requests(baseURL).contains(where: { $0.url?.path.hasSuffix("/api/chat") == true }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(StepHTTPProtocol.requests(baseURL).contains { $0.url?.path.hasSuffix("/api/chat") == true })
        let stops = StepHTTPProtocol.stops(baseURL)
        await state.cancel()
        var cancelled = false
        do { _ = try await pending.value }
        catch { cancelled = error is CancellationError || (error as? ModelStepFailure)?.category == .cancelled }
        #expect(cancelled)
        for _ in 0..<200 where StepHTTPProtocol.stops(baseURL) == stops { try await Task.sleep(for: .milliseconds(5)) }
        #expect(StepHTTPProtocol.stops(baseURL) > stops)
    }

    @Test(arguments: [false, true])
    func anthropicStepKeepsSignedBlocksAndTypedToolErrors(json: Bool) async throws {
        let blocks: [JSONValue] = [
            .object(["type": .string("thinking"), "thinking": .string("reasoned"), "signature": .string("signed-proof")]),
            .object(["type": .string("redacted_thinking"), "data": .string("opaque-redaction")]),
            .object(["type": .string("text"), "text": .string("Inspect")]),
            .object(["type": .string("tool_use"), "id": .string("ant-call"), "name": .string("files_read"), "input": .object(["path": .string("a")])])
        ]
        let usage: JSONValue = .object(["input_tokens": .number(10), "cache_read_input_tokens": .number(5), "cache_creation_input_tokens": .number(3), "output_tokens": .number(7)])
        let final: JSONValue = .object(["type": .string("message"), "role": .string("assistant"), "content": .array(blocks), "stop_reason": .string("tool_use"), "usage": usage])
        let events: [[String: JSONValue]] = [
            ["type": .string("message_start"), "message": .object(["role": .string("assistant"), "content": .array([]), "usage": .object([
                "input_tokens": .number(10), "cache_read_input_tokens": .number(5), "cache_creation_input_tokens": .number(3), "output_tokens": .number(0)])])],
            ["type": .string("content_block_start"), "index": .number(0), "content_block": .object(["type": .string("thinking"), "thinking": .string(""), "signature": .string("")])],
            ["type": .string("content_block_delta"), "index": .number(0), "delta": .object(["type": .string("thinking_delta"), "thinking": .string("reasoned")])],
            ["type": .string("content_block_delta"), "index": .number(0), "delta": .object(["type": .string("signature_delta"), "signature": .string("signed-proof")])],
            ["type": .string("content_block_stop"), "index": .number(0)],
            ["type": .string("content_block_start"), "index": .number(1), "content_block": blocks[1]],
            ["type": .string("content_block_stop"), "index": .number(1)],
            ["type": .string("content_block_start"), "index": .number(2), "content_block": .object(["type": .string("text"), "text": .string("")])],
            ["type": .string("content_block_delta"), "index": .number(2), "delta": .object(["type": .string("text_delta"), "text": .string("Inspect")])],
            ["type": .string("content_block_stop"), "index": .number(2)],
            ["type": .string("content_block_start"), "index": .number(3), "content_block": .object(["type": .string("tool_use"), "id": .string("ant-call"), "name": .string("files_read"), "input": .object([:])])],
            ["type": .string("content_block_delta"), "index": .number(3), "delta": .object(["type": .string("input_json_delta"), "partial_json": .string("{\"path\":")])],
            ["type": .string("content_block_delta"), "index": .number(3), "delta": .object(["type": .string("input_json_delta"), "partial_json": .string("\"a\"}")])],
            ["type": .string("content_block_stop"), "index": .number(3)],
            ["type": .string("message_delta"), "delta": .object(["stop_reason": .string("tool_use")]), "usage": .object(["output_tokens": .number(7)])],
            ["type": .string("message_stop")]
        ]
        let done: JSONValue = .object(["role": .string("assistant"), "content": .array([.object(["type": .string("text"), "text": .string("Done")])]), "stop_reason": .string("end_turn")])
        let (baseURL, session) = StepHTTPProtocol.install([
            .init(body: json ? try JSONEncoder().encode(final) : try sse(events), contentType: json ? "application/json" : "text/event-stream"),
            .init(body: try JSONEncoder().encode(done), contentType: "application/json")
        ])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = AnthropicModelProvider(supportedModels: ["anthropic:test-model"], apiKey: { "sk-ant-api-fixture" }, baseURL: baseURL.deletingLastPathComponent(), session: session)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let records = StepUsageRecords()
        let context = ModelUsageContext(channelId: "ant-fixture", provider: "anthropic", model: "test-model", onRequest: { await records.append($0) })
        let adapter = try #require(try await factory.createModelStepProvider(for: "anthropic:test-model", usageContext: context))
        let loop = AgentLoop(provider: adapter, state: RunState())
        var request = providerRequest()
        request.model = "anthropic:test-model"; request.maximumOutputTokens = 2048; request.reasoningEffort = .high
        request.messages[1].images = [.init(mimeType: "image/png", data: Data([1, 2]))]
        let response = try await loop.collectStep(request)
        #expect(response.text == "Inspect")
        #expect(response.toolCalls.map(\.id) == ["ant-call"])
        #expect(response.continuation?.content == .array(blocks))
        #expect(response.usage == .init(prompt: 18, completion: 7, cachedInputTokens: 5, cacheCreationInputTokens: 3))
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
        request.messages.append(.init(role: .assistant, text: response.text, toolCalls: response.toolCalls, continuation: response.continuation))
        request.messages.append(.init(role: .tool, toolOutput: .init(callId: "ant-call", name: "files_read", content: "actual tool output", isError: true)))
        #expect(try await loop.collectStep(request).text == "Done")
        let requests = StepHTTPProtocol.requests(baseURL)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path == "/v1/messages" })
        #expect(requests[0].headers.first { $0.key.lowercased() == "x-api-key" }?.value == "sk-ant-api-fixture")
        #expect(requests[0].headers.first { $0.key.lowercased() == "anthropic-version" }?.value == "2023-06-01")
        let body = try JSONDecoder().decode(JSONValue.self, from: requests[1].body).asObject
        #expect(body?["max_tokens"] == .number(2048))
        #expect(body?["output_config"]?.asObject?["effort"] == .string("high"))
        #expect(body?["messages"]?.asArray?[1].asObject?["content"] == .array(blocks))
        #expect(body?["messages"]?.asArray?[0].asObject?["content"]?.asArray?.last?.asObject?["source"]?.asObject?["data"] == .string("AQI="))
        let toolResult = body?["messages"]?.asArray?[2].asObject?["content"]?.asArray?.first?.asObject
        #expect(toolResult?["tool_use_id"] == .string("ant-call"))
        #expect(toolResult?["is_error"] == .bool(true))
        #expect(toolResult?["content"] == .string("actual tool output"))
        #expect(await records.values.count == 2)
        #expect(await records.values.first?.usage?.total == 25)
    }

    @Test(arguments: [false, true])
    func anthropicRequiresClosedBlocksAndMessageStop(complete: Bool) async throws {
        var events: [[String: JSONValue]] = [
            ["type": .string("message_start"), "message": .object(["role": .string("assistant"), "content": .array([])])],
            ["type": .string("content_block_start"), "index": .number(0), "content_block": .object(["type": .string("tool_use"), "id": .string("partial"), "name": .string("files_read"), "input": .object([:])])],
            ["type": .string("content_block_delta"), "index": .number(0), "delta": .object(["type": .string("input_json_delta"), "partial_json": .string("{\"path\":\"a\"}")])]
        ]
        if complete {
            events += [["type": .string("content_block_stop"), "index": .number(0)],
                ["type": .string("message_delta"), "delta": .object(["stop_reason": .string("max_tokens")])], ["type": .string("message_stop")]]
        }
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: try sse(events))])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = AnthropicModelProvider(supportedModels: ["anthropic:test-model"], apiKey: { "sk-ant-api-fixture" }, baseURL: baseURL.deletingLastPathComponent(), session: session)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "anthropic:test-model", usageContext: nil))
        do {
            let response = try await AgentLoop(provider: adapter, state: RunState()).collectStep(providerRequest())
            #expect(complete)
            #expect(response.stopReason == .outputLimit)
            #expect(response.toolCalls.count == 1)
        } catch {
            #expect(!complete)
            #expect((error as? ModelStepFailure)?.code == "stream_ended_before_final")
        }
    }

    @Test
    func anthropicOAuthStepRefreshesAndUsesBearerHeadersWithoutRealNetwork() async throws {
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: Data(#"{"role":"assistant","content":[],"stop_reason":"end_turn"}"#.utf8), contentType: "application/json")], host: "api.anthropic.com")
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let credentials = StepCredentials()
        let provider = AnthropicModelProvider(supportedModels: ["anthropic:test-model"], apiKey: { credentials.current() },
            baseURL: baseURL.deletingLastPathComponent(), session: session, refreshTokenIfNeeded: { credentials.refresh() })
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "anthropic:test-model", usageContext: nil))
        _ = try await AgentLoop(provider: adapter, state: RunState()).collectStep(providerRequest())
        let request = try #require(StepHTTPProtocol.requests(baseURL).first)
        #expect(request.headers.first { $0.key.lowercased() == "authorization" }?.value == "Bearer new-token")
        #expect(request.headers.first { $0.key.lowercased() == "x-api-key" } == nil)
        #expect(request.headers.first { $0.key.lowercased() == "anthropic-beta" }?.value.contains("oauth-") == true)
        #expect(credentials.refreshCount == 1)
    }

    @Test
    func anthropicCancellationStopsTheActiveHTTPGeneration() async throws {
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: Data(), holdOpen: true)])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = AnthropicModelProvider(supportedModels: ["anthropic:test-model"], apiKey: { "sk-ant-api-fixture" }, baseURL: baseURL.deletingLastPathComponent(), session: session)
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "anthropic:test-model", usageContext: nil))
        let state = RunState()
        let pending = Task { try await AgentLoop(provider: adapter, state: state).collectStep(providerRequest()) }
        for _ in 0..<200 where StepHTTPProtocol.requests(baseURL).isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(StepHTTPProtocol.requests(baseURL).count == 1)
        await state.cancel()
        var cancelled = false
        do { _ = try await pending.value }
        catch { cancelled = error is CancellationError || (error as? ModelStepFailure)?.category == .cancelled }
        #expect(cancelled)
        for _ in 0..<200 where StepHTTPProtocol.stops(baseURL) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(StepHTTPProtocol.stops(baseURL) > 0)
    }

    @Test
    func anthropicRefreshFailureStopsBeforeHTTPGeneration() async throws {
        let (baseURL, session) = StepHTTPProtocol.install([])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        let provider = AnthropicModelProvider(supportedModels: ["anthropic:test-model"], apiKey: { "fixture" },
            baseURL: baseURL.deletingLastPathComponent(), session: session,
            refreshTokenIfNeeded: { throw URLError(.userAuthenticationRequired) })
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "anthropic:test-model", usageContext: nil))
        var failure: ModelStepFailure?
        do { _ = try await AgentLoop(provider: adapter, state: RunState()).collectStep(providerRequest()) }
        catch { failure = error as? ModelStepFailure }
        #expect(failure?.category == .authentication)
        #expect(failure?.stage == .preparation)
        #expect(StepHTTPProtocol.requests(baseURL).isEmpty)
    }

    @Test
    func tinyHTTPChunksSurviveASlowConsumerWithinTheByteLimit() async throws {
        let body = Data(repeating: 0x61, count: 128 * 1024)
        let (baseURL, session) = StepHTTPProtocol.install([.init(body: body, contentType: "application/octet-stream")])
        defer { session.invalidateAndCancel(); StepHTTPProtocol.remove(baseURL) }
        var received = Data()
        var failure: ModelStepFailure?
        var status = 0
        do {
            for try await event in ModelStepHTTPTransport(session: session).stream(URLRequest(url: baseURL)) {
                switch event {
                case .response(let code, _):
                    status = code
                    try await Task.sleep(for: .milliseconds(250))
                case .data(let bytes):
                    received.append(bytes)
                    try await Task.sleep(for: .milliseconds(1))
                }
            }
        } catch { failure = error as? ModelStepFailure }
        #expect(failure == nil)
        #expect(status == 200)
        #expect(received == body)
    }

}
