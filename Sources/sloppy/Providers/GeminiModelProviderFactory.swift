import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyLanguageModel
import PluginSDK

struct GeminiModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let geminiModels = config.resolvedModels.filter { $0.hasPrefix("gemini:") }
        guard !geminiModels.isEmpty else { return nil }

        let primaryConfig = config.modelConfigs.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("gemini:") == true
        }

        let baseURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? GeminiLanguageModel.defaultBaseURL

        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let envKey = ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
            .compactMap { ProcessInfo.processInfo.environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let resolvedKey = configuredKey.isEmpty ? envKey : configuredKey
        if !resolvedKey.isEmpty {
            return GeminiModelProvider(
                supportedModels: geminiModels,
                apiKey: { resolvedKey },
                baseURL: baseURL,
                tools: config.tools,
                systemInstructions: config.systemInstructions,
                session: ProxySessionFactory.makeSession(
                    proxy: config.coreConfig.proxy,
                    protocolClasses: [GeminiThoughtSignatureURLProtocol.self]
                ),
                nativeSession: ProxySessionFactory.makeSession(proxy: config.coreConfig.proxy)
            )
        }

        if let oauthCredentials = config.geminiOAuthCredentialsProvider?() {
            let tokenBox = GeminiOAuthTokenBox(credentials: oauthCredentials)
            let tokenUsageCapture = TokenUsageCapture()
            let tokenUsageCaptureID = TokenUsageCaptureRegistry.register(tokenUsageCapture)
            let nativeSession = ProxySessionFactory.makeSession(proxy: config.coreConfig.proxy)
            let nativeTransport: GeminiOAuthCredentials.Transport = { request in
                let (data, response) = try await nativeSession.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                return (data, response)
            }
            let refresh: @Sendable (Bool) async throws -> Void = { native in
                let current = tokenBox.credentials()
                guard current.isUsableForAntigravityCLI else {
                    throw GeminiOAuthCredentialsError.missingRequiredScope(currentScopes: current.antigravityScopeDescription)
                }
                let transport = native ? nativeTransport : nil
                let refreshed = try await current.refreshedIfNeeded(transport: transport)
                guard refreshed.isUsableForAntigravityCLI else {
                    throw GeminiOAuthCredentialsError.missingRequiredScope(currentScopes: refreshed.antigravityScopeDescription)
                }
                let binding = tokenBox.projectBinding()
                let project: String?
                if native, binding.resolved {
                    project = binding.id
                } else {
                    project = try await GeminiCodeAssistProjectResolver.resolve(credentials: refreshed, transport: transport)
                }
                tokenBox.update(refreshed, projectID: project)
                // Only the legacy rewriting protocol owns its process-wide cache.
                if !native { GeminiOAuthURLProtocol.setCompanionProjectID(project) }
            }
            return GeminiModelProvider(
                supportedModels: geminiModels,
                apiKey: { tokenBox.accessToken() },
                refreshTokenIfNeeded: { try await refresh(false) },
                baseURL: baseURL,
                tools: config.tools,
                systemInstructions: config.systemInstructions,
                session: ProxySessionFactory.makeSession(
                    proxy: config.coreConfig.proxy,
                    protocolClasses: [GeminiOAuthURLProtocol.self],
                    additionalHeaders: [TokenUsageCaptureRegistry.headerField: tokenUsageCaptureID]
                ),
                tokenUsageCapture: tokenUsageCapture,
                nativeSession: nativeSession,
                nativeCodeAssist: .init(baseURL: GeminiCodeAssistProjectResolver.defaultBaseURL,
                    projectID: { tokenBox.companionProjectID() },
                    headers: ["X-Goog-Api-Client": GeminiCodeAssistProjectResolver.apiClient,
                        "Client-Metadata": GeminiCodeAssistProjectResolver.clientMetadataHeader],
                    userAgent: GeminiCodeAssistProjectResolver.userAgent,
                    refreshCredentials: { try await refresh(true) })
            )
        }

        return nil
    }
}

private final class GeminiOAuthTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: GeminiOAuthCredentials
    private var projectID: String?
    private var projectResolved = false

    init(credentials: GeminiOAuthCredentials) {
        self.value = credentials
    }

    func credentials() -> GeminiOAuthCredentials {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func accessToken() -> String {
        lock.lock()
        defer { lock.unlock() }
        return value.accessToken
    }

    func companionProjectID() -> String? { lock.withLock { projectID } }
    func projectBinding() -> (resolved: Bool, id: String?) { lock.withLock { (projectResolved, projectID) } }

    func update(_ credentials: GeminiOAuthCredentials, projectID: String?) {
        lock.lock()
        value = credentials
        self.projectID = projectID
        projectResolved = true
        lock.unlock()
    }
}
