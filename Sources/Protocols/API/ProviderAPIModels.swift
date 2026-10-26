import Foundation

public enum ProviderAuthMethod: String, Codable, Sendable {
    case apiKey = "api_key"
    case deeplink
}

public enum ProviderProbeID: String, Codable, Sendable {
    case sloppy
    case openAIAPI = "openai-api"
    case openAIOAuth = "openai-oauth"
    case openRouter = "openrouter"
    case ollama
    case gemini
    case anthropic
    case anthropicOAuth = "anthropic-oauth"
    case claudeCode = "claude-code"
}

public struct ProviderProbeRequest: Codable, Sendable {
    public var providerId: ProviderProbeID
    public var apiKey: String?
    public var apiUrl: String?

    public init(providerId: ProviderProbeID, apiKey: String? = nil, apiUrl: String? = nil) {
        self.providerId = providerId
        self.apiKey = apiKey
        self.apiUrl = apiUrl
    }
}

public struct OpenAIProviderModelsRequest: Codable, Sendable {
    public var authMethod: ProviderAuthMethod
    public var apiKey: String?
    public var apiUrl: String?

    public init(authMethod: ProviderAuthMethod, apiKey: String? = nil, apiUrl: String? = nil) {
        self.authMethod = authMethod
        self.apiKey = apiKey
        self.apiUrl = apiUrl
    }
}

public struct ProviderModelOption: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var contextWindow: String?
    public var capabilities: [String]
    /// Exact provider-reported window; the display label may be rounded.
    public var contextWindowTokens: Int?
    public var maxInputTokens: Int?
    public var maxOutputTokens: Int?

    public init(
        id: String,
        title: String,
        contextWindow: String? = nil,
        capabilities: [String] = [],
        contextWindowTokens: Int? = nil,
        maxInputTokens: Int? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.contextWindow = contextWindow
        self.capabilities = capabilities
        self.contextWindowTokens = contextWindowTokens
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct OpenAIProviderModelsResponse: Codable, Sendable {
    public var provider: String
    public var authMethod: ProviderAuthMethod
    public var usedEnvironmentKey: Bool
    public var source: String
    public var warning: String?
    public var models: [ProviderModelOption]

    public init(
        provider: String,
        authMethod: ProviderAuthMethod,
        usedEnvironmentKey: Bool,
        source: String,
        warning: String?,
        models: [ProviderModelOption]
    ) {
        self.provider = provider
        self.authMethod = authMethod
        self.usedEnvironmentKey = usedEnvironmentKey
        self.source = source
        self.warning = warning
        self.models = models
    }
}

public struct OpenAIProviderStatusResponse: Codable, Sendable {
    public var provider: String
    public var hasEnvironmentKey: Bool
    public var hasConfiguredKey: Bool
    public var hasAnyKey: Bool
    public var hasOAuthCredentials: Bool
    public var oauthAccountId: String?
    public var oauthPlanType: String?
    public var oauthExpiresAt: String?

    public init(
        provider: String,
        hasEnvironmentKey: Bool,
        hasConfiguredKey: Bool,
        hasAnyKey: Bool,
        hasOAuthCredentials: Bool = false,
        oauthAccountId: String? = nil,
        oauthPlanType: String? = nil,
        oauthExpiresAt: String? = nil
    ) {
        self.provider = provider
        self.hasEnvironmentKey = hasEnvironmentKey
        self.hasConfiguredKey = hasConfiguredKey
        self.hasAnyKey = hasAnyKey
        self.hasOAuthCredentials = hasOAuthCredentials
        self.oauthAccountId = oauthAccountId
        self.oauthPlanType = oauthPlanType
        self.oauthExpiresAt = oauthExpiresAt
    }
}

public struct AnthropicProviderStatusResponse: Codable, Sendable {
    public var provider: String
    public var hasEnvironmentKey: Bool
    public var hasConfiguredKey: Bool
    public var hasAnyKey: Bool
    public var hasOAuthCredentials: Bool
    public var oauthSource: String?
    public var oauthExpiresAt: String?
    public var oauthRefreshable: Bool

    public init(
        provider: String,
        hasEnvironmentKey: Bool,
        hasConfiguredKey: Bool,
        hasAnyKey: Bool,
        hasOAuthCredentials: Bool = false,
        oauthSource: String? = nil,
        oauthExpiresAt: String? = nil,
        oauthRefreshable: Bool = false
    ) {
        self.provider = provider
        self.hasEnvironmentKey = hasEnvironmentKey
        self.hasConfiguredKey = hasConfiguredKey
        self.hasAnyKey = hasAnyKey
        self.hasOAuthCredentials = hasOAuthCredentials
        self.oauthSource = oauthSource
        self.oauthExpiresAt = oauthExpiresAt
        self.oauthRefreshable = oauthRefreshable
    }
}

public struct GeminiProviderStatusResponse: Codable, Sendable {
    public var provider: String
    public var hasEnvironmentKey: Bool
    public var hasConfiguredKey: Bool
    public var hasAnyKey: Bool
    public var hasOAuthCredentials: Bool
    public var oauthEmail: String?
    public var oauthExpiresAt: String?

    public init(
        provider: String = "gemini",
        hasEnvironmentKey: Bool = false,
        hasConfiguredKey: Bool = false,
        hasAnyKey: Bool = false,
        hasOAuthCredentials: Bool = false,
        oauthEmail: String? = nil,
        oauthExpiresAt: String? = nil
    ) {
        self.provider = provider
        self.hasEnvironmentKey = hasEnvironmentKey
        self.hasConfiguredKey = hasConfiguredKey
        self.hasAnyKey = hasAnyKey
        self.hasOAuthCredentials = hasOAuthCredentials
        self.oauthEmail = oauthEmail
        self.oauthExpiresAt = oauthExpiresAt
    }
}

public struct OpenAIOAuthStartRequest: Codable, Sendable {
    public var redirectURI: String

    public init(redirectURI: String) {
        self.redirectURI = redirectURI
    }
}

public struct OpenAIOAuthStartResponse: Codable, Sendable {
    public var authorizationURL: String
    public var redirectURI: String
    public var state: String

    public init(authorizationURL: String, redirectURI: String, state: String) {
        self.authorizationURL = authorizationURL
        self.redirectURI = redirectURI
        self.state = state
    }
}

public struct OpenAIOAuthCompleteRequest: Codable, Sendable {
    public var callbackURL: String?
    public var code: String?
    public var state: String?

    public init(callbackURL: String? = nil, code: String? = nil, state: String? = nil) {
        self.callbackURL = callbackURL
        self.code = code
        self.state = state
    }
}

public struct OpenAIOAuthCompleteResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var accountId: String?
    public var planType: String?

    public init(ok: Bool, message: String, accountId: String? = nil, planType: String? = nil) {
        self.ok = ok
        self.message = message
        self.accountId = accountId
        self.planType = planType
    }
}

public struct OpenAIOAuthImportCodexResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var accountId: String?
    public var planType: String?

    public init(ok: Bool, message: String, accountId: String? = nil, planType: String? = nil) {
        self.ok = ok
        self.message = message
        self.accountId = accountId
        self.planType = planType
    }
}

public struct AnthropicOAuthStartRequest: Codable, Sendable {
    public var redirectURI: String

    public init(redirectURI: String) {
        self.redirectURI = redirectURI
    }
}

public struct AnthropicOAuthStartResponse: Codable, Sendable {
    public var authorizationURL: String
    public var redirectURI: String
    public var state: String

    public init(authorizationURL: String, redirectURI: String, state: String) {
        self.authorizationURL = authorizationURL
        self.redirectURI = redirectURI
        self.state = state
    }
}

public struct AnthropicOAuthCompleteRequest: Codable, Sendable {
    public var callbackURL: String?
    public var code: String?
    public var state: String?

    public init(callbackURL: String? = nil, code: String? = nil, state: String? = nil) {
        self.callbackURL = callbackURL
        self.code = code
        self.state = state
    }
}

public struct AnthropicOAuthCompleteResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var source: String?
    public var expiresAt: String?
    public var refreshable: Bool

    public init(
        ok: Bool,
        message: String,
        source: String? = nil,
        expiresAt: String? = nil,
        refreshable: Bool = false
    ) {
        self.ok = ok
        self.message = message
        self.source = source
        self.expiresAt = expiresAt
        self.refreshable = refreshable
    }
}

public struct AnthropicOAuthImportClaudeResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var source: String?
    public var expiresAt: String?
    public var refreshable: Bool

    public init(
        ok: Bool,
        message: String,
        source: String? = nil,
        expiresAt: String? = nil,
        refreshable: Bool = false
    ) {
        self.ok = ok
        self.message = message
        self.source = source
        self.expiresAt = expiresAt
        self.refreshable = refreshable
    }
}

public struct GeminiOAuthStartRequest: Codable, Sendable {
    public var redirectURI: String

    public init(redirectURI: String) {
        self.redirectURI = redirectURI
    }
}

public struct GeminiOAuthStartResponse: Codable, Sendable {
    public var authorizationURL: String
    public var redirectURI: String
    public var state: String

    public init(authorizationURL: String, redirectURI: String, state: String) {
        self.authorizationURL = authorizationURL
        self.redirectURI = redirectURI
        self.state = state
    }
}

public struct GeminiOAuthCompleteRequest: Codable, Sendable {
    public var callbackURL: String?
    public var code: String?
    public var state: String?

    public init(callbackURL: String? = nil, code: String? = nil, state: String? = nil) {
        self.callbackURL = callbackURL
        self.code = code
        self.state = state
    }
}

public struct GeminiOAuthCompleteResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var email: String?
    public var expiresAt: String?

    public init(ok: Bool, message: String, email: String? = nil, expiresAt: String? = nil) {
        self.ok = ok
        self.message = message
        self.email = email
        self.expiresAt = expiresAt
    }
}

public struct OpenAIDeviceCodeStartResponse: Codable, Sendable {
    public var deviceAuthId: String
    public var userCode: String
    public var verificationURL: String
    public var interval: Int
    public var expiresIn: Int

    public init(
        deviceAuthId: String,
        userCode: String,
        verificationURL: String,
        interval: Int = 5,
        expiresIn: Int = 600
    ) {
        self.deviceAuthId = deviceAuthId
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.interval = interval
        self.expiresIn = expiresIn
    }
}

public struct OpenAIDeviceCodePollRequest: Codable, Sendable {
    public var deviceAuthId: String
    public var userCode: String

    public init(deviceAuthId: String, userCode: String) {
        self.deviceAuthId = deviceAuthId
        self.userCode = userCode
    }
}

public struct OpenAIDeviceCodePollResponse: Codable, Sendable {
    public var status: String
    public var ok: Bool
    public var message: String
    public var accountId: String?
    public var planType: String?

    public init(
        status: String,
        ok: Bool,
        message: String,
        accountId: String? = nil,
        planType: String? = nil
    ) {
        self.status = status
        self.ok = ok
        self.message = message
        self.accountId = accountId
        self.planType = planType
    }
}

public struct GitHubConnectRequest: Codable, Sendable {
    public var token: String

    public init(token: String) {
        self.token = token
    }
}

public struct GitHubConnectResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var username: String?

    public init(ok: Bool, message: String, username: String? = nil) {
        self.ok = ok
        self.message = message
        self.username = username
    }
}

public struct GitHubAuthStatusResponse: Codable, Sendable {
    public var connected: Bool
    public var username: String?
    public var connectedAt: String?

    public init(connected: Bool, username: String? = nil, connectedAt: String? = nil) {
        self.connected = connected
        self.username = username
        self.connectedAt = connectedAt
    }
}

public struct ProviderProbeResponse: Codable, Sendable {
    public var providerId: ProviderProbeID
    public var ok: Bool
    public var usedEnvironmentKey: Bool
    public var message: String
    public var models: [ProviderModelOption]

    public init(
        providerId: ProviderProbeID,
        ok: Bool,
        usedEnvironmentKey: Bool,
        message: String,
        models: [ProviderModelOption]
    ) {
        self.providerId = providerId
        self.ok = ok
        self.usedEnvironmentKey = usedEnvironmentKey
        self.message = message
        self.models = models
    }
}

public struct SearchProviderStatusResponse: Codable, Sendable {
    public var provider: String
    public var hasEnvironmentKey: Bool
    public var hasConfiguredKey: Bool
    public var hasAnyKey: Bool

    public init(
        provider: String,
        hasEnvironmentKey: Bool,
        hasConfiguredKey: Bool,
        hasAnyKey: Bool
    ) {
        self.provider = provider
        self.hasEnvironmentKey = hasEnvironmentKey
        self.hasConfiguredKey = hasConfiguredKey
        self.hasAnyKey = hasAnyKey
    }
}

public struct SearchToolsStatusResponse: Codable, Sendable {
    public var activeProvider: String
    public var brave: SearchProviderStatusResponse
    public var perplexity: SearchProviderStatusResponse

    public init(
        activeProvider: String,
        brave: SearchProviderStatusResponse,
        perplexity: SearchProviderStatusResponse
    ) {
        self.activeProvider = activeProvider
        self.brave = brave
        self.perplexity = perplexity
    }
}

public struct ImageGenerationModelOption: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var provider: String
    public var supportsEditing: Bool
    public var maxReferenceImages: Int

    public init(id: String, title: String, provider: String, supportsEditing: Bool, maxReferenceImages: Int) {
        self.id = id
        self.title = title
        self.provider = provider
        self.supportsEditing = supportsEditing
        self.maxReferenceImages = maxReferenceImages
    }
}

public struct ImageGenerationStatusResponse: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var provider: String
    public var model: String
    public var hasEnvironmentKey: Bool
    public var hasConfiguredKey: Bool
    public var hasAnyKey: Bool
    public var models: [ImageGenerationModelOption]

    public init(
        enabled: Bool,
        provider: String,
        model: String,
        hasEnvironmentKey: Bool,
        hasConfiguredKey: Bool,
        hasAnyKey: Bool,
        models: [ImageGenerationModelOption]
    ) {
        self.enabled = enabled
        self.provider = provider
        self.model = model
        self.hasEnvironmentKey = hasEnvironmentKey
        self.hasConfiguredKey = hasConfiguredKey
        self.hasAnyKey = hasAnyKey
        self.models = models
    }
}

public struct GenerateTextRequest: Codable, Sendable {
    public var model: String
    public var prompt: String

    public init(model: String, prompt: String) {
        self.model = model
        self.prompt = prompt
    }
}

public struct GenerateTextResponse: Codable, Sendable {
    public var text: String
    public var model: String

    public init(text: String, model: String) {
        self.text = text
        self.model = model
    }
}
