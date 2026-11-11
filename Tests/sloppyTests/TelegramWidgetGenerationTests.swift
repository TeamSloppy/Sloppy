import Foundation
import PluginSDK
import Testing
@testable import sloppy

@Suite("Telegram widget session generation")
struct TelegramWidgetGenerationTests {
    @Test func expiredWidgetCannotReopenOrWriteNewConversation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChannelSessionFileStore(workspaceRootURL: root)
        let session = try await store.recordUserMessage(channelId: "telegram-test", userId: "tg:42", content: "Start")
        let owner = TelegramWidgetOwner(channelID: "telegram-test", sessionID: session.sessionId, userID: 42)
        try await store.recordWidgetAction(owner: owner, content: "Valid widget event")
        let original = try await store.loadSessionDetail(sessionID: session.sessionId)
        #expect(original.events.last?.content == "Valid widget event")
        _ = try await store.closeSession(sessionID: session.sessionId)
        await #expect(throws: (any Error).self) {
            try await store.recordWidgetAction(owner: owner, content: "Must not reopen")
        }
        #expect(try await store.listSessions(status: .open).isEmpty)
        let replacement = try await store.recordUserMessage(channelId: "telegram-test", userId: "tg:42", content: "New conversation")
        #expect(replacement.sessionId != owner.sessionID)
        await #expect(throws: (any Error).self) {
            try await store.recordWidgetAction(owner: owner, content: "Must not leak into new generation")
        }
        let detail = try await store.loadSessionDetail(sessionID: replacement.sessionId)
        #expect(!detail.events.contains { $0.content.contains("Must not") })
    }
}
