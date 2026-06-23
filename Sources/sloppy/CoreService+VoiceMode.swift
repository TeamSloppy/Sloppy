import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

extension CoreService {
    private struct OpenAIModelsResponse: Decodable {
        struct ModelItem: Decodable {
            let id: String
        }

        let data: [ModelItem]
    }

    private static let fallbackVoiceSpeechModels: [ProviderModelOption] = [
        .init(id: "gpt-4o-mini-tts", title: "GPT-4o mini TTS", capabilities: ["tts"]),
        .init(id: "tts-1", title: "TTS 1", capabilities: ["tts", "low_latency"]),
        .init(id: "tts-1-hd", title: "TTS 1 HD", capabilities: ["tts", "high_quality"]),
    ]

    private static let fallbackVoiceTranscriptionModels: [ProviderModelOption] = [
        .init(id: "gpt-4o-transcribe", title: "GPT-4o Transcribe", capabilities: ["transcription"]),
        .init(id: "gpt-4o-mini-transcribe", title: "GPT-4o mini Transcribe", capabilities: ["transcription"]),
        .init(id: "whisper-1", title: "Whisper 1", capabilities: ["transcription"]),
    ]

    private static let gpt4oMiniTTSVoices = [
        "alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer", "verse", "marin", "cedar",
    ]

    private static let legacyTTSVoices = [
        "alloy", "ash", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer",
    ]

    public enum VoiceModeError: Error {
        case invalidPayload
        case openAINotConfigured
        case requestFailed(String)
    }

    public func voiceModeConfig() async -> VoiceModeConfigResponse {
        let config = getConfig()
        let openAIConfigured = Self.voiceModeOpenAIConfigured(config)
        let effectiveProvider: String
        switch config.voiceMode.provider {
        case .openAI:
            effectiveProvider = openAIConfigured ? "openai" : "unavailable"
        case .local:
            effectiveProvider = "local"
        case .auto:
            effectiveProvider = openAIConfigured ? "openai" : "local"
        }

        return VoiceModeConfigResponse(
            enabled: config.voiceMode.enabled,
            configuredProvider: config.voiceMode.provider.rawValue,
            effectiveProvider: effectiveProvider,
            openAIConfigured: openAIConfigured,
            localAvailable: config.voiceMode.local.enabled,
            input: .init(
                mode: config.voiceMode.input.mode.rawValue,
                language: config.voiceMode.input.language,
                previewBeforeSend: config.voiceMode.input.previewBeforeSend
            ),
            openAI: .init(
                enabled: config.voiceMode.openAI.enabled,
                transcriptionModel: config.voiceMode.openAI.transcriptionModel,
                ttsModel: config.voiceMode.openAI.ttsModel,
                voice: config.voiceMode.openAI.voice,
                instructions: config.voiceMode.openAI.instructions
            ),
            local: .init(
                enabled: config.voiceMode.local.enabled,
                voiceName: config.voiceMode.local.voiceName,
                rate: config.voiceMode.local.rate,
                pitch: config.voiceMode.local.pitch
            )
        )
    }

    public func voiceModeCapabilities() async -> VoiceModeCapabilitiesResponse {
        let config = getConfig()
        let openAIConfigured = Self.voiceModeOpenAIConfigured(config)
        let voices = Self.openAIVoiceOptions()
        guard let apiKey = Self.voiceModeOpenAICatalogAPIKey(config) else {
            return VoiceModeCapabilitiesResponse(
                provider: "openai",
                openAIConfigured: openAIConfigured,
                source: "fallback",
                warning: "OpenAI API key is missing. Using built-in voice mode options.",
                speechModels: Self.fallbackVoiceSpeechModels,
                transcriptionModels: Self.fallbackVoiceTranscriptionModels,
                voices: voices
            )
        }

        do {
            let models = try await Self.fetchOpenAIModelIDs(config: config, apiKey: apiKey)
            let speechModels = Self.voiceSpeechModels(from: models)
            let transcriptionModels = Self.voiceTranscriptionModels(from: models)
            let hasRemoteVoiceModels = !speechModels.isEmpty || !transcriptionModels.isEmpty

            return VoiceModeCapabilitiesResponse(
                provider: "openai",
                openAIConfigured: openAIConfigured,
                source: hasRemoteVoiceModels ? "remote" : "fallback",
                warning: hasRemoteVoiceModels ? nil : "OpenAI returned no recognized voice models. Using built-in voice mode options.",
                speechModels: speechModels.isEmpty ? Self.fallbackVoiceSpeechModels : speechModels,
                transcriptionModels: transcriptionModels.isEmpty ? Self.fallbackVoiceTranscriptionModels : transcriptionModels,
                voices: voices
            )
        } catch {
            return VoiceModeCapabilitiesResponse(
                provider: "openai",
                openAIConfigured: openAIConfigured,
                source: "fallback",
                warning: "Failed to fetch OpenAI voice models: \(error.localizedDescription)",
                speechModels: Self.fallbackVoiceSpeechModels,
                transcriptionModels: Self.fallbackVoiceTranscriptionModels,
                voices: voices
            )
        }
    }

    public func transcribeVoice(_ request: VoiceModeTranscriptionRequest) async throws -> VoiceModeTranscriptionResponse {
        let config = getConfig()
        guard Self.voiceModeOpenAIConfigured(config) else {
            throw VoiceModeError.openAINotConfigured
        }
        guard !request.audioBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw VoiceModeError.invalidPayload
        }
        guard let apiKey = Self.voiceModeOpenAIAPIKey(config) else {
            throw VoiceModeError.openAINotConfigured
        }

        return try await OpenAIVoiceModeClient().transcribe(request: request, config: config, apiKey: apiKey)
    }

    public func synthesizeVoice(_ request: VoiceModeSpeechRequest) async throws -> VoiceModeSpeechResponse {
        let config = getConfig()
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceModeError.invalidPayload
        }
        guard Self.voiceModeOpenAIConfigured(config) else {
            throw VoiceModeError.openAINotConfigured
        }
        guard let apiKey = Self.voiceModeOpenAIAPIKey(config) else {
            throw VoiceModeError.openAINotConfigured
        }

        return try await OpenAIVoiceModeClient().speech(request: request, config: config, apiKey: apiKey)
    }

    static func voiceModeOpenAIConfigured(_ config: CoreConfig) -> Bool {
        guard config.voiceMode.openAI.enabled else {
            return false
        }
        let configuredModel = config.models.contains { model in
            !model.disabled
                && model.apiUrl.localizedCaseInsensitiveContains("openai.com")
                && !model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if configuredModel {
            return true
        }
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"].map { !$0.isEmpty } == true
    }

    static func voiceModeOpenAIAPIKey(_ config: CoreConfig) -> String? {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        return config.models.first { model in
            !model.disabled
                && model.apiUrl.localizedCaseInsensitiveContains("openai.com")
                && !model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func voiceModeOpenAICatalogAPIKey(_ config: CoreConfig) -> String? {
        if let configuredKey = config.models.first(where: { model in
            !model.disabled
                && model.apiUrl.localizedCaseInsensitiveContains("openai.com")
                && !model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredKey.isEmpty {
            return configuredKey
        }
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    private static func fetchOpenAIModelIDs(config: CoreConfig, apiKey: String) async throws -> [String] {
        let configuredURL = config.models.first { model in
            !model.disabled && model.apiUrl.localizedCaseInsensitiveContains("openai.com")
        }?.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = CoreModelProviderFactory.parseURL(configuredURL) ?? URL(string: "https://api.openai.com/v1")!
        let endpoint = OpenAICompatibleCatalogEndpoint.modelsListURL(baseURL: baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await SloppyURLSessionFactory.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map(\.id).filter { !$0.isEmpty }.sorted()
    }

    private static func voiceSpeechModels(from modelIDs: [String]) -> [ProviderModelOption] {
        modelIDs
            .filter { $0.lowercased().contains("tts") }
            .map { id in
                ProviderModelOption(id: id, title: voiceModelTitle(id), capabilities: ["tts"])
            }
    }

    private static func voiceTranscriptionModels(from modelIDs: [String]) -> [ProviderModelOption] {
        modelIDs
            .filter {
                let lowered = $0.lowercased()
                return lowered.contains("transcribe") || lowered.contains("whisper")
            }
            .map { id in
                ProviderModelOption(id: id, title: voiceModelTitle(id), capabilities: ["transcription"])
            }
    }

    private static func openAIVoiceOptions() -> [VoiceModeCapabilitiesResponse.Voice] {
        gpt4oMiniTTSVoices.map { id in
            let models = legacyTTSVoices.contains(id)
                ? ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]
                : ["gpt-4o-mini-tts"]
            return VoiceModeCapabilitiesResponse.Voice(
                id: id,
                title: voiceModelTitle(id),
                recommended: id == "marin" || id == "cedar",
                models: models
            )
        }
    }

    private static func voiceModelTitle(_ id: String) -> String {
        id.split(separator: "-")
            .map { part in
                let lower = part.lowercased()
                if lower == "gpt" || lower == "tts" || lower == "hd" {
                    return lower.uppercased()
                }
                if lower == "4o" {
                    return "4o"
                }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}
