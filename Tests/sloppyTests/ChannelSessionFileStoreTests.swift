import Foundation
import Protocols
import Testing
@testable import sloppy

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

@Test
func channelSessionStorePersistsTechnicalEventsWithoutAffectingMessageCounters() async throws {
    let workspaceRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("channel-session-technical-\(UUID().uuidString)", isDirectory: true)
    let store = ChannelSessionFileStore(workspaceRootURL: workspaceRootURL)

    let startedAt = Date(timeIntervalSince1970: 1_700_000_500)
    let initialSummary = try await store.recordUserMessage(
        channelId: "engineering",
        userId: "user-42",
        content: "Check deployment status",
        createdAt: startedAt
    )

    let afterThinking = try await store.recordThinking(
        channelId: "engineering",
        content: "Evaluating route and deciding whether tools are needed.",
        createdAt: startedAt.addingTimeInterval(2)
    )
    #expect(afterThinking.sessionId == initialSummary.sessionId)
    #expect(afterThinking.messageCount == 1)
    #expect(afterThinking.lastMessagePreview == "Check deployment status")

    let afterToolCall = try await store.recordToolCall(
        channelId: "engineering",
        tool: "web.search",
        arguments: .object(["query": .string("deployment health")]),
        reason: "Need latest service status",
        createdAt: startedAt.addingTimeInterval(4)
    )
    #expect(afterToolCall.messageCount == 1)
    #expect(afterToolCall.lastMessagePreview == "Check deployment status")

    let afterToolResult = try await store.recordToolResult(
        channelId: "engineering",
        tool: "web.search",
        ok: true,
        data: .object(["resultCount": .number(3)]),
        error: nil,
        durationMs: 120,
        createdAt: startedAt.addingTimeInterval(6)
    )
    #expect(afterToolResult.messageCount == 1)
    #expect(afterToolResult.lastMessagePreview == "Check deployment status")

    let finalSummary = try await store.recordAssistantMessage(
        channelId: "engineering",
        content: "Deployment looks healthy.",
        createdAt: startedAt.addingTimeInterval(8)
    )
    #expect(finalSummary.messageCount == 2)
    #expect(finalSummary.lastMessagePreview == "Deployment looks healthy.")

    let detail = try await store.loadSessionDetail(sessionID: initialSummary.sessionId)
    let eventTypes = detail.events.map(\.type)
    #expect(eventTypes == [.sessionOpened, .userMessage, .thinking, .toolCall, .toolResult, .assistantMessage])
}
