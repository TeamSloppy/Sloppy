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
    public var effectiveTranscriptionProvider: String?
    public var effectiveSpeechProvider: String?
    public var effectiveRealtimeProvider: String?
    public var openAIConfigured: Bool
    public var localAvailable: Bool
    public var input: Input
    public var openAI: OpenAI
    public var local: Local

    public init(
        enabled: Bool,
        configuredProvider: String,
        effectiveProvider: String,
        effectiveTranscriptionProvider: String? = nil,
        effectiveSpeechProvider: String? = nil,
        effectiveRealtimeProvider: String? = nil,
        openAIConfigured: Bool,
        localAvailable: Bool,
        input: Input,
        openAI: OpenAI,
        local: Local
    ) {
        self.enabled = enabled
        self.configuredProvider = configuredProvider
        self.effectiveProvider = effectiveProvider
        self.effectiveTranscriptionProvider = effectiveTranscriptionProvider
        self.effectiveSpeechProvider = effectiveSpeechProvider
        self.effectiveRealtimeProvider = effectiveRealtimeProvider
        self.openAIConfigured = openAIConfigured
        self.localAvailable = localAvailable
        self.input = input
        self.openAI = openAI
        self.local = local
    }
}

public struct VoiceModeCapabilitiesResponse: Codable, Sendable, Equatable {
    public struct Voice: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var recommended: Bool
        public var models: [String]

        public init(id: String, title: String, recommended: Bool = false, models: [String] = []) {
            self.id = id
            self.title = title
            self.recommended = recommended
            self.models = models
        }
    }

    public var provider: String
    public var openAIConfigured: Bool
    public var source: String
    public var warning: String?
    public var speechModels: [ProviderModelOption]
    public var transcriptionModels: [ProviderModelOption]
    public var voices: [Voice]

    public init(
        provider: String,
        openAIConfigured: Bool,
        source: String,
        warning: String? = nil,
        speechModels: [ProviderModelOption],
        transcriptionModels: [ProviderModelOption],
        voices: [Voice]
    ) {
        self.provider = provider
        self.openAIConfigured = openAIConfigured
        self.source = source
        self.warning = warning
        self.speechModels = speechModels
        self.transcriptionModels = transcriptionModels
        self.voices = voices
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

/// Short-lived credentials for a browser-direct realtime voice session (ADR 0007).
public struct VoiceModeRealtimeSessionResponse: Codable, Sendable, Equatable {
    public var provider: String
    public var model: String
    public var token: String
    public var websocketUrl: String
    public var expiresAt: String
    public var voice: String
    public var systemInstruction: String

    public init(
        provider: String,
        model: String,
        token: String,
        websocketUrl: String,
        expiresAt: String,
        voice: String,
        systemInstruction: String
    ) {
        self.provider = provider
        self.model = model
        self.token = token
        self.websocketUrl = websocketUrl
        self.expiresAt = expiresAt
        self.voice = voice
        self.systemInstruction = systemInstruction
    }
}

public struct VoiceModeWhisperModelOption: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var fileName: String
    public var sizeBytes: Int64
    public var recommended: Bool
    public var installed: Bool
    public var path: String?

    public init(
        id: String,
        title: String,
        fileName: String,
        sizeBytes: Int64,
        recommended: Bool = false,
        installed: Bool = false,
        path: String? = nil
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.recommended = recommended
        self.installed = installed
        self.path = path
    }
}

public struct VoiceModeWhisperInstallJob: Codable, Sendable, Equatable {
    /// `idle | running | succeeded | failed`
    public var state: String
    /// `whisper_cpp | ffmpeg | model` while running or when failed.
    public var step: String?
    /// 0...1 when known; nil while a step has no measurable progress.
    public var progress: Double?
    public var message: String?
    public var model: String?
    public var modelPath: String?

    public init(
        state: String = "idle",
        step: String? = nil,
        progress: Double? = nil,
        message: String? = nil,
        model: String? = nil,
        modelPath: String? = nil
    ) {
        self.state = state
        self.step = step
        self.progress = progress
        self.message = message
        self.model = model
        self.modelPath = modelPath
    }
}

public struct VoiceModeWhisperStatusResponse: Codable, Sendable, Equatable {
    public var whisperCliPath: String?
    public var ffmpegPath: String?
    public var brewPath: String?
    public var modelsDirectory: String
    public var models: [VoiceModeWhisperModelOption]
    /// True when Core can install what is missing by itself (Homebrew present, or only a model is missing).
    public var installable: Bool
    public var manualCommands: [String]
    public var job: VoiceModeWhisperInstallJob

    public init(
        whisperCliPath: String?,
        ffmpegPath: String?,
        brewPath: String?,
        modelsDirectory: String,
        models: [VoiceModeWhisperModelOption],
        installable: Bool,
        manualCommands: [String],
        job: VoiceModeWhisperInstallJob
    ) {
        self.whisperCliPath = whisperCliPath
        self.ffmpegPath = ffmpegPath
        self.brewPath = brewPath
        self.modelsDirectory = modelsDirectory
        self.models = models
        self.installable = installable
        self.manualCommands = manualCommands
        self.job = job
    }
}

public struct VoiceModeWhisperInstallRequest: Codable, Sendable, Equatable {
    public var model: String

    public init(model: String) {
        self.model = model
    }
}
