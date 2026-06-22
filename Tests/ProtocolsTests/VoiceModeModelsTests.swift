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
