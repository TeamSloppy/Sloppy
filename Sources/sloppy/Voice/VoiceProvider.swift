import Foundation

import Protocols

/// Speech-to-text backend (ADR 0004). Credentials are resolved by Core and never reach clients.
protocol VoiceTranscriptionProvider: Sendable {
    func transcribe(request: VoiceModeTranscriptionRequest) async throws -> VoiceModeTranscriptionResponse
}

/// Text-to-speech backend (ADR 0004).
protocol VoiceSpeechProvider: Sendable {
    func speech(request: VoiceModeSpeechRequest) async throws -> VoiceModeSpeechResponse
}
