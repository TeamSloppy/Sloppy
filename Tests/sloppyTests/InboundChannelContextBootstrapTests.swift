import Foundation
import Protocols
import Testing
@testable import sloppy

@Test
func inboundChannelTurnRestoresTodayHistoryIntoBootstrap() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "daily-channel-agent",
            displayName: "Daily Channel Agent",
            role: "Keep continuity in external channels."
        )
    )
    let config = try await service.getAgentConfig(agentID: "daily-channel-agent")
    _ = try await service.updateAgentConfig(
        agentID: "daily-channel-agent",
        request: AgentConfigUpdateRequest(
            role: config.role,
            selectedModel: config.selectedModel,
            documents: AgentDocumentBundle(
                userMarkdown: "# User\nPreserve today's context.",
                agentsMarkdown: "# Agent\nExternal channel responder.",
                soulMarkdown: "# Soul\nSteady.",
                identityMarkdown: "# Identity\ndaily-channel-agent"
            ),
            heartbeat: config.heartbeat,
            channelSessions: AgentChannelSessionSettings(
                allowedChannelIds: ["telegram-main"]
            ),
            runtime: config.runtime
        )
    )

    _ = try await service.channelSessionStore.recordUserMessage(
        channelId: "telegram-main",
        userId: "user-1",
        content: "Morning decision: use today's context.",
        createdAt: Date()
    )
    _ = await service.postMessage(
        channelId: "telegram-main",
        userId: "user-1",
        content: "What did we decide earlier?",
        topicId: nil,
        inboundContext: nil
    )

    let restored = await waitForInboundBootstrap(service: service, channelId: "telegram-main")
    let bootstrap = try #require(restored)
    #expect(bootstrap.contains(CoreService.inboundChannelContextBootstrapMarker))
    #expect(bootstrap.contains("[Today channel history]"))
    #expect(bootstrap.contains("Morning decision: use today's context."))
    #expect(bootstrap.contains("[AGENTS.md]"))
    #expect(bootstrap.contains("External channel responder."))

    let sessions = try await service.channelSessionStore.listSessions(status: .open, channelIds: ["telegram-main"])
    let detail = try await service.channelSessionStore.loadSessionDetail(sessionID: try #require(sessions.first?.sessionId))
    #expect(!detail.events.contains(where: { $0.content.contains(CoreService.inboundChannelContextBootstrapMarker) }))
}

@Test
func inboundTodayHistoryBootstrapKeepsFreshTailWhenBudgetIsTight() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let now = Date(timeIntervalSince1970: 1_800_010_000)
    let dayStart = calendar.startOfDay(for: now)

    for index in 0..<12 {
        _ = try await service.channelSessionStore.recordUserMessage(
            channelId: "busy-channel",
            userId: "user-1",
            content: "message-\(index) " + String(repeating: "x", count: 240),
            createdAt: dayStart.addingTimeInterval(TimeInterval(index * 60))
        )
    }

    let context = try #require(await service.todayChannelHistoryContext(
        channelId: "busy-channel",
        now: now,
        calendar: calendar,
        maxCharacters: 900
    ))

    #expect(context.count <= 900)
    #expect(context.contains("message-11"))
    #expect(!context.contains("message-0"))
}

private func waitForInboundBootstrap(service: CoreService, channelId: String) async -> String? {
    for _ in 0..<40 {
        if let bootstrap = await service.runtime.channelBootstrapContent(channelId: channelId) {
            return bootstrap
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
    return nil
}
