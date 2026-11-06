import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

public struct GeminiModelProvider: ModelProvider, ModelStepProviderFactory {
    /// Account transport and project ownership are explicit; native steps never consult
    /// a process-wide legacy signature/project cache.
    public struct NativeCodeAssistSettings: Sendable {
        public var baseURL: URL
        public var projectID: @Sendable () -> String?
        public var headers: [String: String]
        public var userAgent: String
        public var refreshCredentials: (@Sendable () async throws -> Void)?
        public init(baseURL: URL, projectID: @escaping @Sendable () -> String?,
                    headers: [String: String], userAgent: String,
                    refreshCredentials: (@Sendable () async throws -> Void)? = nil) {
            self.baseURL = baseURL; self.projectID = projectID
            self.headers = headers; self.userAgent = userAgent
            self.refreshCredentials = refreshCredentials
        }
    }
    public let id: String
    public let supportedModels: [String]
    public let systemInstructions: String?
    public let tools: [any Tool]
    private let apiKey: @Sendable () -> String
    private let refreshTokenIfNeeded: (@Sendable () async throws -> Void)?
    private let baseURL: URL
    private let session: URLSession?
    private let nativeSession: URLSession?
    private let nativeCodeAssist: NativeCodeAssistSettings?
    private let _tokenUsageCapture: TokenUsageCapture

    public init(
        id: String = "gemini",
        supportedModels: [String],
        apiKey: @escaping @Sendable () -> String,
        refreshTokenIfNeeded: (@Sendable () async throws -> Void)? = nil,
        baseURL: URL = GeminiLanguageModel.defaultBaseURL,
        tools: [any Tool] = [],
        systemInstructions: String? = nil,
        session: URLSession? = nil,
        tokenUsageCapture: TokenUsageCapture? = nil,
        nativeSession: URLSession? = nil,
        nativeCodeAssist: NativeCodeAssistSettings? = nil
    ) {
        self.id = id
        self.supportedModels = supportedModels
        self.apiKey = apiKey
        self.refreshTokenIfNeeded = refreshTokenIfNeeded
        self.baseURL = baseURL
        self.tools = tools
        self.systemInstructions = systemInstructions
        self.session = session
        self.nativeSession = nativeSession
        self.nativeCodeAssist = nativeCodeAssist
        self._tokenUsageCapture = tokenUsageCapture ?? TokenUsageCapture()
    }

    public func supports(modelName: String) -> Bool {
        if supportedModels.contains(modelName) {
            return true
        }
        return modelName.hasPrefix("gemini:")
    }

    public func tokenUsageCapture(for modelName: String) -> TokenUsageCapture? {
        guard supports(modelName: modelName) else { return nil }
        return _tokenUsageCapture
    }

    public func supportsUsageObservation(for modelName: String) -> Bool { supports(modelName: modelName) }
    public func supportsModelSteps(for modelName: String) -> Bool { supports(modelName: modelName) }

    public func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? {
        guard supportsModelSteps(for: modelName) else { return nil }
        let resolved = modelName.hasPrefix("gemini:") ? String(modelName.dropFirst(7)) : modelName
        let base = nativeSession ?? session ?? .shared
        let observed = try usageContext.map { try UsageObservedURLSession.make(wrapping: base, context: $0) } ?? base
        let endpoint = nativeCodeAssist?.baseURL ?? baseURL
        let route = nativeCodeAssist == nil ? "/generate-content/" : "/code-assist/"
        return NativeHTTPModelStepProvider(providerID: id + route + ModelStepHTTPTransport.cacheKeyDigest(endpoint.absoluteString),
            model: resolved, baseURL: endpoint, token: apiKey, refresh: nativeCodeAssist?.refreshCredentials ?? refreshTokenIfNeeded,
            session: observed, instructions: systemInstructions ?? "", format: .gemini, nativeCodeAssist: nativeCodeAssist)
    }
    public func createLanguageModel(for modelName: String, usageContext: ModelUsageContext) async throws -> any LanguageModel {
        let observed = try UsageObservedURLSession.make(wrapping: session, context: usageContext)
        let scoped = GeminiModelProvider(id: id, supportedModels: supportedModels, apiKey: apiKey, refreshTokenIfNeeded: refreshTokenIfNeeded, baseURL: baseURL,
            tools: tools, systemInstructions: systemInstructions, session: observed)
        return try await scoped.createLanguageModel(for: modelName)
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        try await refreshTokenIfNeeded?()
        let resolved = modelName.hasPrefix("gemini:") ? String(modelName.dropFirst(7)) : modelName
        if let session {
            return GeminiLanguageModel(
                baseURL: baseURL,
                apiKey: apiKey(),
                model: resolved,
                session: session
            )
        }
        return GeminiLanguageModel(
            baseURL: baseURL,
            apiKey: apiKey(),
            model: resolved
        )
    }
}
