import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyLanguageModel
import Testing
@testable import sloppy
import Protocols

struct ProviderEnvironmentKeyTests {
    @Test(arguments: ["$ELIZA_TOKEN", "${ELIZA_TOKEN}"])
    func probeResolvesRequestReference(reference: String) async {
        let service = ProviderProbeService(
            environmentLookup: { $0 == "ELIZA_TOKEN" ? "test-env-secret" : nil },
            transport: { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-env-secret")
                return (Data(#"{"data":[{"id":"gpt-test"}]}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )
        let result = await service.probe(config: .test, request: .init(
            providerId: .openAIAPI, apiKey: reference, apiUrl: "https://eliza.example/v1"
        ))
        #expect(result.ok)
        #expect(result.usedEnvironmentKey)
        #expect(!result.message.contains("test-env-secret"))
    }

    @Test
    func missingReferenceDoesNotFallBackOrSendRequest() async {
        let service = ProviderProbeService(
            environmentLookup: { $0 == "OPENAI_API_KEY" ? "unrelated-key" : nil },
            transport: { _ in
                Issue.record("Missing explicit ENV must fail before transport, even on LAN")
                throw URLError(.cancelled)
            }
        )
        let result = await service.probe(config: .test, request: .init(
            providerId: .openAIAPI, apiKey: "$ELIZA_TOKEN", apiUrl: "http://127.0.0.1:1234"
        ))
        #expect(!result.ok)
        #expect(result.message.contains("ELIZA_TOKEN"))
        #expect(result.message.contains("environment"))
    }
}

private final class EnvironmentKeyURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-env-secret")
        #expect(request.url?.path == "/v1/chat/completions")
        let data = Data(#"{"id":"test","object":"chat.completion","created":1,"model":"gpt-test","choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension ProviderEnvironmentKeyTests {
    private func config(key: String = "$ELIZA_TOKEN") -> CoreConfig {
        var config = CoreConfig.test
        config.models = [.init(title: "Eliza", apiKey: key, apiUrl: "https://eliza.example/v1",
                               model: "gpt-test", providerCatalogId: "openai-api")]
        return config
    }

    @Test(arguments: ["raw-key", "key$with-dollar", "  raw-key  "])
    func literalKeysStayLiteral(key: String) throws {
        let result = try ProviderAPIKeyResolver.resolve(configured: key, environmentLookup: { _ in "wrong-account" })
        #expect(result.key == key.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!result.usedEnvironmentKey)
    }

    @Test(arguments: ["$", "${}", "$9NAME", "${NAME", "$NAME/suffix", "$(whoami)", "${NAME:-fallback}"])
    func rejectsMalformedReferences(reference: String) {
        #expect(throws: ProviderAPIKeyResolver.ResolutionError.self) {
            try ProviderAPIKeyResolver.resolve(configured: reference, environmentLookup: { _ in "secret" })
        }
    }

    @Test(arguments: ["", "  "])
    func emptyEnvironmentIsAnError(value: String) {
        #expect(throws: ProviderAPIKeyResolver.ResolutionError.self) {
            try ProviderAPIKeyResolver.resolve(configured: "$ELIZA_TOKEN", environmentLookup: { _ in value })
        }
    }

    @Test
    func blankKeyKeepsDefaultEnvironmentFallback() throws {
        let result = try ProviderAPIKeyResolver.resolve(configured: " ", environmentLookup: {
            $0 == "OPENAI_API_KEY" ? "default-key" : nil
        })
        #expect(result.key == "default-key")
        #expect(result.usedEnvironmentKey)
    }

    @Test
    func catalogAndProbeResolveSavedReferenceWithoutChangingConfig() async throws {
        let config = config()
        let transport: ProviderProbeService.Transport = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-env-secret")
            return (Data(#"{"data":[{"id":"gpt-test"}]}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let lookup: @Sendable (String) -> String? = { $0 == "ELIZA_TOKEN" ? "test-env-secret" : nil }
        let catalog = OpenAIProviderCatalogService(environmentLookup: lookup, transport: transport)
        let result = await catalog.listModels(config: config, request: .init(authMethod: .apiKey))
        #expect(result.source == "remote")
        #expect(result.usedEnvironmentKey)
        let status = catalog.status(config: config)
        #expect(status.hasAnyKey)
        #expect(status.hasEnvironmentKey)
        let probe = await ProviderProbeService(environmentLookup: lookup, transport: transport)
            .probe(config: config, request: .init(providerId: .openAIAPI))
        #expect(probe.ok)
        #expect(probe.usedEnvironmentKey)
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CoreConfig.self, from: encoded)
        #expect(decoded.models.first?.apiKey == "$ELIZA_TOKEN")
        #expect(!String(decoding: encoded, as: UTF8.self).contains("test-env-secret"))
    }

    @Test
    func catalogFailsBeforeTransportForMissingReference() async {
        let catalog = OpenAIProviderCatalogService(environmentLookup: { _ in nil }, transport: { _ in
            Issue.record("Missing ENV must not hit transport")
            throw URLError(.cancelled)
        })
        let result = await catalog.listModels(config: config(), request: .init(authMethod: .apiKey))
        #expect(result.source == "fallback")
        #expect(result.warning?.contains("ELIZA_TOKEN") == true)
        #expect(!catalog.status(config: config()).hasAnyKey)
    }

    @Test(arguments: ["$ELIZA_TOKEN", "${ELIZA_TOKEN}"])
    func runtimeUsesResolvedKey(reference: String) async throws {
        let config = config(key: reference)
        let httpConfig = URLSessionConfiguration.ephemeral
        httpConfig.protocolClasses = [EnvironmentKeyURLProtocol.self]
        let http = URLSession(configuration: httpConfig)
        defer { http.invalidateAndCancel() }
        let factory = OpenAIModelProviderFactory(environmentLookup: { $0 == "ELIZA_TOKEN" ? "test-env-secret" : nil })
        let provider = try #require(factory.buildProvider(from: .init(
            coreConfig: config, modelConfigs: config.models, resolvedModels: ["openai-api:gpt-test"],
            tools: [], systemInstructions: nil, proxySession: http
        )))
        let model = try await provider.createLanguageModel(for: "openai-api:gpt-test")
        let result = try await LanguageModelSession(model: model).respond(to: "test", generating: String.self)
        #expect(result.content == "ok")
        #expect(config.models.first?.apiKey == reference)
    }

    @Test
    func runtimeDoesNotUseDefaultKeyWhenExplicitReferenceIsMissing() {
        let config = config()
        let factory = OpenAIModelProviderFactory(environmentLookup: { $0 == "OPENAI_API_KEY" ? "wrong-account" : nil })
        #expect(factory.buildProvider(from: .init(
            coreConfig: config, modelConfigs: config.models, resolvedModels: ["openai-api:gpt-test"],
            tools: [], systemInstructions: nil, proxySession: nil
        )) == nil)
    }
}
