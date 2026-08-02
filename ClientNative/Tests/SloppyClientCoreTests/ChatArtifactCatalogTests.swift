import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Chat artifact catalog")
struct ChatArtifactCatalogTests {
    @Test("extracts attachments from sessions and sorts newest first")
    func extractsAttachmentsFromSessionsAndSortsNewestFirst() {
        let olderDate = Date(timeIntervalSince1970: 1_000)
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let firstSession = ChatSessionSummary(
            id: "session-1",
            agentId: "agent-1",
            title: "First chat"
        )
        let secondSession = ChatSessionSummary(
            id: "session-2",
            agentId: "agent-2",
            title: "Second chat"
        )
        let details = [
            ChatSessionDetail(
                summary: firstSession,
                messages: [
                    ChatMessage(
                        id: "message-1",
                        role: .user,
                        segments: [
                            ChatMessageSegment(kind: .text, text: "Screenshot"),
                            ChatMessageSegment(
                                kind: .attachment,
                                attachment: ChatAttachment(
                                    id: "attachment-1",
                                    name: "screen.png",
                                    mimeType: "image/png",
                                    sizeBytes: 512,
                                    relativePath: "uploads/screen.png"
                                )
                            ),
                        ],
                        createdAt: olderDate
                    ),
                ]
            ),
            ChatSessionDetail(
                summary: secondSession,
                messages: [
                    ChatMessage(
                        id: "message-2",
                        role: .assistant,
                        segments: [
                            ChatMessageSegment(
                                kind: .attachment,
                                attachment: ChatAttachment(
                                    id: "attachment-2",
                                    name: "report.pdf",
                                    mimeType: "application/pdf",
                                    sizeBytes: 2_048
                                )
                            ),
                        ],
                        createdAt: newerDate
                    ),
                ]
            ),
        ]

        let artifacts = ChatArtifactCatalog.build(from: details)

        #expect(artifacts.map(\.name) == ["report.pdf", "screen.png"])
        #expect(artifacts.first?.session == secondSession)
        #expect(artifacts.first?.role == .assistant)
        #expect(artifacts.last?.relativePath == "uploads/screen.png")
    }

    @Test("ignores segments without attachment metadata")
    func ignoresSegmentsWithoutAttachmentMetadata() {
        let session = ChatSessionSummary(
            id: "session-1",
            agentId: "agent-1",
            title: "Chat"
        )
        let detail = ChatSessionDetail(
            summary: session,
            messages: [
                ChatMessage(
                    id: "message-1",
                    role: .assistant,
                    segments: [
                        ChatMessageSegment(kind: .text, text: "Done"),
                        ChatMessageSegment(kind: .attachment),
                    ]
                ),
            ]
        )

        #expect(ChatArtifactCatalog.build(from: [detail]).isEmpty)
    }
}
