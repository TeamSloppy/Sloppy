import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@testable import PluginSDK

@Suite(.serialized)
struct OllamaContextLimitsTests {
    private let cloudTags = #"{"models":[{"name":"model:cloud","remote_host":"https://ollama.com","remote_model":"model"}]}"#
    private let cloudInfo = #"{"model_info":{"general.architecture":"test","test.context_length":262144}}"#

    @Test func cloudDiscoveryPrecedesBudgetAndIsSharedWithUsageObservedModels() async throws {
        OllamaContextURLProtocol.handler = { [cloudTags, cloudInfo] request in
            switch request.url?.path {
            case "/api/tags":
                #expect(request.httpMethod == "GET")
                return (200, cloudTags)
            case "/api/show":
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
                return (200, cloudInfo)
            default: throw URLError(.badURL)
            }
        }
        defer { OllamaContextURLProtocol.handler = nil }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let provider = makeProvider(session)
        #expect(provider.contextLimits(for: "ollama:model:cloud") == nil)
        _ = try await provider.createLanguageModel(for: "ollama:model:cloud", usageContext: .init(
            channelId: "channel", provider: "ollama", model: "model:cloud", onRequest: { _ in
                Issue.record("Metadata discovery must not be recorded as model inference")
            }))
        let limits = try #require(provider.contextLimits(for: "ollama:model:cloud"))
        #expect(limits.contextWindowTokens == 262_144)
        #expect(limits.inputBudget(reserving: 1_024) == 261_120)
        #expect(provider.contextLimits(for: "ollama:model:other") == nil)
        OllamaContextURLProtocol.handler = { _ in
            Issue.record("A cached model should not fetch metadata again")
            throw URLError(.badURL)
        }
        _ = try await provider.createLanguageModel(for: "ollama:model:cloud")
    }

    @Test func localModelsKeepFallbackEvenWhenTheirNameLooksLikeCloud() async throws {
        OllamaContextURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/tags")
            return (200, #"{"models":[{"name":"model:cloud"}]}"#)
        }
        defer { OllamaContextURLProtocol.handler = nil }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let provider = makeProvider(session)
        _ = try await provider.createLanguageModel(for: "ollama:model:cloud")
        #expect(provider.contextLimits(for: "ollama:model:cloud") == nil)
    }

    @Test(arguments: ["missing", "negative", "fractional", "wrong-architecture", "failed-tags", "failed-show", "different-model"])
    func unavailableOrInvalidMetadataKeepsInferenceAvailable(scenario: String) async throws {
        OllamaContextURLProtocol.handler = { [cloudTags, cloudInfo] request in
            if request.url?.path == "/api/tags" {
                if scenario == "different-model" {
                    return (200, #"{"models":[{"name":"model:other","remote_host":"https://ollama.com","remote_model":"model"}]}"#)
                }
                return (scenario == "failed-tags" ? 503 : 200, cloudTags)
            }
            let info: String
            switch scenario {
            case "failed-show": info = cloudInfo
            case "negative": info = #"{"model_info":{"general.architecture":"test","test.context_length":-1}}"#
            case "fractional": info = #"{"model_info":{"general.architecture":"test","test.context_length":262144.5}}"#
            case "wrong-architecture": info = #"{"model_info":{"general.architecture":"test","other.context_length":262144}}"#
            default: info = #"{"model_info":{}}"#
            }
            return (scenario == "failed-show" ? 503 : 200, info)
        }
        defer { OllamaContextURLProtocol.handler = nil }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let provider = makeProvider(session)
        _ = try await provider.createLanguageModel(for: "ollama:model:cloud")
        #expect(provider.contextLimits(for: "ollama:model:cloud") == nil)
    }

    @Test func configuredWindowStillOverridesDiscovery() async throws {
        OllamaContextURLProtocol.handler = { [cloudTags, cloudInfo] request in
            (200, request.url?.path == "/api/tags" ? cloudTags : cloudInfo)
        }
        defer { OllamaContextURLProtocol.handler = nil }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let provider = ContextLimitedModelProvider(wrapping: makeProvider(session),
            limits: ["ollama:model:cloud": .init(contextWindowTokens: 8_192)])
        _ = try await provider.createLanguageModel(for: "ollama:model:cloud")
        #expect(provider.contextLimits(for: "ollama:model:cloud")?.contextWindowTokens == 8_192)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaContextURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeProvider(_ session: URLSession) -> OllamaModelProvider {
        OllamaModelProvider(supportedModels: ["ollama:model:cloud"],
            baseURL: URL(string: "https://ollama-context.test")!, session: session)
    }
}

private final class OllamaContextURLProtocol: URLProtocol, @unchecked Sendable {
    // The suite serializes access and clears the fixture after each test.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (status, body) = try handler(request)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
