import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

struct ProviderProbeService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct OpenAIModelsResponse: Decodable {
        struct ModelItem: Decodable {
            let id: String
        }

        let data: [ModelItem]
    }

    private struct OllamaTagsResponse: Decodable {
        struct ModelItem: Decodable {
            let name: String
        }

        let models: [ModelItem]
    }

    private let environmentLookup: @Sendable (String) -> String?
    private let transport: Transport

    init(
        environmentLookup: @escaping @Sendable (String) -> String? = { key in
            ProcessInfo.processInfo.environment[key]
        },
        transport: Transport? = nil
    ) {
        self.environmentLookup = environmentLookup
        self.transport = transport ?? { request in
            let session = URLSession(configuration: .default)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, httpResponse)
        }
    }

    func probe(config: CoreConfig, request: ProviderProbeRequest) async -> ProviderProbeResponse {
        switch request.providerId {
        case .openAIAPI:
            return await probeOpenAI(config: config, request: request, authMethod: .apiKey)
        case .openAIOAuth:
            return await probeOpenAI(config: config, request: request, authMethod: .deeplink)
        case .ollama:
            return await probeOllama(config: config, request: request)
        case .gemini:
            return await probeGemini(config: config, request: request)
        case .anthropic:
            return await probeAnthropic(config: config, request: request)
        }
    }

    private func probeOpenAI(
        config: CoreConfig,
        request: ProviderProbeRequest,
        authMethod: ProviderAuthMethod
    ) async -> ProviderProbeResponse {
        let primaryOpenAIConfig = config.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("openai:") == true
        }

        let apiURL = CoreModelProviderFactory.parseURL(request.apiUrl)
            ?? CoreModelProviderFactory.parseURL(primaryOpenAIConfig?.apiUrl)
            ?? URL(string: "https://api.openai.com/v1")

        let configuredKey = (primaryOpenAIConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentKey = environmentLookup("OPENAI_API_KEY")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestKey = request.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedKey: String
        let usedEnvironmentKey: Bool
        switch authMethod {
        case .apiKey:
            if !requestKey.isEmpty {
                resolvedKey = requestKey
                usedEnvironmentKey = false
            } else if !configuredKey.isEmpty {
                resolvedKey = configuredKey
                usedEnvironmentKey = false
            } else if !environmentKey.isEmpty {
                resolvedKey = environmentKey
                usedEnvironmentKey = true
            } else {
                return ProviderProbeResponse(
                    providerId: request.providerId,
                    ok: false,
                    usedEnvironmentKey: false,
                    message: "OpenAI API key is missing. Provide a key or set OPENAI_API_KEY.",
                    models: []
                )
            }
        case .deeplink:
            guard !environmentKey.isEmpty else {
                return ProviderProbeResponse(
                    providerId: request.providerId,
                    ok: false,
                    usedEnvironmentKey: false,
                    message: "OpenAI web login does not authorize Core by itself. Set OPENAI_API_KEY for Core and try again.",
                    models: []
                )
            }
            resolvedKey = environmentKey
            usedEnvironmentKey = true
        }

        guard let apiURL else {
            return ProviderProbeResponse(
                providerId: request.providerId,
                ok: false,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "OpenAI API URL is invalid.",
                models: []
            )
        }

        do {
            let models = try await fetchOpenAIModels(apiKey: resolvedKey, baseURL: apiURL)
            guard !models.isEmpty else {
                return ProviderProbeResponse(
                    providerId: request.providerId,
                    ok: false,
                    usedEnvironmentKey: usedEnvironmentKey,
                    message: "OpenAI responded successfully, but no models were returned.",
                    models: []
                )
            }

            return ProviderProbeResponse(
                providerId: request.providerId,
                ok: true,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "Connected to OpenAI. Loaded \(models.count) models.",
                models: models
            )
        } catch {
            return ProviderProbeResponse(
                providerId: request.providerId,
                ok: false,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "Failed to connect to OpenAI: \(error.localizedDescription)",
                models: []
            )
        }
    }

    private func probeOllama(
        config: CoreConfig,
        request: ProviderProbeRequest
    ) async -> ProviderProbeResponse {
        let primaryOllamaConfig = config.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("ollama:") == true
        }

        guard let baseURL = CoreModelProviderFactory.parseURL(request.apiUrl)
            ?? CoreModelProviderFactory.parseURL(primaryOllamaConfig?.apiUrl)
            ?? URL(string: "http://127.0.0.1:11434")
        else {
            return ProviderProbeResponse(
                providerId: .ollama,
                ok: false,
                usedEnvironmentKey: false,
                message: "Ollama API URL is invalid.",
                models: []
            )
        }

        do {
            let models = try await fetchOllamaModels(baseURL: baseURL)
            guard !models.isEmpty else {
                return ProviderProbeResponse(
                    providerId: .ollama,
                    ok: false,
                    usedEnvironmentKey: false,
                    message: "Connected to Ollama, but no local models were found.",
                    models: []
                )
            }

            return ProviderProbeResponse(
                providerId: .ollama,
                ok: true,
                usedEnvironmentKey: false,
                message: "Connected to Ollama. Loaded \(models.count) models.",
                models: models
            )
        } catch {
            return ProviderProbeResponse(
                providerId: .ollama,
                ok: false,
                usedEnvironmentKey: false,
                message: "Failed to connect to Ollama: \(error.localizedDescription)",
                models: []
            )
        }
    }

    private func fetchOpenAIModels(apiKey: String, baseURL: URL) async throws -> [ProviderModelOption] {
        let endpoint = openAIModelsURL(baseURL: baseURL)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data
            .map(\.id)
            .filter { !$0.isEmpty }
            .sorted()
            .map(enrichedOpenAIModelOption)
    }

    private func fetchOllamaModels(baseURL: URL) async throws -> [ProviderModelOption] {
        let endpoint = ollamaTagsURL(baseURL: baseURL)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models
            .map(\.name)
            .filter { !$0.isEmpty }
            .sorted()
            .map { name in
                ProviderModelOption(
                    id: name,
                    title: humanReadableOllamaModelTitle(name: name)
                )
            }
    }

    private func openAIModelsURL(baseURL: URL) -> URL {
        if baseURL.path.isEmpty || baseURL.path == "/" {
            return baseURL.appendingPathComponent("models")
        }

        let normalizedPath = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
        if normalizedPath.hasSuffix("/models") {
            return baseURL
        }

        return baseURL.appendingPathComponent("models")
    }

    private func ollamaTagsURL(baseURL: URL) -> URL {
        if baseURL.path.isEmpty || baseURL.path == "/" {
            return baseURL.appendingPathComponent("api").appendingPathComponent("tags")
        }

        let normalizedPath = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
        if normalizedPath.hasSuffix("/api/tags") {
            return baseURL
        }
        if normalizedPath.hasSuffix("/api") {
            return baseURL.appendingPathComponent("tags")
        }

        return baseURL.appendingPathComponent("api").appendingPathComponent("tags")
    }

    private struct GeminiModelsResponse: Decodable {
        struct ModelItem: Decodable {
            let name: String
            let displayName: String?
        }

        let models: [ModelItem]
    }

    private func probeGemini(
        config: CoreConfig,
        request: ProviderProbeRequest
    ) async -> ProviderProbeResponse {
        let primaryConfig = config.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("gemini:") == true
        }

        let envKey = environmentLookup("GEMINI_API_KEY")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestKey = request.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedKey: String
        let usedEnvironmentKey: Bool
        if !requestKey.isEmpty {
            resolvedKey = requestKey
            usedEnvironmentKey = false
        } else if !configuredKey.isEmpty {
            resolvedKey = configuredKey
            usedEnvironmentKey = false
        } else if !envKey.isEmpty {
            resolvedKey = envKey
            usedEnvironmentKey = true
        } else {
            return ProviderProbeResponse(
                providerId: .gemini,
                ok: false,
                usedEnvironmentKey: false,
                message: "Gemini API key is missing. Provide a key or set GEMINI_API_KEY.",
                models: []
            )
        }

        let baseURL = CoreModelProviderFactory.parseURL(request.apiUrl)
            ?? CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? URL(string: "https://generativelanguage.googleapis.com")

        guard let baseURL else {
            return ProviderProbeResponse(
                providerId: .gemini,
                ok: false,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "Gemini API URL is invalid.",
                models: []
            )
        }

        do {
            let models = try await fetchGeminiModels(apiKey: resolvedKey, baseURL: baseURL)
            guard !models.isEmpty else {
                return ProviderProbeResponse(
                    providerId: .gemini,
                    ok: false,
                    usedEnvironmentKey: usedEnvironmentKey,
                    message: "Connected to Gemini, but no models were returned.",
                    models: []
                )
            }

            return ProviderProbeResponse(
                providerId: .gemini,
                ok: true,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "Connected to Gemini. Loaded \(models.count) models.",
                models: models
            )
        } catch {
            return ProviderProbeResponse(
                providerId: .gemini,
                ok: false,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "Failed to connect to Gemini: \(error.localizedDescription)",
                models: []
            )
        }
    }

    private func fetchGeminiModels(apiKey: String, baseURL: URL) async throws -> [ProviderModelOption] {
        let endpoint = baseURL
            .appendingPathComponent("v1beta")
            .appendingPathComponent("models")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }

        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        return decoded.models
            .map { item in
                let modelId = item.name.hasPrefix("models/") ? String(item.name.dropFirst(7)) : item.name
                return ProviderModelOption(
                    id: modelId,
                    title: item.displayName ?? modelId,
                    contextWindow: geminiContextWindow(for: modelId),
                    capabilities: geminiCapabilities(for: modelId)
                )
            }
            .filter { $0.id.contains("gemini") }
            .sorted { $0.id < $1.id }
    }

    private func geminiContextWindow(for modelId: String) -> String? {
        let id = modelId.lowercased()
        if id.contains("2.5") || id.contains("2.0") { return "1.0M" }
        if id.contains("1.5-pro") { return "2.0M" }
        if id.contains("1.5-flash") { return "1.0M" }
        return nil
    }

    private func geminiCapabilities(for modelId: String) -> [String] {
        let id = modelId.lowercased()
        var caps: [String] = ["tools"]
        if id.contains("thinking") || id.contains("2.5") { caps.append("reasoning") }
        return caps
    }

    private static let anthropicModelCatalog: [ProviderModelOption] = [
        ProviderModelOption(id: "claude-sonnet-4-20250514", title: "Claude Sonnet 4", contextWindow: "200K", capabilities: ["tools", "reasoning"]),
        ProviderModelOption(id: "claude-3-7-sonnet-20250219", title: "Claude 3.7 Sonnet", contextWindow: "200K", capabilities: ["tools", "reasoning"]),
        ProviderModelOption(id: "claude-3-5-sonnet-20241022", title: "Claude 3.5 Sonnet", contextWindow: "200K", capabilities: ["tools"]),
        ProviderModelOption(id: "claude-3-5-haiku-20241022", title: "Claude 3.5 Haiku", contextWindow: "200K", capabilities: ["tools"]),
        ProviderModelOption(id: "claude-3-opus-20240229", title: "Claude 3 Opus", contextWindow: "200K", capabilities: ["tools"]),
    ]

    private func probeAnthropic(
        config: CoreConfig,
        request: ProviderProbeRequest
    ) async -> ProviderProbeResponse {
        let primaryConfig = config.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("anthropic:") == true
        }

        let envKey = environmentLookup("ANTHROPIC_API_KEY")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestKey = request.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedKey: String
        let usedEnvironmentKey: Bool
        if !requestKey.isEmpty {
            resolvedKey = requestKey
            usedEnvironmentKey = false
        } else if !configuredKey.isEmpty {
            resolvedKey = configuredKey
            usedEnvironmentKey = false
        } else if !envKey.isEmpty {
            resolvedKey = envKey
            usedEnvironmentKey = true
        } else {
            return ProviderProbeResponse(
                providerId: .anthropic,
                ok: false,
                usedEnvironmentKey: false,
                message: "Anthropic API key is missing. Provide a key or set ANTHROPIC_API_KEY.",
                models: []
            )
        }

        let baseURL = CoreModelProviderFactory.parseURL(request.apiUrl)
            ?? CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? URL(string: "https://api.anthropic.com")

        guard let baseURL else {
            return ProviderProbeResponse(
                providerId: .anthropic,
                ok: false,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "Anthropic API URL is invalid.",
                models: []
            )
        }

        do {
            let models = try await verifyAnthropicKey(apiKey: resolvedKey, baseURL: baseURL)
            return ProviderProbeResponse(
                providerId: .anthropic,
                ok: true,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "Connected to Anthropic. \(models.count) models available.",
                models: models
            )
        } catch {
            return ProviderProbeResponse(
                providerId: .anthropic,
                ok: false,
                usedEnvironmentKey: usedEnvironmentKey,
                message: "Failed to verify Anthropic API key: \(error.localizedDescription)",
                models: []
            )
        }
    }

    private func verifyAnthropicKey(apiKey: String, baseURL: URL) async throws -> [ProviderModelOption] {
        let endpoint = baseURL.appendingPathComponent("v1/messages")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await transport(urlRequest)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 429 else {
            throw URLError(.userAuthenticationRequired)
        }

        return Self.anthropicModelCatalog
    }

    private func enrichedOpenAIModelOption(id: String) -> ProviderModelOption {
        let lowered = id.lowercased()
        var contextWindow: String?
        var capabilities: [String] = []

        if lowered.hasPrefix("gpt-4.1") {
            contextWindow = "1.0M"
            capabilities.append("tools")
        } else if lowered.hasPrefix("gpt-4o") {
            contextWindow = "128K"
            capabilities.append("tools")
        } else if lowered.hasPrefix("o4") || lowered.hasPrefix("o3") {
            contextWindow = "200K"
            capabilities.append(contentsOf: ["reasoning", "tools"])
        } else if lowered.hasPrefix("o1") {
            contextWindow = "128K"
            capabilities.append(contentsOf: ["reasoning", "tools"])
        }

        return ProviderModelOption(
            id: id,
            title: humanReadableOpenAIModelTitle(id: id),
            contextWindow: contextWindow,
            capabilities: capabilities
        )
    }

    private func humanReadableOpenAIModelTitle(id: String) -> String {
        let lower = id.lowercased()
        if lower.hasPrefix("gpt-4.1") {
            let suffix = lower.replacingOccurrences(of: "gpt-4.1", with: "")
            return "GPT-4.1" + titleSuffix(from: suffix)
        }
        if lower.hasPrefix("gpt-4o") {
            let suffix = lower.replacingOccurrences(of: "gpt-4o", with: "")
            return "GPT-4o" + titleSuffix(from: suffix)
        }
        return id
    }

    private func humanReadableOllamaModelTitle(name: String) -> String {
        name.replacingOccurrences(of: ":latest", with: "")
    }

    private func titleSuffix(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        guard !trimmed.isEmpty else {
            return ""
        }

        let parts = trimmed
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.capitalized }
        guard !parts.isEmpty else {
            return ""
        }
        return " " + parts.joined(separator: " ")
    }
}
