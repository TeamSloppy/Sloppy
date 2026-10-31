import Foundation
import Protocols
import Testing
@testable import sloppy

private func userEvent(agentID: String, sessionID: String, text: String) -> AgentSessionEvent {
    AgentSessionEvent(
        agentId: agentID,
        sessionId: sessionID,
        type: .message,
        message: .init(role: .user, segments: [.init(kind: .text, text: text)])
    )
}

@Test
func forkedSessionCopiesHistoryBeforeSelectedMessage() async throws {
    let service = CoreService(config: .test)
    _ = try await service.createAgent(.init(id: "fork-agent", displayName: "Agent", role: "Testing"))
    let source = try await service.createAgentSession(agentID: "fork-agent", request: .init(title: "Source"))
    let first = userEvent(agentID: "fork-agent", sessionID: source.id, text: "first")
    let second = userEvent(agentID: "fork-agent", sessionID: source.id, text: "second")
    _ = try await service.sessionStore.appendEvents(agentID: "fork-agent", sessionID: source.id, events: [first, second])

    let fork = try await service.createAgentSession(
        agentID: "fork-agent",
        request: .init(
            title: "Fork",
            parentSessionId: nil,
            forkFromSessionId: source.id,
            forkBeforeMessageId: second.message?.id
        )
    )

    let detail = try await service.getAgentSession(agentID: "fork-agent", sessionID: fork.id)
    let texts = detail.events.compactMap { $0.message?.segments.first?.text }
    #expect(texts == ["first"])
    #expect(detail.events.allSatisfy { $0.sessionId == fork.id })
    #expect(detail.summary.parentSessionId == nil)
    #expect(Set(detail.events.map(\.id)).isDisjoint(with: [first.id, second.id]))
}

@Test
func forkedSessionRejectsUnknownMessage() async throws {
    let service = CoreService(config: .test)
    _ = try await service.createAgent(.init(id: "fork-missing", displayName: "Agent", role: "Testing"))
    let source = try await service.createAgentSession(agentID: "fork-missing", request: .init(title: "Source"))

    await #expect(throws: (any Error).self) {
        _ = try await service.createAgentSession(
            agentID: "fork-missing",
            request: .init(forkFromSessionId: source.id, forkBeforeMessageId: "does-not-exist")
        )
    }
}

@Test
func createRequestDecodesForkFields() throws {
    let json = Data(#"{"forkFromSessionId":"s1","forkBeforeMessageId":"m1"}"#.utf8)
    let request = try JSONDecoder().decode(AgentSessionCreateRequest.self, from: json)

    #expect(request.forkFromSessionId == "s1")
    #expect(request.forkBeforeMessageId == "m1")
}

@Test
func forkedSessionCopiesThroughSelectedResponseAndStaysIndependent() async throws {
    let service = CoreService(config: .test)
    let agentID = "fork-through"
    _ = try await service.createAgent(.init(id: agentID, displayName: "Agent", role: "Testing"))
    let source = try await service.createAgentSession(agentID: agentID, request: .init(title: "Source"))
    let first = userEvent(agentID: agentID, sessionID: source.id, text: "question")
    let response = AgentSessionEvent(agentId: agentID, sessionId: source.id, type: .message,
        message: .init(role: .assistant, segments: [.init(kind: .text, text: "selected response")]))
    let later = userEvent(agentID: agentID, sessionID: source.id, text: "later question")
    _ = try await service.sessionStore.appendEvents(agentID: agentID, sessionID: source.id, events: [first, response, later])
    let request = try JSONDecoder().decode(AgentSessionCreateRequest.self, from: JSONEncoder().encode(
        AgentSessionCreateRequest(forkFromSessionId: source.id, forkThroughMessageId: response.message?.id)))
    let fork = try await service.createAgentSession(agentID: agentID, request: request, userID: "owner")
    let extra = userEvent(agentID: agentID, sessionID: source.id, text: "after fork")
    _ = try await service.sessionStore.appendEvents(agentID: agentID, sessionID: source.id, events: [extra])
    let detail = try await service.getAgentSession(agentID: agentID, sessionID: fork.id)
    #expect(detail.events.compactMap(\.message).map { $0.segments.compactMap(\.text).joined() } == ["question", "selected response"])
    #expect(detail.summary.parentSessionId == nil)
    #expect(detail.events.allSatisfy { $0.sessionId == fork.id })
    await #expect(throws: (any Error).self) {
        try await service.createAgentSession(agentID: agentID,
            request: .init(forkFromSessionId: source.id, forkThroughMessageId: "missing"))
    }
    await #expect(throws: (any Error).self) {
        try await service.createAgentSession(agentID: agentID,
            request: .init(forkFromSessionId: source.id, forkBeforeMessageId: response.message?.id,
                           forkThroughMessageId: response.message?.id))
    }
}
