import Foundation
import Testing
@testable import Core

@Test
func channelSessionStoreCreatesClosesAndReopensSessions() async throws {
    let workspaceRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("channel-session-store-\(UUID().uuidString)", isDirectory: true)
    let store = ChannelSessionFileStore(workspaceRootURL: workspaceRootURL)

    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let firstSummary = try await store.recordUserMessage(
        channelId: "support",
        userId: "user-1",
        content: "First message",
        createdAt: startedAt
    )
    #expect(firstSummary.status == .open)
    #expect(firstSummary.messageCount == 1)

    let updatedSummary = try await store.recordAssistantMessage(
        channelId: "support",
        content: "Assistant reply",
        createdAt: startedAt.addingTimeInterval(10)
    )
    #expect(updatedSummary.sessionId == firstSummary.sessionId)
    #expect(updatedSummary.messageCount == 2)
    #expect(updatedSummary.updatedAt == startedAt.addingTimeInterval(10))
    #expect(updatedSummary.lastMessagePreview == "Assistant reply")

    _ = try await store.expireInactiveSessions(
        timeoutByChannel: ["support": 1],
        referenceDate: startedAt.addingTimeInterval(90)
    )

    let closedSessions = try await store.listSessions(status: .closed)
    #expect(closedSessions.count == 1)
    #expect(closedSessions.first?.sessionId == firstSummary.sessionId)
    #expect(closedSessions.first?.closedAt == startedAt.addingTimeInterval(90))

    let activeSessionsAfterClose = try await store.listSessions(status: .open)
    #expect(activeSessionsAfterClose.isEmpty)

    let historyAfterClose = try await store.getMessageHistory(channelId: "support", limit: 10)
    #expect(historyAfterClose.isEmpty)

    let reopenedSummary = try await store.recordUserMessage(
        channelId: "support",
        userId: "user-1",
        content: "Second session message",
        createdAt: startedAt.addingTimeInterval(120)
    )
    #expect(reopenedSummary.status == .open)
    #expect(reopenedSummary.sessionId != firstSummary.sessionId)
    #expect(reopenedSummary.messageCount == 1)

    let activeSessions = try await store.listSessions(status: .open)
    #expect(activeSessions.count == 1)
    #expect(activeSessions.first?.sessionId == reopenedSummary.sessionId)

    let allSessions = try await store.listSessions()
    #expect(allSessions.count == 2)
}
