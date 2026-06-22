import Foundation
import Protocols

extension CoreService {
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
}
