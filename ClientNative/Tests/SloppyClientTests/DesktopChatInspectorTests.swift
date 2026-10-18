#if os(macOS)
import Testing
import SloppyClientCore
@testable import SloppyClient

@Suite("Desktop chat results")
struct DesktopChatInspectorTests {
    @Test func resultsExcludeUserUploadsAndKeepLatestAttachmentMetadata() {
        let upload = ChatAttachment(id: "upload", name: "input.png", mimeType: "image/png", sizeBytes: 12)
        let first = ChatAttachment(id: "report", name: "report.md", mimeType: "text/markdown", sizeBytes: 0)
        let completed = ChatAttachment(id: "report", name: "report.md", mimeType: "text/markdown", sizeBytes: 512,
                                       relativePath: "output/report.md")
        let toolResult = ChatAttachment(id: "profile", name: "cpu.json", mimeType: "application/json", sizeBytes: 128,
                                        relativePath: "output/cpu.json")
        let messages: [ChatMessage] = [
            .init(role: .user, segments: [.init(kind: .attachment, attachment: upload)]),
            .init(role: .assistant, segments: [.init(kind: .attachment, attachment: first)]),
            .init(role: .system, segments: [.init(kind: .toolResult, attachment: toolResult)]),
            .init(role: .assistant, segments: [.init(kind: .attachment, attachment: completed)]),
        ]
        #expect(DesktopChatOutputs.attachments(in: messages) == [completed, toolResult])
    }

    @Test func ordinaryToolTextDoesNotBecomeAnOutputFile() {
        let messages: [ChatMessage] = [
            .init(role: .system, segments: [.init(kind: .toolResult, text: "Created report.md; 12 tests passed")]),
            .init(role: .assistant, segments: [.init(kind: .text, text: "See report.md")]),
        ]
        #expect(DesktopChatOutputs.attachments(in: messages).isEmpty)
    }
}
#endif
