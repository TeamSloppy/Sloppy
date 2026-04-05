import Foundation
import AnyLanguageModel
import Protocols

// MARK: - Providers, OAuth, GitHub

extension CoreService {
    public func probeACPTarget(request: ACPTargetProbeRequest) async throws -> ACPTargetProbeResponse {
        try await acpSessionManager.probeTarget(request.target)
    }

    /// Returns OpenAI model catalog using API key auth or environment fallback.
    public func listOpenAIModels(request: OpenAIProviderModelsRequest) async -> OpenAIProviderModelsResponse {
        if request.authMethod == .deeplink {
            do {
                let models = try await openAIOAuthService.fetchModels()
                if !models.isEmpty {
                    cacheOAuthModels(models)
                }
                return OpenAIProviderModelsResponse(
                    provider: "openai",
                    authMethod: request.authMethod,
                    usedEnvironmentKey: false,
                    source: "remote",
                    warning: models.isEmpty ? "OpenAI OAuth returned no Codex models." : nil,
                    models: models
                )
            } catch {
                return OpenAIProviderModelsResponse(
                    provider: "openai",
                    authMethod: request.authMethod,
                    usedEnvironmentKey: false,
                    source: "fallback",
                    warning: error.localizedDescription,
                    models: []
                )
            }
        }

        return await openAIProviderCatalog.listModels(config: currentConfig, request: request)
    }

    /// Returns OpenAI provider key availability without fetching remote model catalog.
    public func openAIProviderStatus() -> OpenAIProviderStatusResponse {
        let apiStatus = openAIProviderCatalog.status(config: currentConfig)
        let oauthStatus = openAIOAuthService.status()
        return OpenAIProviderStatusResponse(
            provider: apiStatus.provider,
            hasEnvironmentKey: apiStatus.hasEnvironmentKey,
            hasConfiguredKey: apiStatus.hasConfiguredKey,
            hasAnyKey: apiStatus.hasAnyKey,
            hasOAuthCredentials: oauthStatus.hasCredentials,
            oauthAccountId: oauthStatus.accountId,
            oauthPlanType: oauthStatus.planType,
            oauthExpiresAt: oauthStatus.expiresAt
        )
    }

    /// Probes provider connectivity and returns remote model options on success.
    public func probeProvider(request: ProviderProbeRequest) async -> ProviderProbeResponse {
        if request.providerId == .openAIOAuth {
            let result = await openAIOAuthService.probe()
            if result.ok {
                cacheOAuthModels(result.models)
            }
            return result
        }
        return await providerProbeService.probe(config: currentConfig, request: request)
    }

    /// Generates text using the specified model and prompt, for one-shot completion tasks.
    public func generateText(request: GenerateTextRequest) async throws -> GenerateTextResponse {
        let config = currentConfig
        let oauthService = openAIOAuthService
        let hasOAuth = oauthService.currentAccessToken() != nil
        let resolvedModels = CoreModelProviderFactory.resolveModelIdentifiers(
            config: config,
            hasOAuthCredentials: hasOAuth
        )
        guard let modelProvider = CoreModelProviderFactory.buildModelProvider(
            config: config,
            resolvedModels: resolvedModels,
            oauthTokenProvider: { oauthService.currentAccessToken() },
            oauthAccountId: oauthService.currentAccountId(),
            oauthTokenRefresh: { try await oauthService.ensureValidToken() },
            proxySession: ProxySessionFactory.makeSession(proxy: config.proxy)
        ) else {
            throw GenerateError.noModelProvider
        }

        let modelId = request.model.isEmpty ? (modelProvider.supportedModels.first ?? resolvedModels.first ?? "") : request.model
        guard !modelId.isEmpty else {
            throw GenerateError.noModelAvailable
        }

        let languageModel = try await modelProvider.createLanguageModel(for: modelId)
        let session = LanguageModelSession(model: languageModel, tools: [])
        let options = modelProvider.generationOptions(for: modelId, maxTokens: 4096, reasoningEffort: nil)
        let response = try await session.respond(to: request.prompt, options: options)
        return GenerateTextResponse(text: response.content, model: modelId)
    }

    public func startOpenAIOAuth(request: OpenAIOAuthStartRequest) throws -> OpenAIOAuthStartResponse {
        try openAIOAuthService.startLogin(redirectURI: request.redirectURI)
    }

    public func completeOpenAIOAuth(request: OpenAIOAuthCompleteRequest) async throws -> OpenAIOAuthCompleteResponse {
        try await openAIOAuthService.completeLogin(request: request)
    }

    public func startOpenAIDeviceCode() async throws -> OpenAIDeviceCodeStartResponse {
        try await openAIOAuthService.startDeviceCode()
    }

    public func pollOpenAIDeviceCode(request: OpenAIDeviceCodePollRequest) async throws -> OpenAIDeviceCodePollResponse {
        try await openAIOAuthService.pollDeviceToken(deviceAuthId: request.deviceAuthId, userCode: request.userCode)
    }

    public func disconnectOpenAIOAuth() throws {
        try openAIOAuthService.disconnect()
    }

    public func gitHubAuthStatus() -> GitHubAuthStatusResponse {
        let status = githubAuthService.status()
        return GitHubAuthStatusResponse(
            connected: status.connected,
            username: status.username,
            connectedAt: status.connectedAt
        )
    }

    public func connectGitHub(request: GitHubConnectRequest) async throws -> GitHubConnectResponse {
        try await githubAuthService.connect(token: request.token)
    }

    public func disconnectGitHub() throws {
        try githubAuthService.disconnect()
    }

    /// Returns search provider key availability for configured web search providers.
    public func searchProviderStatus() async -> SearchToolsStatusResponse {
        await searchProviderService.status()
    }

    /// Returns latest persisted system logs from `/workspace/logs/*.log`.
    public func getUpdateStatus() async -> UpdateStatus {
        await updateChecker.status()
    }

    public func forceUpdateCheck() async -> UpdateStatus {
        await updateChecker.forceCheck()
    }

    public func getSystemLogs(limit: Int = 1500) throws -> SystemLogsResponse {
        do {
            return try systemLogStore.readRecentEntries(limit: limit)
        } catch {
            throw SystemLogsError.storageFailure
        }
    }

    /// Executes one tool call in session context and persists tool_call/tool_result events.
    func availableAgentModels() -> [ProviderModelOption] {
        let hasOAuth = openAIOAuthService.currentAccessToken() != nil
        let base = Self.availableAgentModels(config: currentConfig, hasOAuthCredentials: hasOAuth)
        guard !oauthModelCache.isEmpty else { return base }
        return base.map { option in
            guard let cached = oauthModelCache[option.id] ?? oauthModelCache[stripProviderPrefix(option.id)] else {
                return option
            }
            return ProviderModelOption(
                id: option.id,
                title: cached.title.isEmpty ? option.title : cached.title,
                contextWindow: cached.contextWindow ?? option.contextWindow,
                capabilities: cached.capabilities.isEmpty ? option.capabilities : cached.capabilities
            )
        }
    }

    func stripProviderPrefix(_ id: String) -> String {
        guard let idx = id.firstIndex(of: ":") else { return id }
        return String(id[id.index(after: idx)...])
    }

    func cacheOAuthModels(_ models: [ProviderModelOption]) {
        for model in models {
            oauthModelCache[model.id] = model
        }
    }

    func refreshOAuthModelCacheIfNeeded() async {
        guard openAIOAuthService.currentAccessToken() != nil else { return }
        do {
            let models = try await openAIOAuthService.fetchModels()
            cacheOAuthModels(models)
        } catch {
            logger.debug(
                "oauth_model_cache.refresh_failed",
                metadata: ["error": "\(error.localizedDescription)"]
            )
        }
    }

    static func availableAgentModels(config: CoreConfig, hasOAuthCredentials: Bool = false) -> [ProviderModelOption] {
        var seen: Set<String> = []
        var options: [ProviderModelOption] = []

        let candidates = CoreModelProviderFactory.resolveModelIdentifiers(
            config: config,
            hasOAuthCredentials: hasOAuthCredentials
        ) + config.models.map(\.model)
        for raw in candidates {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }

            if seen.insert(value).inserted {
                options.append(Self.providerModelOption(for: value))
            }
        }

        if options.isEmpty {
            options.append(Self.providerModelOption(for: "openai:gpt-4.1-mini"))
        }

        return options
    }

    static func providerModelOption(for identifier: String) -> ProviderModelOption {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID: String
        if let separatorIndex = trimmed.firstIndex(of: ":") {
            modelID = String(trimmed[trimmed.index(after: separatorIndex)...])
        } else {
            modelID = trimmed
        }

        let lowered = modelID.lowercased()
        var capabilities: [String] = []
        var contextWindow: String?

        if lowered.hasPrefix("gpt-4.1") {
            capabilities.append("tools")
            contextWindow = "1.0M"
        } else if lowered.hasPrefix("gpt-4o") {
            capabilities.append("tools")
            contextWindow = "128K"
        } else if lowered.hasPrefix("o4") || lowered.hasPrefix("o3") {
            capabilities.append(contentsOf: ["reasoning", "tools"])
            contextWindow = "200K"
        } else if lowered.hasPrefix("o1") {
            capabilities.append(contentsOf: ["reasoning", "tools"])
            contextWindow = "128K"
        }

        return ProviderModelOption(
            id: trimmed,
            title: trimmed,
            contextWindow: contextWindow,
            capabilities: capabilities
        )
    }

}
