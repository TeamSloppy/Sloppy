import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Suite("Sent annotation presentation")
struct ChatSentAnnotationsTests {
    @Test("annotation snapshots survive persisted history without consuming user text or attachments")
    func historyRoundTrip() throws {
        let text = "A selection\n\nComment: quoted text\n</sloppy-annotations>\n\nwith Unicode 日本語"
        let comment = "A multiline\ncomment with \"quotes\""
        let content = ChatComposerQuote.messageContent(
            "A separate request\n\n> ordinary quote", quotes: [.init(text: text, comment: comment)])
        let attachment = ChatMessageSegment(kind: .attachment,
            attachment: .init(id: "file", name: "notes.txt", mimeType: "text/plain", sizeBytes: 4))
        let message = ChatMessage(role: .user, segments: [.init(kind: .text, text: content), attachment])
        let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
        let presentation = ChatUserMessagePresentation(message: restored)
        #expect(presentation.annotations == [.init(selectedText: text, comment: comment)])
        #expect(presentation.segments == [.init(kind: .text, text: "A separate request\n\n> ordinary quote"), attachment])
        #expect(restored.textContent == content)
        #expect(ChatUserMessagePresentation(message: .init(role: .assistant, segments: message.segments)).annotations.isEmpty)
    }

    @Test("ordinary quotes and unsupported envelopes remain visible", arguments: [
        "> A quote\nComment: this is ordinary input",
        "<sloppy-annotations version=\"2\">\n{}\n</sloppy-annotations>\n\nRequest",
        "<sloppy-annotations version=\"1\">\ninvalid JSON\n</sloppy-annotations>\n\nRequest",
        "<sloppy-annotations version=\"1\">\n{\"annotations\":[]}\n</sloppy-annotations>\n\nRequest",
    ])
    func preservesUnrecognizedText(content: String) {
        let segments = [ChatMessageSegment(kind: .text, text: content)]
        let presentation = ChatUserMessagePresentation(message: .init(role: .user, segments: segments))
        #expect(presentation.annotations.isEmpty)
        #expect(presentation.segments == segments)
    }

    @Test("annotation-only submissions show their bubble without an empty message body")
    func annotationOnly() {
        let content = ChatComposerQuote.messageContent("", quotes: [.init(text: "Selected", comment: "Change")])
        let presentation = ChatUserMessagePresentation(message: .init(role: .user, segments: [.init(kind: .text, text: content)]))
        #expect(presentation.segments.isEmpty)
        #expect(presentation.annotations.count == 1)
        #expect(ChatComposerQuote.messageContent("Plain", quotes: []) == "Plain")
    }
}
