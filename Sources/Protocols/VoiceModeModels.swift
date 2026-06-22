import Foundation

public struct VoiceModeConfigResponse: Codable, Sendable, Equatable {
    public struct Input: Codable, Sendable, Equatable {
        public var mode: String
        public var language: String
        public var previewBeforeSend: Bool

        public init(mode: String, language: String, previewBeforeSend: Bool) {
            self.mode = mode
            self.language = language
            self.previewBeforeSend = previewBeforeSend
        }
    }

    public struct OpenAI: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var transcriptionModel: String
        public var ttsModel: String
        public var voice: String
        public var instructions: String

        public init(enabled: Bool, transcriptionModel: String, ttsModel: String, voice: String, instructions: String) {
            self.enabled = enabled
            self.transcriptionModel = transcriptionModel
            self.ttsModel = ttsModel
            self.voice = voice
            self.instructions = instructions
        }
    }

    public struct Local: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var voiceName: String
        public var rate: Double
        public var pitch: Double

        public init(enabled: Bool, voiceName: String, rate: Double, pitch: Double) {
            self.enabled = enabled
            self.voiceName = voiceName
            self.rate = rate
            self.pitch = pitch
        }
    }

    public var enabled: Bool
    public var configuredProvider: String
    public var effectiveProvider: String
    public var openAIConfigured: Bool
    public var localAvailable: Bool
    public var input: Input
    public var openAI: OpenAI
    public var local: Local

    public init(
        enabled: Bool,
        configuredProvider: String,
        effectiveProvider: String,
        openAIConfigured: Bool,
        localAvailable: Bool,
        input: Input,
        openAI: OpenAI,
        local: Local
    ) {
        self.enabled = enabled
        self.configuredProvider = configuredProvider
        self.effectiveProvider = effectiveProvider
        self.openAIConfigured = openAIConfigured
        self.localAvailable = localAvailable
        self.input = input
        self.openAI = openAI
        self.local = local
    }
}

public struct VoiceModeTranscriptionRequest: Codable, Sendable, Equatable {
    public var audioBase64: String
    public var mimeType: String
    public var language: String?
    public var prompt: String?

    public init(audioBase64: String, mimeType: String, language: String? = nil, prompt: String? = nil) {
        self.audioBase64 = audioBase64
        self.mimeType = mimeType
        self.language = language
        self.prompt = prompt
    }
}

public struct VoiceModeTranscriptionResponse: Codable, Sendable, Equatable {
    public var text: String
    public var provider: String
    public var model: String

    public init(text: String, provider: String, model: String) {
        self.text = text
        self.provider = provider
        self.model = model
    }
}

public struct VoiceModeSpeechRequest: Codable, Sendable, Equatable {
    public var text: String
    public var voice: String?
    public var instructions: String?

    public init(text: String, voice: String? = nil, instructions: String? = nil) {
        self.text = text
        self.voice = voice
        self.instructions = instructions
    }
}

public struct VoiceModeSpeechResponse: Codable, Sendable, Equatable {
    public var audioBase64: String
    public var mimeType: String
    public var provider: String
    public var model: String
    public var voice: String

    public init(audioBase64: String, mimeType: String, provider: String, model: String, voice: String) {
        self.audioBase64 = audioBase64
        self.mimeType = mimeType
        self.provider = provider
        self.model = model
        self.voice = voice
    }
}
