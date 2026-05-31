import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyLanguageModel
import Testing
@testable import PluginSDK
@testable import Protocols
@testable import sloppy

private final class OAuthTokenBox: @unchecked Sendable {
    var token: String
    var refreshCount = 0

    init(token: String) {
        self.token = token
    }
}

@Test
func coreModelProviderFactoryAcceptsOpenRouterPrefixedModel() {
    let model = CoreConfig.ModelConfig(
        title: "openrouter-main",
        apiKey: "",
        apiUrl: "",
        model: "openrouter:anthropic/claude-3.5-sonnet"
    )
    #expect(CoreModelProviderFactory.resolvedIdentifier(for: model) == "openrouter:anthropic/claude-3.5-sonnet")
}

@Test
func coreModelProviderFactoryInfersOpenRouterFromApiHost() {
    let model = CoreConfig.ModelConfig(
        title: "edge",
        apiKey: "sk-or-test",
        apiUrl: "https://openrouter.ai/api/v1",
        model: "openai/gpt-4o-mini"
    )
    #expect(CoreModelProviderFactory.resolvedIdentifier(for: model) == "openrouter:openai/gpt-4o-mini")
}

@Test
func coreModelProviderFactoryUsesExplicitOpenAIPrefixes() {
    let apiModel = CoreConfig.ModelConfig(
        title: "OpenAI API",
        apiKey: "sk-test",
        apiUrl: "https://api.openai.com/v1",
        model: "gpt-5.4-mini",
        providerCatalogId: "openai-api"
    )
    let oauthModel = CoreConfig.ModelConfig(
        title: "OpenAI Codex",
        apiKey: "",
        apiUrl: "https://chatgpt.com/backend-api",
        model: "gpt-5-codex-mini",
        providerCatalogId: "openai-oauth"
    )
    let legacyModel = CoreConfig.ModelConfig(
        title: "OpenAI",
        apiKey: "sk-test",
        apiUrl: "https://api.openai.com/v1",
        model: "openai:gpt-5.4-mini"
    )

    #expect(CoreModelProviderFactory.resolvedIdentifier(for: apiModel) == "openai-api:gpt-5.4-mini")
    #expect(CoreModelProviderFactory.resolvedIdentifier(for: oauthModel) == "openai-oauth:gpt-5-codex-mini")
    #expect(CoreModelProviderFactory.resolvedIdentifier(for: legacyModel) == nil)
}

@Test
func openCodeImporterParsesOpenAICompatibleProviderModels() {
    let config: [String: Any] = [
        "provider": [
            "company:models": [
                "name": "Company Models",
                "npm": "@ai-sdk/openai-compatible",
                "options": [
                    "baseURL": "https://models.example.com/v1",
                    "apiKey": "{env:COMPANY_MODELS_KEY}",
                ],
                "models": [
                    "fast-code": ["name": "Fast Code"],
                    "deep-code": ["name": "Deep Code"],
                ],
            ],
            "bedrock": [
                "npm": "@ai-sdk/amazon-bedrock",
                "models": [
                    "claude": ["name": "Claude"],
                ],
            ],
        ],
    ]

    let models = OpenCodeConfigImporter.parseModelConfigs(from: config)

    #expect(models.map(\.model) == [
        "opencode:company:models/deep-code",
        "opencode:company:models/fast-code",
    ])
    #expect(models.allSatisfy { $0.apiUrl == "https://models.example.com/v1" })
    #expect(models.allSatisfy { $0.providerCatalogId == "opencode:company:models" })
}

@Test
func coreModelProviderFactoryBuildsOpenCodeProvider() {
    var config = CoreConfig.test
    config.models = [
        CoreConfig.ModelConfig(
            title: "opencode:Company / Fast Code",
            apiKey: "company-key",
            apiUrl: "https://models.example.com/v1",
            model: "opencode:company/fast-code",
            providerCatalogId: "opencode:company"
        )
    ]

    let provider = CoreModelProviderFactory.buildModelProvider(
        config: config,
        resolvedModels: ["opencode:company/fast-code"]
    )

    #expect(provider?.supportedModels == ["opencode:company/fast-code"])
}

@Test
func geminiOAuthCredentialsLoadReadsGoogleOAuthFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-oauth-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("oauth_creds.json")
    try Data(
        """
        {
          "access_token": "oauth-token",
          "refresh_token": "refresh-token",
          "token_type": "Bearer",
          "expiry_date": 1893456000000
        }
        """.utf8
    ).write(to: url)

    let credentials = try #require(GeminiOAuthCredentials.load(url: url))
    #expect(credentials.accessToken == "oauth-token")
    #expect(credentials.refreshToken == "refresh-token")
    #expect(credentials.authorizationHeaderValue == "Bearer oauth-token")
}

@Test
func geminiOAuthCredentialsLoadReadsSloppyGoogleOAuthFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-sloppy-oauth-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("google_oauth.json")
    try Data(
        """
        {
          "access": "oauth-token",
          "refresh": "refresh-token|project-123|managed-456",
          "expires": 1893456000000,
          "email": "user@example.com"
        }
        """.utf8
    ).write(to: url)

    let credentials = try #require(GeminiOAuthCredentials.load(url: url))
    #expect(credentials.accessToken == "oauth-token")
    #expect(credentials.refreshToken == "refresh-token")
    #expect(credentials.expiryDate == Date(timeIntervalSince1970: 1_893_456_000))
    #expect(credentials.email == "user@example.com")
    #expect(credentials.projectID == "project-123")
    #expect(credentials.managedProjectID == "managed-456")
    #expect(credentials.isUsableForAntigravityCLI == true)
}

@Test
func geminiOAuthCredentialsLoadWorkspacePrefersSloppyFileOverLegacyFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-sloppy-oauth-precedence-\(UUID().uuidString)", isDirectory: true)
    let workspaceRoot = directory.appendingPathComponent(".sloppy", isDirectory: true)
    let authDirectory = workspaceRoot.appendingPathComponent("auth", isDirectory: true)
    try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)
    let sloppyURL = authDirectory.appendingPathComponent("gemini-oauth-auth.json")
    try Data(
        """
        {
          "access": "sloppy-token",
          "refresh": "sloppy-refresh|project-123|managed-456",
          "expires": 1893456000000,
          "email": "user@example.com"
        }
        """.utf8
    ).write(to: sloppyURL)
    let legacyURL = directory.appendingPathComponent("legacy-oauth-creds.json")
    try Data(
        """
        {
          "access_token": "legacy-token",
          "refresh_token": "legacy-refresh",
          "token_type": "Bearer",
          "expiry_date": 1893456000000
        }
        """.utf8
    ).write(to: legacyURL)

    let credentials = try #require(GeminiOAuthCredentials.load(workspaceRootURL: workspaceRoot, legacyURL: legacyURL))
    #expect(credentials.accessToken == "sloppy-token")
    #expect(credentials.refreshToken == "sloppy-refresh")
    #expect(credentials.projectID == "project-123")
}

@Test
func geminiOAuthCredentialsLoadAcceptsRefreshTokenOnlyCLIFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-oauth-refresh-only-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("oauth_creds.json")
    try Data(
        """
        {
          "access_token": "",
          "scope": "https://www.googleapis.com/auth/cloud-platform",
          "token_type": "Bearer",
          "id_token": "",
          "expiry_date": 1778105904231,
          "refresh_token": "refresh-token"
        }
        """.utf8
    ).write(to: url)

    let credentials = try #require(GeminiOAuthCredentials.load(url: url))
    #expect(credentials.accessToken == "")
    #expect(credentials.refreshToken == "refresh-token")
    #expect(credentials.scope == "https://www.googleapis.com/auth/cloud-platform")
    #expect(credentials.isUsableForAntigravityCLI == true)
}

@Test
func geminiOAuthCredentialsRefreshWritesSloppyPackedCredentialsAndPreservesProjectIDs() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-sloppy-oauth-refresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("google_oauth.json")
    try Data(
        """
        {
          "access": "expired-token",
          "refresh": "refresh-token|project-123|managed-456",
          "expires": 946684800000,
          "email": "user@example.com"
        }
        """.utf8
    ).write(to: url)

    let credentials = try #require(GeminiOAuthCredentials.load(url: url))
    let refreshed = try await credentials.refreshedIfNeeded(
        url: url,
        now: Date(timeIntervalSince1970: 1_800_000_000),
        transport: { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("grant_type=refresh_token"))
            #expect(body.contains("refresh_token=refresh-token"))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                """
                {
                  "access_token": "fresh-token",
                  "refresh_token": "rotated-refresh-token",
                  "expires_in": 3600,
                  "token_type": "Bearer"
                }
                """.utf8
            )
            return (data, response)
        }
    )

    #expect(refreshed.accessToken == "fresh-token")
    #expect(refreshed.refreshToken == "rotated-refresh-token")
    #expect(refreshed.projectID == "project-123")
    #expect(refreshed.managedProjectID == "managed-456")
    let storedObject = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(storedObject["access"] as? String == "fresh-token")
    #expect(storedObject["refresh"] as? String == "rotated-refresh-token|project-123|managed-456")
    #expect(storedObject["email"] as? String == "user@example.com")
}

@Test
func geminiOAuthCredentialsRefreshInvalidGrantClearsSloppyCredentials() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-sloppy-oauth-invalid-grant-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("google_oauth.json")
    try Data(
        """
        {
          "access": "expired-token",
          "refresh": "refresh-token",
          "expires": 946684800000,
          "email": "user@example.com"
        }
        """.utf8
    ).write(to: url)

    let credentials = try #require(GeminiOAuthCredentials.load(url: url))
    do {
        _ = try await credentials.refreshedIfNeeded(
            url: url,
            now: Date(timeIntervalSince1970: 1_800_000_000),
            transport: { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (Data(#"{"error":"invalid_grant"}"#.utf8), response)
            }
        )
        Issue.record("Expected invalid_grant refresh to fail.")
    } catch let error as GeminiOAuthCredentialsError {
        #expect(error.isInvalidGrant == true)
    }

    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test
func geminiOAuthCredentialsRejectsUnrelatedScopesForAntigravityCLI() throws {
    let credentials = GeminiOAuthCredentials(
        accessToken: "oauth-token",
        refreshToken: "refresh-token",
        tokenType: "Bearer",
        expiryDate: nil,
        scope: "https://www.googleapis.com/auth/drive.readonly"
    )

    #expect(credentials.isUsableForAntigravityCLI == false)
}

@Test
func geminiOAuthCredentialsRefreshesExpiredCLIFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-oauth-refresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("oauth_creds.json")
    try Data(
        """
        {
          "access_token": "expired-token",
          "scope": "https://www.googleapis.com/auth/cloud-platform",
          "token_type": "Bearer",
          "expiry_date": 946684800000,
          "refresh_token": "refresh-token"
        }
        """.utf8
    ).write(to: url)

    let bodyBox = OAuthTokenBox(token: "")
    let credentials = try #require(GeminiOAuthCredentials.load(url: url))
    let refreshed = try await credentials.refreshedIfNeeded(
        url: url,
        now: Date(timeIntervalSince1970: 1_800_000_000),
        transport: { request in
            bodyBox.token = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                """
                {
                  "access_token": "fresh-token",
                  "expires_in": 3600,
                  "token_type": "Bearer",
                  "scope": "https://www.googleapis.com/auth/cloud-platform"
                }
                """.utf8
            )
            return (data, response)
        }
    )

    #expect(bodyBox.token.contains("grant_type=refresh_token"))
    #expect(bodyBox.token.contains("refresh_token=refresh-token"))
    #expect(refreshed.accessToken == "fresh-token")
    #expect(refreshed.refreshToken == "refresh-token")
    let stored = try #require(GeminiOAuthCredentials.load(url: url))
    #expect(stored.accessToken == "fresh-token")
    #expect(stored.refreshToken == "refresh-token")
}

@Test
func coreModelProviderFactoryBuildsGeminiFromOAuthCredentialsWithoutAPIKey() {
    var config = CoreConfig.test
    config.models = [
        CoreConfig.ModelConfig(
            title: "gemini",
            apiKey: "",
            apiUrl: "https://generativelanguage.googleapis.com",
            model: "gemini-2.5-flash",
            providerCatalogId: "gemini"
        )
    ]
    let provider = CoreModelProviderFactory.buildModelProvider(
        config: config,
        resolvedModels: ["gemini:gemini-2.5-flash"],
        geminiOAuthCredentialsProvider: {
            GeminiOAuthCredentials(
                accessToken: "oauth-token",
                refreshToken: nil,
                tokenType: "Bearer",
                expiryDate: nil
            )
        }
    )

    #expect(provider?.supportedModels == ["gemini:gemini-2.5-flash"])
}

@Test
func coreModelProviderFactoryBuildsGeminiFromSloppyWorkspaceOAuthCredentials() throws {
    let currentDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-workspace-oauth-\(UUID().uuidString)", isDirectory: true)
    let workspaceRoot = currentDirectory.appendingPathComponent(".sloppy", isDirectory: true)
    let authDirectory = workspaceRoot.appendingPathComponent("auth", isDirectory: true)
    try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)
    try Data(
        """
        {
          "access": "oauth-token",
          "refresh": "refresh-token|project-123|managed-456",
          "expires": 1893456000000,
          "email": "user@example.com"
        }
        """.utf8
    ).write(to: authDirectory.appendingPathComponent("gemini-oauth-auth.json"))

    var config = CoreConfig.test
    config.workspace.basePath = currentDirectory.path
    config.workspace.name = ".sloppy"
    config.models = [
        CoreConfig.ModelConfig(
            title: "gemini",
            apiKey: "",
            apiUrl: "https://generativelanguage.googleapis.com",
            model: "gemini-2.5-flash",
            providerCatalogId: "gemini"
        )
    ]

    let provider = CoreModelProviderFactory.buildModelProvider(
        config: config,
        resolvedModels: ["gemini:gemini-2.5-flash"],
        currentDirectory: currentDirectory.path
    )

    #expect(provider?.supportedModels == ["gemini:gemini-2.5-flash"])
}

@Test
func coreModelProviderFactorySurfacesAntigravityCredentialsWithoutRequiredScope() async throws {
    var config = CoreConfig.test
    config.models = [
        CoreConfig.ModelConfig(
            title: "gemini",
            apiKey: "",
            apiUrl: "https://generativelanguage.googleapis.com",
            model: "gemini-2.5-flash",
            providerCatalogId: "gemini"
        )
    ]
    let provider = CoreModelProviderFactory.buildModelProvider(
        config: config,
        resolvedModels: ["gemini:gemini-2.5-flash"],
        geminiOAuthCredentialsProvider: {
            GeminiOAuthCredentials(
                accessToken: "oauth-token",
                refreshToken: nil,
                tokenType: "Bearer",
                expiryDate: nil,
                scope: "https://www.googleapis.com/auth/drive.readonly"
            )
        }
    )

    let geminiProvider = try #require(provider)
    #expect(geminiProvider.supportedModels == ["gemini:gemini-2.5-flash"])
    do {
        _ = try await geminiProvider.createLanguageModel(for: "gemini:gemini-2.5-flash")
        Issue.record("Expected Antigravity CLI OAuth scope validation to fail.")
    } catch let error as GeminiOAuthCredentialsError {
        #expect(error.localizedDescription.contains(GeminiOAuthCredentials.requiredAntigravityScope))
    }
}

@Test
func coreModelProviderFactoryAllowsGeminiConfiguredKeyWhenOAuthScopeIsMissing() {
    var config = CoreConfig.test
    config.models = [
        CoreConfig.ModelConfig(
            title: "gemini",
            apiKey: "configured-key",
            apiUrl: "https://generativelanguage.googleapis.com",
            model: "gemini-2.5-flash",
            providerCatalogId: "gemini"
        )
    ]
    let provider = CoreModelProviderFactory.buildModelProvider(
        config: config,
        resolvedModels: ["gemini:gemini-2.5-flash"],
        geminiOAuthCredentialsProvider: {
            GeminiOAuthCredentials(
                accessToken: "oauth-token",
                refreshToken: nil,
                tokenType: "Bearer",
                expiryDate: nil,
                scope: "https://www.googleapis.com/auth/cloud-platform"
            )
        }
    )

    #expect(provider?.supportedModels == ["gemini:gemini-2.5-flash"])
}

@Test
func openAIModelProviderResponsesModeUsesOpenAIResponsesVariant() async throws {
    let provider = OpenAIModelProvider(
        supportedModels: ["openrouter:openai/gpt-4o-mini"],
        settings: .init(
            apiKey: { "sk-or-test" },
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            session: URLSession.shared,
            modelIdentifierPrefix: "openrouter:",
            useOpenAICodexOAuthPath: false,
            allowResponsesAPIFallback: false,
            useOpenResponsesLanguageModel: true
        )
    )

    let languageModel = try await provider.createLanguageModel(for: "openrouter:openai/gpt-4o-mini")
    let openAIModel = try #require(languageModel as? OpenAILanguageModel)
    #expect(openAIModel.apiVariant == .responses)
}

@Test
func openAIModelProviderUsesDynamicOAuthTokenWhenCodexSessionIsCached() async throws {
    let box = OAuthTokenBox(token: "stale-oauth-token")
    let provider = OpenAIModelProvider(
        supportedModels: ["openai-oauth:gpt-5-codex-mini"],
        settings: .init(
            apiKey: { box.token },
            refreshTokenIfNeeded: {
                box.refreshCount += 1
                box.token = "fresh-oauth-token"
            },
            modelIdentifierPrefix: "openai-oauth:",
            useOpenAICodexOAuthPath: true
        )
    )

    let languageModel = try await provider.createLanguageModel(for: "openai-oauth:gpt-5-codex-mini")
    let oauthModel = try #require(languageModel as? OpenAIOAuthModel)
    let request = try await oauthModel.buildHTTPRequestForTesting(body: Data())

    #expect(box.refreshCount == 1)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-oauth-token")
}

@Test
func openAIOAuthConfigPrefersOAuthTokenProviderOverAPIKey() async throws {
    var config = CoreConfig.test
    config.models = [
        CoreConfig.ModelConfig(
            title: "openai-oauth",
            apiKey: "sk-proj-static-key",
            apiUrl: "https://chatgpt.com/backend-api",
            model: "gpt-5.4",
            providerCatalogId: "openai-oauth"
        )
    ]

    let builtProvider = CoreModelProviderFactory.buildModelProvider(
        config: config,
        resolvedModels: ["openai-oauth:gpt-5.4"],
        oauthTokenProvider: { "oauth-access-token" },
        oauthAccountId: "acct_test"
    )
    let provider = try #require(builtProvider)
    let languageModel = try await provider.createLanguageModel(for: "openai-oauth:gpt-5.4")
    let oauthModel = try #require(languageModel as? OpenAIOAuthModel)
    let request = try await oauthModel.buildHTTPRequestForTesting(body: Data())

    #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/codex/responses")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-access-token")
    #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct_test")
}

@Test
func availableAgentModelsIncludesCachedOpenAIOAuthCatalog() async throws {
    var config = CoreConfig.test
    config.models = []
    config.disableModelInference = false

    let workspaceRootURL = config.resolvedWorkspaceRootURL(
        currentDirectory: FileManager.default.currentDirectoryPath
    )
    let authDirectoryURL = workspaceRootURL.appendingPathComponent("auth", isDirectory: true)
    try FileManager.default.createDirectory(at: authDirectoryURL, withIntermediateDirectories: true)
    try Data(
        """
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": null,
          "tokens": {
            "access_token": "oauth-token",
            "account_id": "acct_test"
          },
          "last_refresh": "2026-05-07T00:00:00Z"
        }
        """.utf8
    ).write(to: authDirectoryURL.appendingPathComponent("openai-oauth-auth.json"))

    let service = CoreService(
        config: config,
        persistenceBuilder: InMemoryCorePersistenceBuilder()
    )
    await service.cacheOAuthModels([
        ProviderModelOption(
            id: "gpt-5.5",
            title: "GPT-5.5",
            contextWindow: "272K",
            capabilities: ["tools"]
        )
    ])

    let models = await service.availableAgentModels()
    let cached = models.first { $0.id == "openai-oauth:gpt-5.5" }
    #expect(cached?.title == "GPT-5.5")
    #expect(cached?.contextWindow == "272K")
}

@Test
func geminiOAuthURLProtocolRewritesAPIKeyHeaderToBearerAuth() throws {
    var request = URLRequest(url: try #require(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini:generateContent")))
    request.setValue("oauth-token", forHTTPHeaderField: "x-goog-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(
        """
        {
          "contents": [
            { "role": "user", "parts": [{ "text": "Hello" }] }
          ]
        }
        """.utf8
    )

    let modified = try GeminiOAuthURLProtocol.modifiedRequest(
        from: request,
        projectID: "project-123",
        requestID: "request-123"
    )

    #expect(modified.value(forHTTPHeaderField: "x-goog-api-key") == nil)
    #expect(modified.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
    #expect(modified.url?.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal:generateContent")
    #expect(modified.value(forHTTPHeaderField: "User-Agent") == "antigravity")
    let body = try #require(modified.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["project"] as? String == "project-123")
    #expect(object["model"] as? String == "gemini")
    #expect(object["userAgent"] as? String == "antigravity")
    #expect(object["requestId"] as? String == "request-123")
    let nestedRequest = try #require(object["request"] as? [String: Any])
    #expect(nestedRequest["contents"] != nil)
}

@Test
func geminiOAuthURLProtocolRewritesStreamingRequestsToAntigravitySSE() throws {
    var request = URLRequest(url: try #require(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse")))
    request.setValue("oauth-token", forHTTPHeaderField: "x-goog-api-key")
    request.httpBody = Data(#"{ "contents": [] }"#.utf8)

    let modified = try GeminiOAuthURLProtocol.modifiedRequest(
        from: request,
        projectID: "project-123",
        requestID: "request-123"
    )

    #expect(modified.url?.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse")
    #expect(modified.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    let body = try #require(modified.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["model"] as? String == "gemini-2.5-flash")
}

@Test
func geminiOAuthURLProtocolUnwrapsAntigravityResponseBody() throws {
    let wrapped = Data(
        """
        {
          "response": {
            "candidates": [
              {
                "content": {
                  "role": "model",
                  "parts": [{ "text": "Hello" }]
                }
              }
            ]
          },
          "traceId": "trace-123"
        }
        """.utf8
    )

    let unwrapped = try GeminiOAuthURLProtocol.responseBodyForGeminiParser(from: wrapped)
    let object = try #require(JSONSerialization.jsonObject(with: unwrapped) as? [String: Any])
    #expect(object["candidates"] != nil)
    #expect(object["traceId"] == nil)
}

@Test
func sloppyExtraCertificateAuthorityExtractsMultiplePEMCertificates() {
    let first = Data([0x01, 0x02, 0x03]).base64EncodedString()
    let second = Data([0x04, 0x05, 0x06]).base64EncodedString()
    let pem =
        """
        -----BEGIN CERTIFICATE-----
        \(first)
        -----END CERTIFICATE-----
        -----BEGIN CERTIFICATE-----
        \(second)
        -----END CERTIFICATE-----
        """

    let certificates = SloppyExtraCertificateAuthority.certificateData(fromPEM: pem)

    #expect(certificates == [Data([0x01, 0x02, 0x03]), Data([0x04, 0x05, 0x06])])
}
