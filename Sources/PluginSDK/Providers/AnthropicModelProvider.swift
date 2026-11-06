import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

public struct AnthropicModelProvider: ModelProvider, ModelStepProviderFactory {
    public let id: String
    public let supportedModels: [String]
    public let systemInstructions: String?
    public let tools: [any Tool]
    private let tokenProvider: @Sendable () -> String
    private let baseURL: URL
    private let session: URLSession?
    private let refreshTokenIfNeeded: (@Sendable () async throws -> Void)?
    private let _tokenUsageCapture: TokenUsageCapture
    private let tokenUsageCaptureID: String

    public init(
        id: String = "anthropic",
        supportedModels: [String],
        apiKey: @escaping @Sendable () -> String,
        baseURL: URL = OAuthAnthropicLanguageModel.defaultBaseURL,
        tools: [any Tool] = [],
        systemInstructions: String? = nil,
        session: URLSession? = nil,
        refreshTokenIfNeeded: (@Sendable () async throws -> Void)? = nil,
        tokenUsageCapture: TokenUsageCapture? = nil
    ) {
        let capture = tokenUsageCapture ?? TokenUsageCapture()
        self.id = id
        self.supportedModels = supportedModels
        self.tokenProvider = apiKey
        self.baseURL = baseURL
        self.tools = tools
        self.systemInstructions = systemInstructions
        self.session = session
        self.refreshTokenIfNeeded = refreshTokenIfNeeded
        self._tokenUsageCapture = capture
        self.tokenUsageCaptureID = TokenUsageCaptureRegistry.register(capture)
    }

    public func supports(modelName: String) -> Bool {
        if supportedModels.contains(modelName) {
            return true
        }
        return modelName.hasPrefix("anthropic:")
    }

    public func tokenUsageCapture(for modelName: String) -> TokenUsageCapture? {
        guard supports(modelName: modelName) else { return nil }
        return _tokenUsageCapture
    }

    public func supportsUsageObservation(for modelName: String) -> Bool { supports(modelName: modelName) }
    public func supportsModelSteps(for modelName: String) -> Bool { supports(modelName: modelName) }

    public func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? {
        guard supportsModelSteps(for: modelName) else { return nil }
        let resolved = modelName.hasPrefix("anthropic:") ? String(modelName.dropFirst(10)) : modelName
        var baseSession = session ?? .shared
        let configuration = try UsageObservedURLSession.copyConfiguration(of: baseSession)
        if configuration.protocolClasses?.contains(where: { $0 == OAuthAnthropicURLProtocol.self }) == true {
            // Native requests already carry correct auth headers. Keep the configured proxy
            // and trust handling without routing through the legacy rewriting session.
            configuration.protocolClasses = configuration.protocolClasses?.filter { $0 != OAuthAnthropicURLProtocol.self }
            baseSession = URLSession(configuration: configuration, delegate: baseSession.delegate, delegateQueue: baseSession.delegateQueue)
        }
        let observed = try usageContext.map { try UsageObservedURLSession.make(wrapping: baseSession, context: $0) } ?? baseSession
        return NativeHTTPModelStepProvider(providerID: id + "/messages/" + ModelStepHTTPTransport.cacheKeyDigest(baseURL.absoluteString),
            model: resolved, baseURL: baseURL, token: tokenProvider, refresh: refreshTokenIfNeeded,
            session: observed, instructions: systemInstructions ?? "", format: .anthropic)
    }

    public func createLanguageModel(for modelName: String, usageContext: ModelUsageContext) async throws -> any LanguageModel {
        let observed = try UsageObservedURLSession.make(wrapping: session ?? OAuthAnthropicURLSession.makeSessionRewritingAnthropicAuth(), context: usageContext)
        let scoped = AnthropicModelProvider(id: id, supportedModels: supportedModels, apiKey: tokenProvider, baseURL: baseURL, tools: tools, systemInstructions: systemInstructions,
            session: observed, refreshTokenIfNeeded: refreshTokenIfNeeded)
        return try await scoped.createLanguageModel(for: modelName)
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        let resolved = modelName.hasPrefix("anthropic:") ? String(modelName.dropFirst(10)) : modelName
        try? await refreshTokenIfNeeded?()
        let httpSession: HTTPSession
        if let session {
            httpSession = session
        } else {
            httpSession = OAuthAnthropicURLSession.makeSessionRewritingAnthropicAuth(
                tokenUsageCaptureID: tokenUsageCaptureID
            )
        }
        return OAuthAnthropicLanguageModel(
            baseURL: baseURL,
            apiKey: tokenProvider(),
            model: resolved,
            session: httpSession
        )
    }
}
