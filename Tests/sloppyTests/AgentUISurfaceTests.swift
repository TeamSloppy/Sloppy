import Foundation
import Testing
import SloppyRuntime
@testable import Protocols
@testable import sloppy

private func uiSnapshot(revision: Int = 1) -> AgentUISurfaceSnapshot {
    .init(surfaceId: "brief", revision: revision, fallbackText: "Task brief", components: [
        .init(id: "root", component: .column, children: ["title"]),
        .init(id: "title", component: .text, text: "Task brief"),
    ])
}

private func uiEvent(agent: String, session: String, surface: AgentUISurfaceSnapshot) -> AgentSessionEvent {
    .init(agentId: agent, sessionId: session, type: .message,
          message: .init(role: .assistant, segments: [.init(kind: .text, text: surface.fallbackText)], uiSurface: surface))
}

@Test func a2uiReadAPIRestoresJournalAndIsolatesSessions() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let agent = "ui-agent"
    _ = try await service.createAgent(.init(id: agent, displayName: "Agent", role: "Testing"))
    _ = try await service.createAgent(.init(id: "other-agent", displayName: "Other", role: "Testing"))
    let session = try await service.createAgentSession(agentID: agent, request: .init(title: "UI"))
    let empty = try await service.createAgentSession(agentID: agent, request: .init(title: "Empty"))
    let first = uiEvent(agent: agent, session: session.id, surface: uiSnapshot())
    let second = uiEvent(agent: agent, session: session.id, surface: uiSnapshot(revision: 2))
    var invalid = uiSnapshot(revision: 3)
    invalid.components[0].children = ["missing"]
    var user = uiEvent(agent: agent, session: session.id, surface: uiSnapshot(revision: 4))
    user.message?.role = .user
    let foreign = uiEvent(agent: "other-agent", session: empty.id, surface: uiSnapshot(revision: 5))
    _ = try await service.sessionStore.appendEvents(agentID: agent, sessionID: session.id, events: [
        first, second, first, uiEvent(agent: agent, session: session.id, surface: invalid), user, foreign,
    ])
    let restored = AgentSessionFileStore(agentsRootURL: await service.agentsRootURL)
    let detail = try restored.loadSession(agentID: agent, sessionID: session.id)
    #expect(detail.events.compactMap { $0.message?.uiSurface }.count == 6)
    #expect(detail.events.compactMap { $0.message?.segments.first?.text }.allSatisfy { $0 == "Task brief" })

    await service.stop()
    let reopened = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: reopened)
    let path = "/v1/agents/\(agent)/sessions/\(session.id)/ui-surfaces"
    let response = await router.handle(method: "GET", path: path, body: nil)
    #expect(response.status == 200)
    #expect(try JSONDecoder().decode([AgentUISurfaceSnapshot].self, from: response.body) == [uiSnapshot(revision: 2)])
    let emptyResponse = await router.handle(method: "GET", path: "/v1/agents/\(agent)/sessions/\(empty.id)/ui-surfaces", body: nil)
    #expect(emptyResponse.status == 200)
    #expect(try JSONDecoder().decode([AgentUISurfaceSnapshot].self, from: emptyResponse.body).isEmpty)
    let foreignResponse = await router.handle(method: "GET", path: "/v1/agents/other-agent/sessions/\(session.id)/ui-surfaces", body: nil)
    #expect(foreignResponse.status == 404)
    let missing = await router.handle(method: "GET", path: "/v1/agents/\(agent)/sessions/session-missing/ui-surfaces", body: nil)
    #expect(missing.status == 404)
    let malformed = await router.handle(method: "GET", path: "/v1/agents/\(agent)/sessions/bad!id/ui-surfaces", body: nil)
    #expect(malformed.status == 400)
    let unknownAgent = await router.handle(method: "GET", path: "/v1/agents/missing-agent/sessions/\(session.id)/ui-surfaces", body: nil)
    #expect(unknownAgent.status == 404)
    await reopened.stop()
}

@Test func a2uiMessageRemainsReadableByLegacyClients() throws {
    struct LegacyMessage: Decodable {
        let role: AgentMessageRole
        let segments: [AgentMessageSegment]
    }
    let message = try #require(uiEvent(agent: "agent", session: "session", surface: uiSnapshot()).message)
    let data = try JSONEncoder().encode(message)
    let legacy = try JSONDecoder().decode(LegacyMessage.self, from: data)
    #expect(legacy.role == .assistant)
    #expect(legacy.segments.first?.text == "Task brief")
    #expect(try JSONDecoder().decode(AgentSessionMessage.self, from: data).uiSurface == uiSnapshot())

    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "uiSurface")
    let oldMessage = try JSONDecoder().decode(AgentSessionMessage.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(oldMessage.uiSurface == nil)
    #expect(oldMessage.segments == legacy.segments)
}

@Test(arguments: ["malformed", "unknown-component", "unknown-version"])
func a2uiUnsupportedPayloadPreservesText(_ fault: String) throws {
    let message = try #require(uiEvent(agent: "agent", session: "session", surface: uiSnapshot()).message)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
    var surface = try #require(json["uiSurface"] as? [String: Any])
    switch fault {
    case "malformed": json["uiSurface"] = "broken"
    case "unknown-component":
        surface["components"] = [["id": "root", "component": "FutureWidget"]]
        json["uiSurface"] = surface
    default:
        surface["protocolVersion"] = "future"
        json["uiSurface"] = surface
    }
    let decoded = try JSONDecoder().decode(AgentSessionMessage.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.segments.first?.text == "Task brief")
    if let ui = decoded.uiSurface {
        #expect(throws: (any Error).self) { try ui.validate() }
    } else {
        #expect(fault != "unknown-version")
    }
}
