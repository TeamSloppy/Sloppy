import Foundation
import Testing
@testable import SloppyClientCore

private let isoDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

@Suite("ChatModels")
struct ChatModelsTests {

    @Test("ChatMessage decodes role and text segments from JSON")
    func chatMessageDecoding() throws {
        let json = """
        {
            "id": "msg-1",
            "role": "user",
            "segments": [{"kind": "text", "text": "Hello"}],
            "createdAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let msg = try isoDecoder.decode(ChatMessage.self, from: json)

        #expect(msg.id == "msg-1")
        #expect(msg.role == .user)
        #expect(msg.textContent == "Hello")
    }

    @Test("ChatMessage textContent concatenates multiple text segments")
    func chatMessageTextContent() {
        let msg = ChatMessage(
            id: "m1",
            role: .assistant,
            segments: [
                ChatMessageSegment(kind: .text, text: "Foo"),
                ChatMessageSegment(kind: .text, text: " bar")
            ]
        )

        #expect(msg.textContent == "Foo bar")
    }

    @Test("ChatMessage textContent ignores non-text segments")
    func chatMessageIgnoresThinkingSegments() {
        let msg = ChatMessage(
            id: "m2",
            role: .assistant,
            segments: [
                ChatMessageSegment(kind: .thinking, text: "internal"),
                ChatMessageSegment(kind: .text, text: "visible")
            ]
        )

        #expect(msg.textContent == "visible")
    }

    @Test("ChatSessionSummary decodes from JSON")
    func chatSessionSummaryDecoding() throws {
        let json = """
        {
            "id": "sess-1",
            "agentId": "agent-1",
            "title": "My Chat",
            "messageCount": 5,
            "updatedAt": "2026-01-01T00:00:00Z",
            "kind": "chat"
        }
        """.data(using: .utf8)!

        let summary = try isoDecoder.decode(ChatSessionSummary.self, from: json)

        #expect(summary.id == "sess-1")
        #expect(summary.agentId == "agent-1")
        #expect(summary.title == "My Chat")
        #expect(summary.messageCount == 5)
        #expect(summary.kind == "chat")
    }

    @Test("ChatStreamUpdate sessionReady kind decodes")
    func chatStreamUpdateSessionReady() throws {
        let json = """
        {
            "kind": "session_ready",
            "cursor": 0
        }
        """.data(using: .utf8)!

        let update = try isoDecoder.decode(ChatStreamUpdate.self, from: json)

        #expect(update.kind == .sessionReady)
        #expect(update.cursor == 0)
        #expect(update.message == nil)
    }

    @Test("ChatStreamUpdate sessionError extracts errorText")
    func chatStreamUpdateSessionError() throws {
        let json = """
        {
            "kind": "session_error",
            "cursor": 3,
            "message": "Failed to stream"
        }
        """.data(using: .utf8)!

        let update = try isoDecoder.decode(ChatStreamUpdate.self, from: json)

        #expect(update.kind == .sessionError)
        #expect(update.errorText == "Failed to stream")
        #expect(update.message == nil)
    }

    @Test("ChatStreamUpdate sessionEvent extracts embedded message")
    func chatStreamUpdateSessionEvent() throws {
        let json = """
        {
            "kind": "session_event",
            "cursor": 1,
            "event": {
                "id": "evt-1",
                "type": "message",
                "message": {
                    "id": "msg-2",
                    "role": "assistant",
                    "segments": [{"kind": "text", "text": "Hi there"}],
                    "createdAt": "2026-01-01T00:00:00Z"
                }
            }
        }
        """.data(using: .utf8)!

        let update = try isoDecoder.decode(ChatStreamUpdate.self, from: json)

        #expect(update.kind == .sessionEvent)
        #expect(update.cursor == 1)
        #expect(update.message?.id == "msg-2")
        #expect(update.message?.textContent == "Hi there")
    }

    @Test("AppNotification decodes type and fields")
    func appNotificationDecoding() throws {
        let json = """
        {
            "id": "notif-1",
            "type": "agent_error",
            "title": "Agent Crashed",
            "message": "Out of memory",
            "timestamp": "2026-01-01T00:00:00Z",
            "metadata": {"agentId": "agent-42"}
        }
        """.data(using: .utf8)!

        let notif = try isoDecoder.decode(AppNotification.self, from: json)

        #expect(notif.id == "notif-1")
        #expect(notif.type == .agentError)
        #expect(notif.title == "Agent Crashed")
        #expect(notif.message == "Out of memory")
        #expect(notif.metadata["agentId"] == "agent-42")
    }

    @Test("AppNotification confirmation type decodes")
    func appNotificationConfirmationDecoding() throws {
        let json = """
        {
            "id": "n2",
            "type": "confirmation",
            "title": "Done",
            "message": "Task completed",
            "timestamp": "2026-01-01T00:00:00Z",
            "metadata": {}
        }
        """.data(using: .utf8)!

        let notif = try isoDecoder.decode(AppNotification.self, from: json)

        #expect(notif.type == .confirmation)
    }

    @Test("AppNotificationType raw values match server format")
    func appNotificationTypeRawValues() {
        #expect(AppNotificationType.agentError.rawValue == "agent_error")
        #expect(AppNotificationType.systemError.rawValue == "system_error")
        #expect(AppNotificationType.pendingApproval.rawValue == "pending_approval")
        #expect(AppNotificationType.confirmation.rawValue == "confirmation")
    }
}
