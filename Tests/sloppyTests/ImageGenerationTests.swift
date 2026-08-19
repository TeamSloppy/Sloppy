import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols
import Testing
@testable import sloppy

private final class ImageGenerationMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class ImageGenerationLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private func imageGenerationSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ImageGenerationMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func imageGenerationHTTPResponse(
    request: URLRequest,
    status: Int = 200,
    contentType: String = "application/json"
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType]
    )!
}

private func imageGenerationRequestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data.isEmpty ? nil : data
}

@Suite("Image generation", .serialized)
struct ImageGenerationTests {
    @Test("old config payloads receive disabled image generation defaults")
    func backwardCompatibleConfigDefaults() throws {
        let encoded = try JSONEncoder().encode(CoreConfig.test)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "imageGeneration")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CoreConfig.self, from: legacy)

        #expect(decoded.imageGeneration.enabled == false)
        #expect(decoded.imageGeneration.provider == .fal)
        #expect(decoded.imageGeneration.model == "fal-ai/flux-2")
        #expect(decoded.imageGeneration.timeoutMs == 180_000)
    }

    @Test("FAL_KEY precedence is session, process, then config")
    func credentialPrecedence() {
        let config = CoreConfig.ImageGeneration(fal: .init(apiKey: "config-key"))
        #expect(ImageGenerationCredentialResolver.resolve(
            provider: .fal,
            config: config,
            models: [],
            environmentOverrides: ["FAL_KEY": "session-key"],
            processEnvironment: ["FAL_KEY": "process-key"]
        ).apiKey == "session-key")
        #expect(ImageGenerationCredentialResolver.resolve(
            provider: .fal,
            config: config,
            models: [],
            environmentOverrides: [:],
            processEnvironment: ["FAL_KEY": "process-key"]
        ).apiKey == "process-key")
        #expect(ImageGenerationCredentialResolver.resolve(
            provider: .fal,
            config: config,
            models: [],
            environmentOverrides: [:],
            processEnvironment: [:]
        ).apiKey == "config-key")

        let openAIModels = [CoreConfig.ModelConfig(
            title: "OpenAI API",
            apiKey: "configured-openai",
            apiUrl: "https://api.openai.com/v1",
            model: "gpt-5.4-mini",
            providerCatalogId: "openai-api"
        )]
        #expect(ImageGenerationCredentialResolver.resolve(
            provider: .openAI,
            config: config,
            models: openAIModels,
            environmentOverrides: ["OPENAI_API_KEY": "session-openai"],
            processEnvironment: ["OPENAI_API_KEY": "process-openai"]
        ).apiKey == "session-openai")
        let configuredOpenAI = ImageGenerationCredentialResolver.resolve(
            provider: .openAI,
            config: config,
            models: openAIModels,
            environmentOverrides: [:],
            processEnvironment: [:]
        )
        #expect(configuredOpenAI.apiKey == "configured-openai")
        #expect(configuredOpenAI.apiBaseURL?.absoluteString == "https://api.openai.com/v1")
    }

    @Test("FAL generate submits safe single-image payload and polls queue")
    func falGenerateQueueFlow() async throws {
        let capturedBody = ImageGenerationLocked<Data?>(nil)
        let statusCalls = ImageGenerationLocked(0)
        ImageGenerationMockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/fal-ai/flux-2":
                capturedBody.withLock { $0 = imageGenerationRequestBody(request) }
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Key secret")
                let data = Data(#"{"request_id":"req-1","status_url":"https://queue.fal.run/status/req-1","response_url":"https://queue.fal.run/result/req-1"}"#.utf8)
                return (imageGenerationHTTPResponse(request: request), data)
            case "/status/req-1":
                let call = statusCalls.withLock { value -> Int in
                    value += 1
                    return value
                }
                let status = call == 1 ? "IN_PROGRESS" : "COMPLETED"
                return (imageGenerationHTTPResponse(request: request), Data("{\"status\":\"\(status)\"}".utf8))
            case "/result/req-1":
                return (imageGenerationHTTPResponse(request: request), Data(#"{"images":[{"url":"https://cdn.example/image.png","width":1024,"height":576,"content_type":"image/png"}],"seed":42}"#.utf8))
            default:
                throw URLError(.badURL)
            }
        }
        defer { ImageGenerationMockURLProtocol.requestHandler = nil }
        let provider = FALImageGenerationProvider(
            apiKey: "secret",
            session: imageGenerationSession(),
            pollIntervalNanoseconds: 1_000_000
        )

        let result = try await provider.generate(
            request: ImageGenerationRequest(prompt: "A lighthouse", aspectRatio: nil, sourceImages: [], seed: 42),
            model: try #require(ImageGenerationCatalog.model(id: "fal-ai/flux-2")),
            timeoutMs: 1_000
        )

        #expect(result.imageURL?.absoluteString == "https://cdn.example/image.png")
        #expect(result.width == 1024)
        #expect(result.height == 576)
        let body = try #require(capturedBody.withLock { $0 })
        let payload = try JSONDecoder().decode(JSONValue.self, from: body).asObject
        #expect(payload?["image_size"]?.asString == "landscape_16_9")
        #expect(payload?["num_images"]?.asNumber == 1)
        #expect(payload?["output_format"]?.asString == "png")
        #expect(payload?["enable_safety_checker"]?.asBool == true)
    }

    @Test("FAL edit uses configured edit endpoint and preserves source proportions")
    func falEditPayload() async throws {
        let capturedPath = ImageGenerationLocked("")
        let capturedBody = ImageGenerationLocked<Data?>(nil)
        ImageGenerationMockURLProtocol.requestHandler = { request in
            if request.httpMethod == "POST" {
                capturedPath.withLock { $0 = request.url?.path ?? "" }
                capturedBody.withLock { $0 = imageGenerationRequestBody(request) }
                return (imageGenerationHTTPResponse(request: request), Data(#"{"request_id":"req-edit","status_url":"https://queue.fal.run/status/edit","response_url":"https://queue.fal.run/result/edit"}"#.utf8))
            }
            if request.url?.path == "/status/edit" {
                return (imageGenerationHTTPResponse(request: request), Data(#"{"status":"COMPLETED"}"#.utf8))
            }
            return (imageGenerationHTTPResponse(request: request), Data(#"{"data":{"images":[{"url":"https://cdn.example/edit.png"}]}}"#.utf8))
        }
        defer { ImageGenerationMockURLProtocol.requestHandler = nil }
        let provider = FALImageGenerationProvider(apiKey: "secret", session: imageGenerationSession(), pollIntervalNanoseconds: 1)

        _ = try await provider.generate(
            request: ImageGenerationRequest(
                prompt: "Make the sky orange",
                aspectRatio: nil,
                sourceImages: ["https://example.com/source.png"],
                seed: nil
            ),
            model: try #require(ImageGenerationCatalog.model(id: "fal-ai/flux-2-pro")),
            timeoutMs: 1_000
        )

        #expect(capturedPath.withLock { $0 } == "/fal-ai/flux-2-pro/edit")
        let body = try #require(capturedBody.withLock { $0 })
        let payload = try #require(try JSONDecoder().decode(JSONValue.self, from: body).asObject)
        #expect(payload["image_size"] == nil)
        #expect(payload["image_urls"]?.asArray?.first?.asString == "https://example.com/source.png")
    }

    @Test("FAL provider times out while request remains queued")
    func falTimeout() async throws {
        ImageGenerationMockURLProtocol.requestHandler = { request in
            if request.httpMethod == "POST" {
                return (imageGenerationHTTPResponse(request: request), Data(#"{"request_id":"req-timeout","status_url":"https://queue.fal.run/status/timeout","response_url":"https://queue.fal.run/result/timeout"}"#.utf8))
            }
            return (imageGenerationHTTPResponse(request: request), Data(#"{"status":"IN_QUEUE"}"#.utf8))
        }
        defer { ImageGenerationMockURLProtocol.requestHandler = nil }
        let provider = FALImageGenerationProvider(apiKey: "secret", session: imageGenerationSession(), pollIntervalNanoseconds: 1_000_000)

        await #expect(throws: ImageGenerationProviderError.timeout) {
            try await provider.generate(
                request: ImageGenerationRequest(prompt: "A test", aspectRatio: .square, sourceImages: [], seed: nil),
                model: try #require(ImageGenerationCatalog.model(id: "fal-ai/flux-2")),
                timeoutMs: 1
            )
        }
    }

    @Test("FAL provider maps HTTP and malformed responses")
    func falErrorResponses() async throws {
        ImageGenerationMockURLProtocol.requestHandler = { request in
            (imageGenerationHTTPResponse(request: request, status: 401), Data(#"{"detail":"invalid key"}"#.utf8))
        }
        let provider = FALImageGenerationProvider(apiKey: "bad", session: imageGenerationSession())
        await #expect(throws: ImageGenerationProviderError.http(status: 401, message: "invalid key")) {
            try await provider.generate(
                request: ImageGenerationRequest(prompt: "A test", aspectRatio: nil, sourceImages: [], seed: nil),
                model: try #require(ImageGenerationCatalog.model(id: "fal-ai/flux-2")),
                timeoutMs: 1_000
            )
        }

        ImageGenerationMockURLProtocol.requestHandler = { request in
            (imageGenerationHTTPResponse(request: request), Data(#"{"ok":true}"#.utf8))
        }
        await #expect(throws: ImageGenerationProviderError.invalidResponse("FAL submit response did not contain request_id.")) {
            try await provider.generate(
                request: ImageGenerationRequest(prompt: "A test", aspectRatio: nil, sourceImages: [], seed: nil),
                model: try #require(ImageGenerationCatalog.model(id: "fal-ai/flux-2")),
                timeoutMs: 1_000
            )
        }
        ImageGenerationMockURLProtocol.requestHandler = nil
    }

    @Test("FAL provider propagates task cancellation")
    func falCancellation() async throws {
        ImageGenerationMockURLProtocol.requestHandler = { request in
            if request.httpMethod == "POST" {
                return (imageGenerationHTTPResponse(request: request), Data(#"{"request_id":"req-cancel","status_url":"https://queue.fal.run/status/cancel","response_url":"https://queue.fal.run/result/cancel"}"#.utf8))
            }
            return (imageGenerationHTTPResponse(request: request), Data(#"{"status":"IN_QUEUE"}"#.utf8))
        }
        defer { ImageGenerationMockURLProtocol.requestHandler = nil }
        let provider = FALImageGenerationProvider(
            apiKey: "secret",
            session: imageGenerationSession(),
            pollIntervalNanoseconds: 5_000_000_000
        )
        let task = Task {
            try await provider.generate(
                request: ImageGenerationRequest(prompt: "A test", aspectRatio: nil, sourceImages: [], seed: nil),
                model: try #require(ImageGenerationCatalog.model(id: "fal-ai/flux-2")),
                timeoutMs: 60_000
            )
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected image generation to be cancelled.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    @Test("OpenAI generation returns base64 image with bounded medium-quality payload")
    func openAIGenerationPayload() async throws {
        let capturedBody = ImageGenerationLocked<Data?>(nil)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ImageGenerationMockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/v1/images/generations")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-key")
            capturedBody.withLock { $0 = imageGenerationRequestBody(request) }
            let payload = "{\"data\":[{\"b64_json\":\"\(png.base64EncodedString())\"}],\"output_format\":\"png\",\"size\":\"1024x1024\"}"
            return (imageGenerationHTTPResponse(request: request), Data(payload.utf8))
        }
        defer { ImageGenerationMockURLProtocol.requestHandler = nil }
        let provider = OpenAIImageGenerationProvider(apiKey: "openai-key", session: imageGenerationSession())

        let result = try await provider.generate(
            request: ImageGenerationRequest(prompt: "A lighthouse", aspectRatio: .square, sourceImages: [], seed: 123),
            model: try #require(ImageGenerationCatalog.model(id: "gpt-image-2")),
            timeoutMs: 1_000
        )

        #expect(result.imageData == png)
        #expect(result.imageURL == nil)
        #expect(result.width == 1024)
        #expect(result.height == 1024)
        #expect(result.seed == nil)
        let body = try #require(capturedBody.withLock { $0 })
        let payload = try #require(try JSONDecoder().decode(JSONValue.self, from: body).asObject)
        #expect(payload["model"]?.asString == "gpt-image-2")
        #expect(payload["size"]?.asString == "1024x1024")
        #expect(payload["quality"]?.asString == "medium")
        #expect(payload["output_format"]?.asString == "png")
        #expect(payload["seed"] == nil)
    }

    @Test("OpenAI editing sends URL/data references and preserves source proportions")
    func openAIEditPayload() async throws {
        let capturedBody = ImageGenerationLocked<Data?>(nil)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ImageGenerationMockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/v1/images/edits")
            capturedBody.withLock { $0 = imageGenerationRequestBody(request) }
            let payload = "{\"data\":[{\"b64_json\":\"\(png.base64EncodedString())\"}],\"output_format\":\"png\"}"
            return (imageGenerationHTTPResponse(request: request), Data(payload.utf8))
        }
        defer { ImageGenerationMockURLProtocol.requestHandler = nil }
        let provider = OpenAIImageGenerationProvider(apiKey: "openai-key", session: imageGenerationSession())
        let source = "data:image/png;base64,\(png.base64EncodedString())"

        _ = try await provider.generate(
            request: ImageGenerationRequest(prompt: "Change the sky", aspectRatio: nil, sourceImages: [source], seed: nil),
            model: try #require(ImageGenerationCatalog.model(id: "gpt-image-2")),
            timeoutMs: 1_000
        )

        let body = try #require(capturedBody.withLock { $0 })
        let payload = try #require(try JSONDecoder().decode(JSONValue.self, from: body).asObject)
        #expect(payload["size"]?.asString == "auto")
        #expect(payload["input_fidelity"]?.asString == "high")
        #expect(payload["images"]?.asArray?.first?.asObject?["image_url"]?.asString == source)
    }

    @Test("image artifact is persisted, readable, described, and removable")
    func imageArtifactLifecycle() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ImageGenerationMockURLProtocol.requestHandler = { request in
            (imageGenerationHTTPResponse(request: request, contentType: "image/png"), png)
        }
        defer { ImageGenerationMockURLProtocol.requestHandler = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("image-artifact-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = try await ImageArtifactService.create(
            remoteURL: URL(string: "https://cdn.example/image.png")!,
            prompt: "A lighthouse",
            provider: "fal",
            model: "fal-ai/flux-2",
            modality: .textToImage,
            seed: 7,
            width: 1024,
            height: 576,
            workspaceRootURL: root,
            session: imageGenerationSession()
        )
        let record = PersistedArtifactRecord(
            id: artifact.id,
            kind: "image",
            mediaType: artifact.mediaType,
            content: artifact.manifestJSON,
            bundlePath: ImageArtifactService.bundlePath(id: artifact.id),
            createdAt: Date()
        )

        #expect(FileManager.default.fileExists(atPath: artifact.fileURL.path))
        #expect(ImageArtifactService.metadata(from: record)?.contentUrl == "/v1/artifacts/\(artifact.id)/file")
        #expect(ImageArtifactService.file(record: record, workspaceRootURL: root)?.data == png)
        ImageArtifactService.deleteBundle(id: artifact.id, workspaceRootURL: root)
        #expect(!FileManager.default.fileExists(atPath: artifact.fileURL.deletingLastPathComponent().path))
    }

    @Test("tool rejects paid generation while disabled")
    func toolDisabledBoundary() async throws {
        let service = CoreService(config: .test)
        _ = try await service.createAgent(AgentCreateRequest(id: "image-disabled", displayName: "Image", role: "Testing"))
        let session = try await service.createAgentSession(
            agentID: "image-disabled",
            request: AgentSessionCreateRequest(title: "Image")
        )

        let result = await service.invokeToolFromRuntime(
            agentID: "image-disabled",
            sessionID: session.id,
            request: ToolInvocationRequest(tool: "images.generate", arguments: ["prompt": .string("A lighthouse")]),
            recordSessionEvents: false
        )

        #expect(result.ok == false)
        #expect(result.error?.code == "image_generation_disabled")
    }

    @Test("tool confines local source images before provider dispatch")
    func toolSourceConfinement() async throws {
        var config = CoreConfig.test
        config.imageGeneration = .init(enabled: true, fal: .init(apiKey: "test-key"))
        let service = CoreService(config: config)
        _ = try await service.createAgent(AgentCreateRequest(id: "image-confined", displayName: "Image", role: "Testing"))
        let session = try await service.createAgentSession(
            agentID: "image-confined",
            request: AgentSessionCreateRequest(title: "Image")
        )

        let result = await service.invokeToolFromRuntime(
            agentID: "image-confined",
            sessionID: session.id,
            request: ToolInvocationRequest(
                tool: "images.generate",
                arguments: [
                    "prompt": .string("Edit this"),
                    "sourceImage": .string("/etc/passwd"),
                ]
            ),
            recordSessionEvents: false
        )

        #expect(result.ok == false)
        #expect(result.error?.code == "invalid_arguments")
    }

    @Test("provider status and binary artifact routes expose image capability")
    func imageGenerationRoutes() async throws {
        var config = CoreConfig.test
        config.imageGeneration = .init(enabled: true, model: "fal-ai/flux-2-pro", fal: .init(apiKey: "configured"))
        let service = CoreService(config: config)
        let router = CoreRouter(service: service)

        let statusResponse = await router.handle(method: "GET", path: "/v1/providers/image-generation/status", body: nil)
        #expect(statusResponse.status == 200)
        let status = try JSONDecoder().decode(ImageGenerationStatusResponse.self, from: statusResponse.body)
        #expect(status.enabled)
        #expect(status.model == "fal-ai/flux-2-pro")
        #expect(status.hasConfiguredKey)
        #expect(status.models.count == 3)
        #expect(status.models.contains { $0.id == "gpt-image-2" && $0.provider == "openai" })

        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ImageGenerationMockURLProtocol.requestHandler = { request in
            (imageGenerationHTTPResponse(request: request, contentType: "image/png"), png)
        }
        defer { ImageGenerationMockURLProtocol.requestHandler = nil }
        let artifact = try await ImageArtifactService.create(
            remoteURL: URL(string: "https://cdn.example/route.png")!,
            prompt: "Route image",
            provider: "fal",
            model: "fal-ai/flux-2",
            modality: .textToImage,
            seed: nil,
            width: 8,
            height: 8,
            workspaceRootURL: service.workspaceRootURL,
            session: imageGenerationSession()
        )
        await service.store.persistArtifact(record: PersistedArtifactRecord(
            id: artifact.id,
            kind: "image",
            mediaType: artifact.mediaType,
            content: artifact.manifestJSON,
            bundlePath: ImageArtifactService.bundlePath(id: artifact.id),
            createdAt: Date()
        ))

        let fileResponse = await router.handle(method: "GET", path: "/v1/artifacts/\(artifact.id)/file", body: nil)
        #expect(fileResponse.status == 200)
        #expect(fileResponse.contentType == "image/png")
        #expect(fileResponse.body == png)

        let deleteResponse = await router.handle(method: "DELETE", path: "/v1/artifacts/\(artifact.id)", body: nil)
        #expect(deleteResponse.status == 200)
        let afterDelete = await router.handle(method: "GET", path: "/v1/artifacts/\(artifact.id)/file", body: nil)
        #expect(afterDelete.status == 404)
        #expect(!FileManager.default.fileExists(atPath: artifact.fileURL.deletingLastPathComponent().path))
    }

    @Test("OpenAI image provider status reuses configured OpenAI API credentials")
    func openAIImageProviderStatus() async throws {
        var config = CoreConfig.test
        config.imageGeneration = .init(enabled: true, provider: .openAI, model: "gpt-image-2")
        config.models = [CoreConfig.ModelConfig(
            title: "OpenAI API",
            apiKey: "configured-openai",
            apiUrl: "https://api.openai.com/v1",
            model: "gpt-5.4-mini",
            providerCatalogId: "openai-api"
        )]
        let service = CoreService(config: config)
        let response = await CoreRouter(service: service).handle(
            method: "GET",
            path: "/v1/providers/image-generation/status",
            body: nil
        )

        let status = try JSONDecoder().decode(ImageGenerationStatusResponse.self, from: response.body)
        #expect(response.status == 200)
        #expect(status.provider == "openai")
        #expect(status.model == "gpt-image-2")
        #expect(status.hasConfiguredKey)
    }
}
