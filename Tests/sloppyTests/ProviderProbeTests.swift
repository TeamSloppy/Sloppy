import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import sloppy
@testable import Protocols

private func makeProbeHTTPResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}

private final class ProbeRequestCounter: @unchecked Sendable {
    var count = 0
}

@Test
func providerProbeEndpointReturnsFailureWhenOpenAIKeyIsMissing() async throws {
    let config = CoreConfig.test
    let service = CoreService(
        config: config,
        providerProbeService: ProviderProbeService(
            environmentLookup: { _ in nil },
            transport: { request in
                Issue.record("Transport should not be used when OpenAI key is missing.")
                return (Data(), makeProbeHTTPResponse(url: request.url!))
            }
        ),
        builtInGatewayPluginFactory: .live
    )
    let router = CoreRouter(service: service)

    let body = try JSONEncoder().encode(
        ProviderProbeRequest(
            providerId: .openAIAPI,
            apiUrl: "https://api.openai.com/v1"
        )
    )
    let response = await router.handle(method: "POST", path: "/v1/providers/probe", body: body)

    #expect(response.status == 200)
    let payload = try JSONDecoder().decode(ProviderProbeResponse.self, from: response.body)
    #expect(payload.providerId == ProviderProbeID.openAIAPI)
    #expect(payload.ok == false)
    #expect(payload.models.isEmpty)
}

@Test
func providerProbeEndpointReturnsFriendlyFailureWhenOAuthIsNotConnected() async throws {
    let config = CoreConfig.test
    let service = CoreService(
        config: config,
        builtInGatewayPluginFactory: .live
    )
    let router = CoreRouter(service: service)

    let body = try JSONEncoder().encode(
        ProviderProbeRequest(
            providerId: .openAIOAuth,
            apiUrl: "https://chatgpt.com/backend-api"
        )
    )
    let response = await router.handle(method: "POST", path: "/v1/providers/probe", body: body)

    #expect(response.status == 200)
    let payload = try JSONDecoder().decode(ProviderProbeResponse.self, from: response.body)
    #expect(payload.providerId == ProviderProbeID.openAIOAuth)
    #expect(payload.ok == false)
    #expect(payload.models.isEmpty)
    #expect(payload.message == "Failed to connect to OpenAI OAuth: OpenAI OAuth is not connected yet. Start sign-in first.")
}

@Test
func providerProbeEndpointMapsOllamaModelsFromTagsResponse() async throws {
    let config = CoreConfig.test
    let service = CoreService(
        config: config,
        providerProbeService: ProviderProbeService(
            transport: { request in
                let payload =
                    """
                    {
                      "models": [
                        { "name": "qwen3:latest" },
                        { "name": "llama3.2" }
                      ]
                    }
                    """
                return (Data(payload.utf8), makeProbeHTTPResponse(url: request.url!))
            }
        ),
        builtInGatewayPluginFactory: .live
    )
    let router = CoreRouter(service: service)

    let body = try JSONEncoder().encode(
        ProviderProbeRequest(
            providerId: .ollama,
            apiUrl: "http://127.0.0.1:11434"
        )
    )
    let response = await router.handle(method: "POST", path: "/v1/providers/probe", body: body)

    #expect(response.status == 200)
    let payload = try JSONDecoder().decode(ProviderProbeResponse.self, from: response.body)
    #expect(payload.providerId == ProviderProbeID.ollama)
    #expect(payload.ok == true)
    #expect(payload.models.map { $0.id } == ["llama3.2", "qwen3:latest"])
    #expect(payload.models.map { $0.title } == ["llama3.2", "qwen3"])
}

@Test
func providerProbeEndpointRejectsInvalidProviderID() async throws {
    let router = CoreRouter(service: CoreService(config: .test))
    let body = Data(#"{"providerId":"invalid-provider"}"#.utf8)
    let response = await router.handle(method: "POST", path: "/v1/providers/probe", body: body)

    #expect(response.status == 400)
}

@Test
func providerProbeOpenAIListsModelsWithoutKeyOnPrivateLAN() async throws {
    let config = CoreConfig.test
    let service = CoreService(
        config: config,
        providerProbeService: ProviderProbeService(
            environmentLookup: { _ in nil },
            transport: { request in
                let path = request.url?.path ?? ""
                #expect(path.hasSuffix("/v1/models"))
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                let payload = #"{"data":[{"id":"lm-studio-model"}]}"#
                return (Data(payload.utf8), makeProbeHTTPResponse(url: request.url!))
            }
        ),
        builtInGatewayPluginFactory: .live
    )
    let router = CoreRouter(service: service)

    let body = try JSONEncoder().encode(
        ProviderProbeRequest(
            providerId: .openAIAPI,
            apiUrl: "http://192.168.3.43:1234"
        )
    )
    let response = await router.handle(method: "POST", path: "/v1/providers/probe", body: body)

    #expect(response.status == 200)
    let payload = try JSONDecoder().decode(ProviderProbeResponse.self, from: response.body)
    #expect(payload.providerId == ProviderProbeID.openAIAPI)
    #expect(payload.ok == true)
    #expect(payload.models.map(\.id) == ["lm-studio-model"])
}

@Test
func providerProbeGeminiPrefersRequestAPIKeyOverOAuthCredentialsFile() async throws {
    let service = ProviderProbeService(
        environmentLookup: { key in
            key == "GEMINI_API_KEY" ? "env-api-key" : nil
        },
        transport: { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.url?.query?.contains("key=request-api-key") == true)
            let payload =
                """
                {
                  "models": [
                    { "name": "models/gemini-2.5-flash", "displayName": "Gemini 2.5 Flash" }
                  ]
                }
                """
            return (Data(payload.utf8), makeProbeHTTPResponse(url: request.url!))
        },
        geminiOAuthCredentialsProvider: {
            GeminiOAuthCredentials(
                accessToken: "oauth-access-token",
                refreshToken: nil,
                tokenType: "Bearer",
                expiryDate: nil,
                scope: "https://www.googleapis.com/auth/cloud-platform"
            )
        }
    )

    let response = await service.probe(
        config: .test,
        request: ProviderProbeRequest(
            providerId: .gemini,
            apiKey: "request-api-key",
            apiUrl: "https://generativelanguage.googleapis.com"
        )
    )

    #expect(response.ok == true)
    #expect(response.usedEnvironmentKey == false)
    #expect(response.message == "Connected to Gemini with API key. Loaded 1 models.")
    #expect(response.models.map(\.id) == ["gemini-2.5-flash"])
}

@Test
func providerProbeGeminiUsesAntigravityModelsForOAuthCredentials() async throws {
    let seenRequests = ProbeRequestCounter()
    let service = ProviderProbeService(
        transport: { request in
            seenRequests.count += 1
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-access-token")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "antigravity")
            if request.url?.absoluteString == "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist" {
                let body = try #require(request.httpBody)
                let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(object["cloudaicompanionProject"] == nil)
                let metadata = try #require(object["metadata"] as? [String: Any])
                #expect(metadata["ideType"] as? String == "ANTIGRAVITY")
                #expect((metadata["platform"] as? String)?.contains("_") == true)
                #expect(metadata["platform"] as? String != "MACOS")
                #expect(metadata["pluginType"] as? String == "GEMINI")
                let payload =
                    """
                    {
                      "cloudaicompanionProject": "companion-project-123"
                    }
                """
                return (Data(payload.utf8), makeProbeHTTPResponse(url: request.url!))
            }
            #expect(request.url?.absoluteString == "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")
            let body = try #require(request.httpBody)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["project"] as? String == "companion-project-123")
            let payload =
                """
                {
                  "models": {
                    "gemini-3-pro-low": { "displayName": "Gemini 3 Pro Low" },
                    "chat_20706": { "displayName": "Internal", "isInternal": true }
                  }
                }
                """
            return (Data(payload.utf8), makeProbeHTTPResponse(url: request.url!))
        },
        geminiOAuthCredentialsProvider: {
            GeminiOAuthCredentials(
                accessToken: "oauth-access-token",
                refreshToken: nil,
                tokenType: "Bearer",
                expiryDate: nil,
                scope: "https://www.googleapis.com/auth/cloud-platform"
            )
        }
    )

    let response = await service.probe(
        config: .test,
        request: ProviderProbeRequest(
            providerId: .gemini,
            apiUrl: "https://generativelanguage.googleapis.com"
        )
    )

    #expect(response.ok == true)
    #expect(response.message == "Connected to Gemini with Antigravity CLI OAuth. Loaded 1 models.")
    #expect(response.models.map(\.id) == ["gemini-3-pro-low"])
    #expect(seenRequests.count == 2)
}

@Test
func providerProbeGeminiRejectsOAuthCredentialsWithoutAntigravityScope() async throws {
    let service = ProviderProbeService(
        transport: { request in
            Issue.record("Unexpected Gemini probe request: \(request)")
            return (Data(), makeProbeHTTPResponse(url: request.url!, statusCode: 500))
        },
        geminiOAuthCredentialsProvider: {
            GeminiOAuthCredentials(
                accessToken: "oauth-access-token",
                refreshToken: nil,
                tokenType: "Bearer",
                expiryDate: nil,
                scope: "https://www.googleapis.com/auth/drive.readonly"
            )
        }
    )

    let response = await service.probe(
        config: .test,
        request: ProviderProbeRequest(
            providerId: .gemini,
            apiUrl: "https://generativelanguage.googleapis.com"
        )
    )

    #expect(response.ok == false)
    #expect(response.message.contains(GeminiOAuthCredentials.requiredAntigravityScope))
    #expect(response.models.isEmpty)
}
