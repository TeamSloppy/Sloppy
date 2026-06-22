import Foundation
import Protocols

extension CoreService {
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
}
