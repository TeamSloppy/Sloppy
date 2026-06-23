import Foundation
import Testing
@testable import Protocols

@Test
func voiceModeConfigResponseRoundTripsWithoutSecrets() throws {
    let response = VoiceModeConfigResponse(
        enabled: true,
        configuredProvider: "auto",
        effectiveProvider: "openai",
        openAIConfigured: true,
        localAvailable: true,
        input: .init(mode: "push_to_talk", language: "auto", previewBeforeSend: true),
        openAI: .init(
            enabled: true,
            transcriptionModel: "gpt-4o-mini-transcribe",
            ttsModel: "gpt-4o-mini-tts",
            voice: "coral",
            instructions: "Speak warmly."
        ),
        local: .init(enabled: true, voiceName: "", rate: 1, pitch: 1)
    )

    let data = try JSONEncoder().encode(response)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.localizedCaseInsensitiveContains("apiKey"))
    #expect(!json.localizedCaseInsensitiveContains("authorization"))

    let decoded = try JSONDecoder().decode(VoiceModeConfigResponse.self, from: data)
    #expect(decoded.effectiveProvider == "openai")
    #expect(decoded.openAI.voice == "coral")
}

@Test
func voiceModeAudioRequestsRoundTrip() throws {
    let transcription = VoiceModeTranscriptionRequest(
        audioBase64: "d2F2",
        mimeType: "audio/webm",
        language: "ru-RU",
        prompt: "Sloppy project vocabulary"
    )
    let speech = VoiceModeSpeechRequest(text: "Привет", voice: "marin", instructions: "Short reply")

    let transcriptionDecoded = try JSONDecoder().decode(
        VoiceModeTranscriptionRequest.self,
        from: JSONEncoder().encode(transcription)
    )
    let speechDecoded = try JSONDecoder().decode(
        VoiceModeSpeechRequest.self,
        from: JSONEncoder().encode(speech)
    )

    #expect(transcriptionDecoded.mimeType == "audio/webm")
    #expect(transcriptionDecoded.language == "ru-RU")
    #expect(speechDecoded.text == "Привет")
    #expect(speechDecoded.voice == "marin")
}

@Test("voice mode capabilities response round-trips")
func voiceModeCapabilitiesResponseRoundTrips() throws {
    let response = VoiceModeCapabilitiesResponse(
        provider: "openai",
        openAIConfigured: true,
        source: "fallback",
        warning: nil,
        speechModels: [
            .init(id: "gpt-4o-mini-tts", title: "GPT-4o mini TTS", capabilities: ["tts"])
        ],
        transcriptionModels: [
            .init(id: "gpt-4o-mini-transcribe", title: "GPT-4o mini Transcribe", capabilities: ["transcription"])
        ],
        voices: [
            .init(id: "marin", title: "Marin", recommended: true, models: ["gpt-4o-mini-tts"])
        ]
    )

    let decoded = try JSONDecoder().decode(VoiceModeCapabilitiesResponse.self, from: JSONEncoder().encode(response))

    #expect(decoded.provider == "openai")
    #expect(decoded.speechModels.first?.id == "gpt-4o-mini-tts")
    #expect(decoded.transcriptionModels.first?.id == "gpt-4o-mini-transcribe")
    #expect(decoded.voices.first?.recommended == true)
}
