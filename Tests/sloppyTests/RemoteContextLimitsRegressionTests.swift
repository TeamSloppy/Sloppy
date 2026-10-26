import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PluginSDK
import Protocols
@testable import sloppy

@Suite(.serialized) struct RemoteContextLimitsRegressionTests {
    @Test func numericRemoteLimitsSurviveCatalogRoundTrip() throws {
        let source = ProviderModelOption(id: "vendor:generic-large", title: "Large",
            contextWindow: "rounded display", contextWindowTokens: 245_760,
            maxInputTokens: 220_000, maxOutputTokens: 16_384)
        let decoded = try JSONDecoder().decode(ProviderModelOption.self, from: JSONEncoder().encode(source))
        let cache = RemoteModelContextLimits()
        cache.store(decoded, for: "sloppy:vendor:generic-large")
        #expect(cache.value(for: "sloppy:vendor:generic-large") == ModelContextLimits(
            contextWindowTokens: 245_760, maxInputTokens: 220_000, maxOutputTokens: 16_384))
        #expect(cache.value(for: "sloppy:vendor:other") == nil)
    }

    @Test func olderCatalogDoesNotInventWindowFromDisplayOrName() throws {
        let data = Data(#"{"id":"vendor:large","title":"Large","capabilities":[],"contextWindow":"200K"}"#.utf8)
        let option = try JSONDecoder().decode(ProviderModelOption.self, from: data)
        let cache = RemoteModelContextLimits()
        cache.store(option, for: "sloppy:vendor:large")
        #expect(cache.value(for: "sloppy:vendor:large") == nil)
        cache.store(.init(id: "vendor:large", title: "Large", contextWindowTokens: -1), for: "invalid")
        #expect(cache.value(for: "invalid") == nil)
    }

    @Test func exportedCatalogUsesAuthoritativeProviderLimits() {
        let option = ProviderModelOption(id: "vendor:generic", title: "Generic", contextWindow: "rounded")
        let exported = CoreService.providerModelOption(option, limits: .init(
            contextWindowTokens: 200_000, maxInputTokens: 180_000, maxOutputTokens: 32_000))
        #expect(exported.contextWindowTokens == 200_000)
        #expect(exported.maxInputTokens == 180_000)
        #expect(exported.maxOutputTokens == 32_000)
        #expect(exported.contextWindow == "rounded")
    }

    @Test(arguments: [200_000, 245_760])
    func catalogDiscoveryPopulatesExactFactoryModelBeforeRuntimeBudget(window: Int) async throws {
        let option = ProviderModelOption(id: "claude-code:sonnet", title: "Remote Sonnet",
            contextWindow: "deliberately not numeric", contextWindowTokens: window,
            maxInputTokens: window - 10_000, maxOutputTokens: 16_384)
        let data = try JSONEncoder().encode([option])
        RemoteContextCatalogURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/providers/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer remote-only")
            return (200, data)
        }
        defer { RemoteContextCatalogURLProtocol.handler = nil }
        let http = makeSession()
        defer { http.invalidateAndCancel() }
        let provider = try makeProvider(session: http)
        let name = "sloppy:claude-code:sonnet"
        #expect(provider.contextLimits(for: name) == nil)
        _ = try await provider.createLanguageModel(for: name)
        let limits = try #require(provider.contextLimits(for: name))
        #expect(limits == ModelContextLimits(contextWindowTokens: window,
            maxInputTokens: window - 10_000, maxOutputTokens: 16_384))
        // Runtime consumes this exact API after creating its language model.
        #expect(limits.inputBudget(reserving: 32_000) == window - 10_000 - 16_384)
        #expect(provider.contextLimits(for: "sloppy:claude-code:sonnet-extra") == nil)
        #expect(provider.contextLimits(for: "claude-code:sonnet") == nil)
    }

    @Test(arguments: ["legacy", "similar-id", "failed-catalog"])
    func missingExactNumericCatalogMetadataPreservesFallback(scenario: String) async throws {
        let id = scenario == "similar-id" ? "claude-code:sonnet-extra" : "claude-code:sonnet"
        let option = ProviderModelOption(id: id, title: "Sonnet", contextWindow: "200K",
            contextWindowTokens: scenario == "similar-id" ? 900_000 : nil)
        let data = try JSONEncoder().encode([option])
        RemoteContextCatalogURLProtocol.handler = { _ in
            (scenario == "failed-catalog" ? 503 : 200, data)
        }
        defer { RemoteContextCatalogURLProtocol.handler = nil }
        let http = makeSession()
        defer { http.invalidateAndCancel() }
        let provider = try makeProvider(session: http)
        let name = "sloppy:claude-code:sonnet"
        _ = try await provider.createLanguageModel(for: name)
        // nil retains RuntimeSystem's existing configured fallback, rather than guessing 200K.
        #expect(provider.contextLimits(for: name) == nil)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteContextCatalogURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeProvider(session: URLSession) throws -> any ModelProvider {
        var config = CoreConfig.test
        config.models = [.init(title: "Remote", apiKey: "remote-only",
            apiUrl: "https://remote-context.test/v1", model: "claude-code:sonnet", providerCatalogId: "sloppy")]
        return try #require(CoreModelProviderFactory.buildModelProvider(config: config,
            resolvedModels: ["sloppy:claude-code:sonnet"], proxySession: session))
    }

}


private final class RemoteContextCatalogURLProtocol: URLProtocol, @unchecked Sendable {
    // The owning suite is serialized and each test resets this fixture.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (status, data) = try handler(request)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
