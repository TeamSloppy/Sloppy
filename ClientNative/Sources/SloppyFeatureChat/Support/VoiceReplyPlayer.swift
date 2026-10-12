import AVFoundation
import Foundation
import Observation
import SloppyClientCore

/// Reads assistant replies aloud through Core's `/v1/voice/speech` (the same provider as the
/// Dashboard), synthesizing the next sentence group while the current one plays. When Core has
/// no speech provider, or a request fails, the rest of the reply uses the system voice.
@MainActor
@Observable
public final class VoiceReplyPlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    public typealias Synthesize = @Sendable (VoiceSpeechRequest) async throws -> VoiceSpeechResponse

    public private(set) var isSpeaking = false

    @ObservationIgnored private var speakingTask: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var playbackFinished: CheckedContinuation<Void, Never>?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `markdown` after stripping formatting. Any speech already in progress is replaced.
    public func speak(markdown: String, localeIdentifier: String?, synthesize: @escaping Synthesize) {
        stop()
        let chunks = VoiceSpeechText.speechChunks(from: VoiceSpeechText.plainText(fromMarkdown: markdown))
        guard !chunks.isEmpty else { return }
        isSpeaking = true
        speakingTask = Task { @MainActor [weak self] in
            await self?.play(chunks: chunks, localeIdentifier: localeIdentifier, synthesize: synthesize)
            guard let self, !Task.isCancelled else { return }
            self.finishSpeaking()
        }
    }

    public func stop() {
        speakingTask?.cancel()
        speakingTask = nil
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        resumePlayback()
        finishSpeaking()
    }

    private func play(chunks: [String], localeIdentifier: String?, synthesize: @escaping Synthesize) async {
        activateAudioSession()
        var useSystemVoice = false
        var pending: Task<VoiceSpeechResponse?, Never>? = Self.prefetch(chunks[0], synthesize)
        for index in chunks.indices {
            let current = pending
            pending = index + 1 < chunks.count && !useSystemVoice ? Self.prefetch(chunks[index + 1], synthesize) : nil
            if Task.isCancelled { current?.cancel(); pending?.cancel(); return }
            if !useSystemVoice, let response = await current?.value, let data = response.audioData {
                await playAudio(data)
            } else {
                // Core has no speech provider or the request failed: stay on the system voice from here on.
                useSystemVoice = true
                pending?.cancel()
                pending = nil
                await speakWithSystemVoice(chunks[index], localeIdentifier: localeIdentifier)
            }
            if Task.isCancelled { pending?.cancel(); return }
        }
    }

    private static func prefetch(_ text: String, _ synthesize: @escaping Synthesize) -> Task<VoiceSpeechResponse?, Never> {
        Task { try? await synthesize(VoiceSpeechRequest(text: text)) }
    }

    private func playAudio(_ data: Data) async {
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.delegate = self
        self.player = player
        guard player.prepareToPlay(), player.play() else {
            self.player = nil
            return
        }
        await withCheckedContinuation { playbackFinished = $0 }
        self.player = nil
    }

    private func speakWithSystemVoice(_ text: String, localeIdentifier: String?) async {
        let utterance = AVSpeechUtterance(string: text)
        if let localeIdentifier, !localeIdentifier.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(language: localeIdentifier.replacingOccurrences(of: "_", with: "-"))
        }
        await withCheckedContinuation {
            playbackFinished = $0
            synthesizer.speak(utterance)
        }
    }

    private func resumePlayback() {
        let continuation = playbackFinished
        playbackFinished = nil
        continuation?.resume()
    }

    private func finishSpeaking() {
        guard isSpeaking else { return }
        isSpeaking = false
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func activateAudioSession() {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? session.setActive(true)
        #endif
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.resumePlayback() }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in self?.resumePlayback() }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.resumePlayback() }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.resumePlayback() }
    }
}
