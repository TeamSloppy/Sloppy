import Foundation
import Protocols
import Testing
@testable import sloppy

@Test
func promptSuggestionRequiresCurrentFinishedRunAndValidDraftText() throws {
    let user = message(.user, "Draft the release update.")
    let assistant = message(.assistant, "The update is ready for review.")
    let done = AgentSessionEvent(agentId: "agent", sessionId: "session", type: .runStatus,
        runStatus: .init(id: "run", stage: .done, label: "Done"))
    let events = [user, assistant, done]
    let context = try #require(SessionPromptSuggestionContext(events: events, sourceRunID: "run"))
    #expect(context.prompt.contains("Draft the release update."))
    #expect(context.prompt.contains("The update is ready for review."))
    #expect(SessionPromptSuggestionContext(events: events, sourceRunID: "old") == nil)
    #expect(SessionPromptSuggestionContext(events: events + [message(.user, "Another task")], sourceRunID: "run") == nil)
    #expect(SessionPromptSuggestionContext(events: [user, done], sourceRunID: "run") == nil)
    #expect(SessionPromptSuggestionContext.parse(#"{"text":"Shorten the release update."}"#) == "Shorten the release update.")
    #expect(SessionPromptSuggestionContext.parse(#"{"text":null}"#) == nil)
    #expect(SessionPromptSuggestionContext.parse(#"{"text":"/reset"}"#) == nil)
    #expect(SessionPromptSuggestionContext.parse(#"{"text":"one\ntwo"}"#) == nil)
}

private func message(_ role: AgentMessageRole, _ text: String) -> AgentSessionEvent {
    .init(agentId: "agent", sessionId: "session", type: .message,
        message: .init(role: role, segments: [.init(kind: .text, text: text)]))
}

@Test
func promptSuggestionRouteReusesSamplingWithoutWritingAUserMessage() async throws {
    let config = CoreConfig.test
    let root = config.resolvedWorkspaceRootURL()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(.init(id: "agent", displayName: "Agent", role: "Test"))
    let session = try await service.createAgentSession(agentID: "agent", request: .init())
    let store = await service.sessionStore
    let done = AgentSessionEvent(agentId: "agent", sessionId: session.id, type: .runStatus,
        runStatus: .init(id: "completed", stage: .done, label: "Done"))
    _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
        message(.user, "Draft an update."), message(.assistant, "The draft is ready."), done
    ])
    let before = try store.loadSession(agentID: "agent", sessionID: session.id).events.map(\.id)
    let probe = WorkflowModelProbe(answers: [#"{"text":"Make it shorter."}"#])
    await service.overrideModelProviderForTests(WorkflowModelProvider(probe: probe), defaultModel: "mock:test-model")
    let router = CoreRouter(service: service)
    let path = "/v1/agents/agent/sessions/\(session.id)/prompt-suggestion"
    let payload = Data(#"{"sourceRunId":"completed"}"#.utf8)

    for _ in 0..<2 {
        let response = await router.handle(method: "POST", path: path, body: payload)
        #expect(response.status == 200)
        #expect(try JSONDecoder().decode(SessionPromptSuggestion.self, from: response.body).text == "Make it shorter.")
    }
    #expect(try store.loadSession(agentID: "agent", sessionID: session.id).events.map(\.id) == before)
    _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [message(.user, "Start something else.")])
    let stale = await router.handle(method: "POST", path: path, body: payload)
    #expect(try JSONDecoder().decode(SessionPromptSuggestion.self, from: stale.body).text == nil)
    #expect(await probe.prompts.count == 1)
    await service.shutdownChannelPlugins()
}
