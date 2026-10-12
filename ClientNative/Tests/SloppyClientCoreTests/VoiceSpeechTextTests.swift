import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Voice speech text")
struct VoiceSpeechTextTests {
    @Test("Markdown markup is not read aloud")
    func stripsMarkdown() {
        let markdown = """
        # Title

        Some **bold** text with a [link](https://example.com) and `code`.

        ```swift
        let hidden = 1
        ```

        - first item
        """
        let plain = VoiceSpeechText.plainText(fromMarkdown: markdown)
        #expect(plain.contains("Title"))
        #expect(plain.contains("Some bold text with a link and code."))
        #expect(plain.contains("first item"))
        #expect(!plain.contains("hidden"))
        #expect(!plain.contains("**"))
        #expect(!plain.contains("https://"))
    }

    @Test("Short sentences merge and the first chunk starts early")
    func chunksMergeShortSentences() {
        let text = "Ok. Done. Это длинное предложение, которое точно превышает минимальную длину. Ещё одно предложение после него."
        let chunks = VoiceSpeechText.speechChunks(from: text, minCharacters: 40)
        #expect(chunks.count >= 2)
        #expect(chunks[0].hasPrefix("Ok. Done."))
        #expect(chunks.joined(separator: " ").contains("Ещё одно предложение"))
    }

    @Test("Oversized text is split to the request limit")
    func respectsLimit() {
        let text = String(repeating: "слово ", count: 1_000)
        let chunks = VoiceSpeechText.speechChunks(from: text, minCharacters: 40, maxCharacters: 200)
        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { $0.count <= 200 })
    }

    @Test("Empty input produces no chunks")
    func empty() {
        #expect(VoiceSpeechText.speechChunks(from: "  \n ").isEmpty)
    }
}

@Suite("Voice config and fallback")
struct VoiceConfigTests {
    @Test("Auto language is omitted so the provider detects it")
    func languageHint() {
        #expect(VoiceConfig(input: .init(language: "auto")).transcriptionLanguage == nil)
        #expect(VoiceConfig(input: .init(language: " ")).transcriptionLanguage == nil)
        #expect(VoiceConfig(input: .init(language: "ru")).transcriptionLanguage == "ru")
    }

    @Test("Config decodes the Core response and ignores unknown fields")
    func decodesCoreResponse() throws {
        let json = """
        {"enabled":true,"configuredProvider":"auto","effectiveProvider":"openai",
         "effectiveTranscriptionProvider":"groq","effectiveSpeechProvider":"elevenlabs",
         "openAIConfigured":false,"localAvailable":true,
         "input":{"mode":"auto_submit","language":"ru","previewBeforeSend":false}}
        """
        let config = try JSONDecoder().decode(VoiceConfig.self, from: Data(json.utf8))
        #expect(config.effectiveTranscriptionProvider == "groq")
        #expect(config.input.language == "ru")
        #expect(config.input.previewBeforeSend == false)
    }

    @Test("Only unavailable providers fall back to on-device recognition")
    func fallbackPolicy() {
        #expect(VoiceTranscriptionFallback.allowsOnDeviceRecognition(after: APIError.httpError(statusCode: 409, body: nil)))
        #expect(VoiceTranscriptionFallback.allowsOnDeviceRecognition(after: APIError.httpError(statusCode: 404, body: nil)))
        #expect(VoiceTranscriptionFallback.allowsOnDeviceRecognition(after: URLError(.notConnectedToInternet)))
        #expect(!VoiceTranscriptionFallback.allowsOnDeviceRecognition(after: APIError.httpError(statusCode: 500, body: nil)))
        #expect(!VoiceTranscriptionFallback.allowsOnDeviceRecognition(after: APIError.httpError(statusCode: 400, body: nil)))
    }
}
