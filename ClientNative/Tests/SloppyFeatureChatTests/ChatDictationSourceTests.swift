import Foundation
import Testing

@Suite("Chat dictation source")
struct ChatDictationSourceTests {
    private var viewModelSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    private var apiClientSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyClientCore")
                .appendingPathComponent("SloppyAPIClient.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("view model owns dictation state metering and transcript handoff")
    func viewModelOwnsDictationLifecycle() throws {
        let source = try viewModelSource

        #expect(source.contains("public private(set) var dictationPhase: ChatComposerDictationPhase = .idle"))
        #expect(source.contains("public private(set) var dictationLevels: [CGFloat] = Array(repeating: 0.12, count: 48)"))
        #expect(source.contains("public var isShowingDictationComposer: Bool"))
        #expect(source.contains("private let dictationRecorder = DictationRecorder()"))
        #expect(source.contains("public func startDictation()"))
        #expect(source.contains("public func stopDictation()"))
        #expect(source.contains("private func beginDictationMetering()"))
        #expect(source.contains("private func appendDictationLevel("))
        #expect(source.contains("composerDraft.text = transcript"))
    }

    @Test("api client exposes voice transcription endpoint for dictation")
    func apiClientExposesVoiceTranscriptionEndpoint() throws {
        let source = try apiClientSource

        #expect(source.contains("public func transcribeVoice("))
        #expect(source.contains("try await voice.transcribe(request)"))
    }
}
