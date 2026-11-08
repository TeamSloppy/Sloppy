import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyLanguageModel
import PluginSDK
import Protocols
import Testing
@testable import sloppy

@Suite("Sloppy remote provider", .serialized)
struct SloppyRemoteProviderTests {
    @Test(arguments: [false, true]) func anonymousRemoteStepCannotInheritAnotherAuthorization(factory: Bool) async throws {
        RemoteInferenceURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization")?.isEmpty != false)
            if request.httpMethod == "GET" {
                let data = try JSONEncoder().encode([ProviderModelOption(id: "mock:test-model", title: "Step", capabilities: ["model_step_v1"])])
                return .init(status: 200, body: data, contentType: "application/json")
            }
            let body = try #require(try remoteStepBody(request))
            let input = try JSONDecoder().decode(SloppyModelStepRequest.self, from: body)
            return .init(status: 200, body: try JSONEncoder().encode(SloppyModelStepResponse(request: input.request,
                response: .init(text: "Anonymous step", stopReason: .endTurn))), contentType: "application/json")
        }
        defer { RemoteInferenceURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteInferenceURLProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "Bearer must-not-leak"]
        let http = URLSession(configuration: configuration)
        defer { http.invalidateAndCancel() }
        let adapter: any ModelStepProvider
        if factory {
            var config = CoreConfig.test
            config.models = [.init(title: "Anonymous", apiKey: "", apiUrl: "https://remote.test", model: "mock:test-model", providerCatalogId: "sloppy")]
            let provider = try #require(CoreModelProviderFactory.buildModelProvider(config: config,
                resolvedModels: ["sloppy:mock:test-model"], proxySession: http))
            let stepFactory = try #require(provider as? any ModelStepProviderFactory)
            adapter = try #require(try await stepFactory.createModelStepProvider(for: "sloppy:mock:test-model", usageContext: nil))
        } else { adapter = try SloppyModelStepProvider(baseURL: "https://remote.test", accessToken: "", model: "sloppy:mock:test-model", session: http) }
        var final: ModelStepResponse?
        for try await event in adapter.streamStep(remoteFixtureRequest(model: "sloppy:mock:test-model")) {
            if case .final(let value) = event { final = value }
        }
        #expect(final?.text == "Anonymous step")
    }

    @Test func versionedRemoteStepKeepsTheCallerAsToolOwner() async throws {
        var serverConfig = CoreConfig.test
        serverConfig.auth.token = "step-only-token"
        let server = CoreService(config: serverConfig, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await server.waitForStartup(dispatchReadyTasks: false)
        let script = RemoteStepScript()
        await server.overrideModelProviderForTests(RemoteStepFactory(script: script), defaultModel: "mock:test-model")
        let router = CoreRouter(service: server)
        RemoteInferenceURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer step-only-token")
            return await router.handle(method: request.httpMethod ?? "GET", path: request.url?.path ?? "",
                body: try remoteStepBody(request), headers: ["Authorization": "Bearer step-only-token"])
        }
        defer { RemoteInferenceURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteInferenceURLProtocol.self]
        let http = URLSession(configuration: configuration)
        defer { http.invalidateAndCancel() }
        var config = CoreConfig.test
        config.models = [.init(title: "Remote step", apiKey: "step-only-token", apiUrl: "https://remote.test",
            model: "mock:test-model", providerCatalogId: "sloppy")]
        let provider = try #require(CoreModelProviderFactory.buildModelProvider(config: config,
            resolvedModels: ["sloppy:mock:test-model"], proxySession: http))
        let factory = try #require(provider as? any ModelStepProviderFactory)
        let adapter = try #require(try await factory.createModelStepProvider(for: "sloppy:mock:test-model", usageContext: nil))
        var request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "one", attemptId: "one",
            model: "sloppy:mock:test-model", projectionRevision: "1", cacheScope: "caller",
            messages: [.init(role: .user, text: "Read through the caller")],
            tools: [.init(name: "local_read", toolId: "files.read", parameters: .object(["type": .string("object")]))],
            reasoningEffort: .high)
        var first: ModelStepResponse?
        for try await event in adapter.streamStep(request) { if case .final(let response) = event { first = response } }
        let response = try #require(first)
        #expect(await script.requests.count == 1)
        #expect(await script.legacyCalls == 0)
        #expect(response.toolCalls.first?.rawArguments == #"{ "path" : "caller.txt" }"#)
        #expect(response.usage?.total == 12)
        request.stepId = "two"; request.attemptId = "two"
        request.messages += [.init(role: .assistant, toolCalls: response.toolCalls, continuation: response.continuation),
            .init(role: .tool, toolOutput: .init(callId: "local-call", name: "local_read", content: "Caller-owned result", isError: false))]
        var last: ModelStepResponse?
        for try await event in adapter.streamStep(request) { if case .final(let response) = event { last = response } }
        #expect(last?.text == "Remote response after caller result")
        #expect(await script.requests.count == 2)
        request.messages[1].continuation?.providerId = "foreign"
        await #expect(throws: ModelStepFailure.self) { for try await _ in adapter.streamStep(request) { } }
        #expect(await script.requests.count == 2)
        #expect(await script.legacyCalls == 0)
    }

    @Test func remoteStepRejectsUnversionedAndUnauthenticatedRequests() async throws {
        var config = CoreConfig.test
        config.auth.token = "step-only-token"
        let server = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await server.waitForStartup(dispatchReadyTasks: false)
        let script = RemoteStepScript()
        await server.overrideModelProviderForTests(RemoteStepFactory(script: script), defaultModel: "mock:test-model")
        let router = CoreRouter(service: server)
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "one", attemptId: "one",
            model: "mock:test-model", projectionRevision: "1", cacheScope: "caller", messages: [.init(role: .user, text: "Task")])
        for version in [0, 2] {
            let body = try JSONEncoder().encode(Protocols.JSONValue.object(["schemaVersion": .number(Double(version)),
                "request": try JSONValueCoder.encode(request)]))
            #expect(await router.handle(method: "POST", path: "/v1/providers/step", body: body,
                headers: ["Authorization": "Bearer step-only-token"]).status == 426)
        }
        let body = try JSONEncoder().encode(Protocols.JSONValue.object(["schemaVersion": .number(1), "request": try JSONValueCoder.encode(request)]))
        #expect(await router.handle(method: "POST", path: "/v1/providers/step", body: body).status == 401)
        #expect(await script.requests.isEmpty)
        #expect(await script.legacyCalls == 0)
    }

    @Test(arguments: [false, true]) func executesToolsOnRequestingServer(streaming: Bool) async throws {
        var config = CoreConfig.test
        config.auth.token = "only-remote-token"
        let server = CoreService(config: config)
        await server.installRemoteTestModel()
        let router = CoreRouter(service: server)
        RemoteInferenceURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer only-remote-token")
            let body: Data
            if let data = request.httpBody { body = data }
            else {
                let stream = try #require(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                body = data
            }
            let payload = try JSONDecoder().decode(SloppyInferenceRequest.self, from: body)
            #expect(payload.tools.map(\.name) == ["local_echo"])
            #expect(payload.reasoningEffort == .high)
            #expect(payload.transcript.contains { if case .prompt = $0 { true } else { false } })
            return await router.handle(method: "POST", path: "/v1/providers/inference", body: body, headers: ["Authorization": "Bearer only-remote-token"])
        }
        defer { RemoteInferenceURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteInferenceURLProtocol.self]
        let http = URLSession(configuration: configuration)
        defer { http.invalidateAndCancel() }
        let model = SloppyRemoteModel(baseURL: "https://remote.test", accessToken: "only-remote-token", model: "mock:test-model", session: http)
        let counter = RemoteToolCounter()
        let session = LanguageModelSession(model: model, tools: [LocalEchoTool(counter: counter)])
        var options = GenerationOptions(maximumResponseTokens: 50)
        options[custom: SloppyRemoteModel.self] = .init(reasoningEffort: .high)
        if streaming {
            var snapshots: [String] = []
            for try await snapshot in session.streamResponse(to: "Run the local tool", generating: String.self, options: options) {
                snapshots.append(snapshot.content)
            }
            #expect(snapshots.last == "from-local")
        } else {
            let result = try await session.respond(to: "Run the local tool", generating: String.self, options: options)
            #expect(result.content == "from-local")
            #expect(result.transcriptEntries.contains { if case .toolOutput = $0 { true } else { false } })
        }
        #expect(await counter.calls == 1)
    }

    @Test func routesRemoteModelWithoutLosingItsProviderPrefix() async throws {
        var config = CoreConfig.test
        config.models = [.init(title: "Remote", apiKey: "remote-only", apiUrl: "https://remote.example/v1",
                               model: "openai-oauth:gpt-test", providerCatalogId: "sloppy")]
        let models = CoreModelProviderFactory.resolveModelIdentifiers(config: config)
        #expect(models == ["sloppy:openai-oauth:gpt-test"])
        let provider = try #require(CoreModelProviderFactory.buildModelProvider(config: config, resolvedModels: models))
        let model = try #require(try await provider.createLanguageModel(for: models[0]) as? SloppyRemoteModel)
        #expect(model.accessToken == "remote-only")
        #expect(model.model == "openai-oauth:gpt-test")
        #expect(try SloppyRemoteEndpoint.url(base: model.baseURL, path: "providers/inference").path == "/v1/providers/inference")
    }

    @Test func probesRemoteCatalogWithOnlyTheRemoteToken() async throws {
        let probe = ProviderProbeService(environmentLookup: { _ in "must-not-leak" }, transport: { request in
            #expect(request.url?.absoluteString == "https://remote.example/v1/providers/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer remote-token")
            let data = try JSONEncoder().encode([
                ProviderModelOption(id: "openai-oauth:gpt-test", title: "Codex"),
                ProviderModelOption(id: "sloppy:other", title: "Chained server"),
            ])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = await probe.probe(config: .test, request: .init(providerId: .sloppy, apiKey: "remote-token", apiUrl: "https://remote.example"))
        #expect(result.ok)
        #expect(result.models.map(\.id) == ["openai-oauth:gpt-test"])
    }

    @Test func aNewRemoteURLDoesNotInheritAnExistingServersToken() async {
        var config = CoreConfig.test
        config.models = [.init(title: "Existing server", apiKey: "existing-secret", apiUrl: "https://existing.example", model: "mock:test-model", providerCatalogId: "sloppy")]
        let probe = ProviderProbeService(transport: { request in
            #expect(request.url?.host == "new.example")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = await probe.probe(config: config, request: .init(providerId: .sloppy, apiUrl: "https://new.example"))
        #expect(result.ok)
    }

    @Test func remoteInferenceUsesConfiguredModelAndRejectsForwardingLoops() async throws {
        let router = CoreRouter(service: CoreService(config: .test))
        let request = SloppyInferenceRequest(model: "mock:test-model", transcript: Transcript(entries: [
            .prompt(.init(segments: [.text(.init(content: "Hello"))], options: .init(), responseFormat: nil)),
        ]), tools: [], options: .init())
        let headers = ["Authorization": "Bearer \(CoreConfig.test.auth.token)"]
        let response = await router.handle(method: "POST", path: "/v1/providers/inference", body: try JSONEncoder().encode(request), headers: headers)
        #expect(response.status == 200)
        let result = try JSONDecoder().decode(SloppyInferenceResponse.self, from: response.body)
        #expect(!result.text.isEmpty)
        #expect(result.toolCalls.isEmpty)
        var invalid = request
        invalid.model = "sloppy:mock:test-model"
        let rejected = await router.handle(method: "POST", path: "/v1/providers/inference", body: try JSONEncoder().encode(invalid), headers: headers)
        #expect(rejected.status == 400)
    }

    @Test func inferenceRequiresServerAuthorization() async throws {
        var config = CoreConfig.test
        config.ui.dashboardAuth.enabled = true
        config.ui.dashboardAuth.token = "remote-secret"
        let router = CoreRouter(service: CoreService(config: config))
        let body = try JSONEncoder().encode(SloppyInferenceRequest(model: "mock:test-model", transcript: .init(), tools: [], options: .init()))
        let response = await router.handle(method: "POST", path: "/v1/providers/inference", body: body)
        #expect(response.status == 401)
        let authorized = await router.handle(method: "POST", path: "/v1/providers/inference", body: body, headers: ["Authorization": "Bearer remote-secret"])
        #expect(authorized.status == 200)
    }
}

private func remoteStepBody(_ request: URLRequest) throws -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private actor RemoteStepScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    private(set) var legacyCalls = 0
    func legacy() { legacyCalls += 1 }
    private func next(_ request: ModelStepRequest) -> ModelStepResponse {
        requests.append(request)
        #expect(request.model == "mock:test-model")
        if requests.count == 1 {
            #expect(request.reasoningEffort == .high)
            #expect(request.tools.first?.name == "local_read")
            return .init(toolCalls: [.init(id: "local-call", name: "local_read", rawArguments: #"{ "path" : "caller.txt" }"#)],
                stopReason: .toolCalls, usage: .init(prompt: 10, completion: 2),
                continuation: .init(providerId: "remote-fixture", modelId: "mock:test-model", format: "signed-v1", content: .string("signed-value")))
        }
        #expect(request.messages[1].continuation?.providerId == "remote-fixture")
        #expect(request.messages[1].continuation?.content == .string("signed-value"))
        #expect(request.messages.last?.toolOutput?.content == "Caller-owned result")
        return .init(text: "Remote response after caller result", stopReason: .endTurn)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { continuation.yield(.started); continuation.yield(.final(await self.next(request))); continuation.finish() }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct RemoteStepFactory: ModelProvider, ModelStepProviderFactory {
    let id = "remote-fixture"
    let supportedModels = ["mock:test-model"]
    let script: RemoteStepScript
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        await script.legacy()
        throw ModelStepFailure(category: .protocolViolation, code: "legacy_remote_generation", message: "Remote steps cannot use legacy scheduling.")
    }
}

private extension CoreService {
    func installRemoteTestModel() {
        modelProvider = AnyModelProviderBox(id: "mock", supportedModels: ["mock:test-model"], createLanguageModel: { _ in RemoteToolTestModel() })
    }
}

private struct RemoteToolTestModel: LanguageModel {
    typealias UnavailableReason = Never
    func respond<Content: Generable>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type, includeSchemaInPrompt: Bool, options: GenerationOptions) async throws -> LanguageModelSession.Response<Content> {
        if session.transcript.contains(where: { if case .toolOutput = $0 { true } else { false } }) {
            let raw = GeneratedContent("from-local")
            return .init(content: try type.init(raw), rawContent: raw, transcriptEntries: [])
        }
        let call = Transcript.ToolCall(id: "call-1", toolName: "local_echo", arguments: GeneratedContent("input"))
        let delegate = try #require(session.toolExecutionDelegate)
        await delegate.didGenerateToolCalls([call], in: session)
        guard case .stop = await delegate.toolCallDecision(for: call, in: session) else {
            Issue.record("Remote server must not execute caller tools")
            throw SloppyRemoteError.toolUnavailable(call.toolName)
        }
        let raw = GeneratedContent("")
        return .init(content: try type.init(raw), rawContent: raw, transcriptEntries: [])
    }
    func streamResponse<Content: Generable>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type, includeSchemaInPrompt: Bool, options: GenerationOptions) -> sending LanguageModelSession.ResponseStream<Content> {
        .init(stream: AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await respond(within: session, to: prompt, generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
                    continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        })
    }
}

private actor RemoteToolCounter { var calls = 0; func increment() { calls += 1 } }
private struct LocalEchoTool: Tool {
    let name = "local_echo"
    let description = "A tool owned by the requesting server"
    let counter: RemoteToolCounter
    func call(arguments: String) async throws -> String {
        #expect(arguments == "input")
        await counter.increment()
        return "from-local"
    }
}

private final class RemoteInferenceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async throws -> CoreRouterResponse)?
    private var loadingTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let handler = Self.handler
        let request = self.request
        let capturedProtocol = RemoteInferenceProtocolBox(value: self)
        loadingTask = Task<Void, Never> {
            let protocolInstance = capturedProtocol.value
            do {
                guard let handler else { throw URLError(.unknown) }
                let response = try await handler(request)
                let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: ["Content-Type": response.contentType])!
                protocolInstance.client?.urlProtocol(protocolInstance, didReceive: http, cacheStoragePolicy: .notAllowed)
                if let stream = response.sseStream {
                    for await event in stream {
                        let frame = "event: \(event.event)\ndata: \(String(decoding: event.data, as: UTF8.self))\n\n"
                        protocolInstance.client?.urlProtocol(protocolInstance, didLoad: Data(frame.utf8))
                    }
                } else { protocolInstance.client?.urlProtocol(protocolInstance, didLoad: response.body) }
                protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
            } catch { protocolInstance.client?.urlProtocol(protocolInstance, didFailWithError: error) }
        }
    }
    override func stopLoading() { loadingTask?.cancel() }
}

private struct RemoteInferenceProtocolBox<Value>: @unchecked Sendable {
    let value: Value
}
