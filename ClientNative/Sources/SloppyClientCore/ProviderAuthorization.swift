import Foundation

public struct CodexDeviceAuthorization: Codable, Sendable {
    public var deviceAuthId: String
    public var userCode: String
    public var verificationURL: String
    public var interval: Int
    public var expiresIn: Int
}

public struct CodexDeviceAuthorizationResult: Codable, Sendable {
    public var status: String
    public var ok: Bool
    public var message: String
    public var accountId: String?
    public var planType: String?
}

public struct CodexAuthorizationStatus: Codable, Sendable {
    public var hasOAuthCredentials: Bool
    public var oauthAccountId: String?
    public var oauthPlanType: String?
}

public enum ModelConnectionPreset: String, CaseIterable, Identifiable, Sendable {
    case openAI = "openai-api"
    case codex = "openai-oauth"
    case sloppy
    case openRouter = "openrouter"
    case anthropic
    case anthropicOAuth = "anthropic-oauth"
    case gemini
    case ollama

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openAI: "OpenAI API"
        case .codex: "Codex · Device code"
        case .sloppy: "Sloppy server"
        case .openRouter: "OpenRouter"
        case .anthropic: "Anthropic API"
        case .anthropicOAuth: "Anthropic OAuth"
        case .gemini: "Gemini"
        case .ollama: "Ollama"
        }
    }

    public var apiURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .codex: "https://chatgpt.com/backend-api"
        case .sloppy: ""
        case .openRouter: "https://openrouter.ai/api/v1"
        case .anthropic, .anthropicOAuth: "https://api.anthropic.com"
        case .gemini: "https://generativelanguage.googleapis.com"
        case .ollama: "http://localhost:11434"
        }
    }

    public func applying(to model: SloppyConfig.ModelConfig) -> SloppyConfig.ModelConfig {
        guard model.providerCatalogId != rawValue else { return model }
        var updated = model
        updated.providerCatalogId = rawValue
        updated.apiUrl = apiURL
        updated.apiKey = ""
        updated.model = ""
        let previousPreset = model.providerCatalogId.flatMap(Self.init(rawValue:))
        if model.title.isEmpty || model.title == "new-provider" || model.title == previousPreset?.title || model.title == previousPreset?.rawValue {
            updated.title = title
        }
        return updated
    }
}
