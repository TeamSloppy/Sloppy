import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    public func startDictation() {
        guard dictationPhase == .idle, !shouldShowStopButton, !isSending else {
            return
        }

        voiceReplyPlayer.stop()
        Task { @MainActor in
            _ = await resolvedVoiceConfig()
            do {
                try await dictationRecorder.start()
                dictationPhase = .recording
                dictationDuration = 0
                dictationLevels = Array(repeating: 0.12, count: 48)
                beginDictationMetering()
            } catch {
                resetDictationState()
                showSessionStatus(error.localizedDescription)
            }
        }
    }

    public func stopDictation() {
        guard dictationPhase == .recording else {
            return
        }

        dictationPhase = .transcribing
        dictationMeterTask?.cancel()
        dictationMeterTask = nil

        Task { @MainActor in
            do {
                let capture = try await dictationRecorder.stop()
                dictationDuration = capture.duration
                let transcript = try await transcribeDictationCapture(capture)
                composerDraft.text = transcript
                saveActiveComposerDraft()
                resetDictationState()
            } catch {
                await dictationRecorder.cancel()
                resetDictationState()
                showSessionStatus(error.localizedDescription)
            }
        }
    }

    private func beginDictationMetering() {
        dictationMeterTask?.cancel()
        dictationMeterTask = Task { @MainActor in
            while !Task.isCancelled, dictationPhase == .recording {
                let snapshot = await dictationRecorder.snapshot()
                dictationDuration = snapshot.elapsed
                appendDictationLevel(snapshot.level)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func appendDictationLevel(_ level: Double) {
        dictationLevels.removeFirst()
        dictationLevels.append(max(0.08, min(1, CGFloat(level))))
    }

    private func transcribeDictationCapture(_ capture: DictationCapture) async throws -> String {
        defer {
            try? FileManager.default.removeItem(at: capture.fileURL)
        }

        let audioData = try Data(contentsOf: capture.fileURL)
        guard !audioData.isEmpty else {
            throw DictationRecorderError.noCapture
        }
        let config = await resolvedVoiceConfig()
        do {
            let response = try await apiClient.transcribeVoice(
                VoiceTranscriptionRequest(
                    audioBase64: audioData.base64EncodedString(),
                    mimeType: capture.mimeType,
                    language: config?.transcriptionLanguage
                )
            )
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw DictationRecorderError.noSpeechDetected
            }
            return text
        } catch {
            guard VoiceTranscriptionFallback.allowsOnDeviceRecognition(after: error) else {
                throw error
            }
            let fallback = try await AppleSpeechTranscriber.transcribe(
                fileURL: capture.fileURL,
                localeIdentifier: config?.transcriptionLanguage ?? Locale.current.identifier
            )
            let text = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw DictationRecorderError.noSpeechDetected
            }
            return text
        }
    }

    /// Core's voice settings (language, providers), fetched once per view model; nil if unreachable.
    private func resolvedVoiceConfig() async -> VoiceConfig? {
        if let voiceConfig { return voiceConfig }
        if let voiceConfigTask { return await voiceConfigTask.value }
        let client = apiClient
        let task = Task { try? await client.fetchVoiceConfig() }
        voiceConfigTask = task
        let config = await task.value
        voiceConfigTask = nil
        voiceConfig = config
        return config
    }

    public func toggleReadAloud() {
        isReadAloudEnabled.toggle()
        UserDefaults.standard.set(isReadAloudEnabled, forKey: "sloppy.chat.readAloud")
        if !isReadAloudEnabled {
            voiceReplyPlayer.stop()
        }
    }

    public func stopSpeakingReply() {
        voiceReplyPlayer.stop()
    }

    /// Speaks one assistant message on demand (message menu), regardless of the auto setting.
    public func speakReply(_ message: ChatMessage) {
        speak(message.textContent)
    }

    func speakFinishedReply(_ message: ChatMessage) {
        guard isReadAloudEnabled, dictationPhase == .idle,
              spokenReplyIDs.insert(message.id).inserted else {
            return
        }
        speak(message.textContent)
    }

    private func speak(_ markdown: String) {
        let client = apiClient
        Task { @MainActor in
            let config = await resolvedVoiceConfig()
            voiceReplyPlayer.speak(
                markdown: markdown,
                localeIdentifier: config?.transcriptionLanguage ?? Locale.current.identifier
            ) { request in
                try await client.synthesizeVoice(request)
            }
        }
    }

    private func resetDictationState() {
        dictationMeterTask?.cancel()
        dictationMeterTask = nil
        dictationPhase = .idle
        dictationDuration = 0
        dictationLevels = Array(repeating: 0.12, count: 48)
    }

    func cancelDictationIfNeeded() {
        guard dictationPhase != .idle else {
            return
        }
        resetDictationState()
        Task {
            await dictationRecorder.cancel()
        }
    }
}
