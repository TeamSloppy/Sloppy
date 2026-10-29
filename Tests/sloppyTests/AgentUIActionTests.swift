import Foundation
import Testing
@testable import Protocols
@testable import sloppy

extension CoreService { func holdUIInboxForTesting() { sessionMessageIsStopping = true } }
private let actionForm =
    #"[{"version":"v0.9.1","createSurface":{"surfaceId":"form","catalogId":"urn:sloppy:a2ui:catalog:v1"}},{"version":"v0.9.1","updateComponents":{"surfaceId":"form","components":[{"id":"root","component":"Column","children":["name","go"]},{"id":"name","component":"TextField","label":"Name","binding":"/name","required":true},{"id":"go","component":"Button","label":"Continue","action":"submit"}]}}]"#

@Test func a2uiActionIsAcceptedOnceAndRestoresBeforeDelivery() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(.init(id: "forms", displayName: "Forms", role: "Testing"))
    let session = try await service.createAgentSession(agentID: "forms", request: .init(title: "Form"))
    await service.holdUIInboxForTesting()
    _ = try await service.renderAgentUI(
        agentID: "forms", sessionID: session.id, request: .init(messages: actionForm, expectedRevision: 0, fallbackText: "Name"))
    let action = AgentUISubmission(actionId: UUID().uuidString, revision: 1, componentId: "go", values: ["/name": .string("Ada")])
    let router = CoreRouter(service: service)
    let path = "/v1/agents/forms/sessions/\(session.id)/ui-surfaces/form/actions"
    let body = try JSONEncoder().encode(action)
    let first = await router.handle(method: "POST", path: path, body: body)
    #expect(first.status == 200)
    let repeated = await router.handle(method: "POST", path: path, body: body)
    #expect(repeated.status == 200)
    let detail = try await service.getAgentSession(agentID: "forms", sessionID: session.id)
    #expect(detail.events.filter { $0.message?.id == action.actionId }.count == 1)
    #expect(detail.events.first { $0.message?.id == action.actionId }?.message?.segments.first?.text == "Continue\nName: Ada")
    #expect(try await service.listAgentUISurfaces(agentID: "forms", sessionID: session.id).first?.submittedActionId == action.actionId)
    let stale = AgentUISubmission(actionId: UUID().uuidString, revision: 1, componentId: "go", values: action.values)
    let staleBody = try JSONEncoder().encode(stale)
    #expect(await router.handle(method: "POST", path: path, body: staleBody).status == 409)
    var conflict = action
    conflict.values["/name"] = .string("Other")
    let conflictBody = try JSONEncoder().encode(conflict)
    #expect(await router.handle(method: "POST", path: path, body: conflictBody).status == 409)
    await service.stop()
    let restarted = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    await restarted.holdUIInboxForTesting()
    let receipt = try await restarted.submitAgentUIAction(agentID: "forms", sessionID: session.id, surfaceID: "form", submission: action)
    #expect(receipt.actionId == action.actionId)
    #expect(
        try await restarted.getAgentSession(agentID: "forms", sessionID: session.id).events.filter { $0.message?.id == action.actionId }
            .count == 1)
    await restarted.stop()
}

@Test func a2uiCapabilityIsExplicitAndCannotBeGrantedByToolArguments() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(.init(id: "caps", displayName: "Caps", role: "Testing"))
    let session = try await service.createAgentSession(agentID: "caps", request: .init(title: "Capabilities"))
    let denied = await service.invokeToolFromRuntime(
        agentID: "caps", sessionID: session.id, request: .init(tool: "ui.catalog", arguments: ["supportsA2UI": .bool(true)]))
    #expect(denied.error?.code == "ui_client_unsupported")
    let event = AgentSessionEvent(
        agentId: "caps", sessionId: session.id, type: .message,
        message: .init(role: .user, segments: [.init(kind: .text, text: "Form")], supportsA2UI: true))
    _ = try await service.sessionStore.appendEvents(agentID: "caps", sessionID: session.id, events: [event])
    let allowed = await service.invokeToolFromRuntime(
        agentID: "caps", sessionID: session.id, request: .init(tool: "ui.catalog", arguments: [:]))
    #expect(allowed.ok)
    await service.stop()
}

@Test func a2uiSkillRoutesAutomaticallyAndKeepsUserEdits() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ui-skill-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = AgentCatalogFileStore(agentsRootURL: root)
    _ = try catalog.createAgent(.init(id: "skill", displayName: "Skill", role: "Testing"), availableModels: [])
    let store = AgentSkillsFileStore(agentsRootURL: root, sharedSkillsRootURLs: [])
    _ = try store.provisionBuiltInSkills(agentID: "skill")
    let installed = try store.getSkill(agentID: "skill", skillID: BuiltInSkillCatalog.a2uiID)
    #expect(installed.autoRoute?.isEmpty == false)
    let path = URL(fileURLWithPath: installed.localPath).appendingPathComponent("SKILL.md")
    try "Custom UI instructions".write(to: path, atomically: true, encoding: .utf8)
    _ = try store.provisionBuiltInSkills(agentID: "skill")
    #expect(try String(contentsOf: path, encoding: .utf8) == "Custom UI instructions")
}

extension CoreService {
    func seedUICheckpointForTesting(agent: String, session: String, submission: AgentUISubmission) throws {
        sessionMessageIsStopping = true
        let surface = try agentUISurfaceStates(agentID: agent, sessionID: session)[0]
        let accepted = try surface.accepting(submission)
        let request = AgentSessionPostMessageRequest(
            userId: "local", content: "[UI action]\n{}", clientMessageId: submission.actionId, supportsA2UI: true)
        _ = try sessionMessageInbox().enqueue(
            .init(
                id: submission.actionId, agentId: agent, sessionId: session, request: request, uiSnapshot: accepted,
                uiSubmission: submission))
    }
    func createUIWorkerForTesting(agentID: String, parent: String) throws -> AgentSessionSummary {
        try sessionStore.createSession(agentID: agentID, request: .init(title: "Child", parentSessionId: parent, kind: .longChatWorker))
    }
    func holdLongUIForTesting() {
        sessionMessageIsStopping = true
        longChatIsStopping = true
    }
}

@Test func a2uiAcceptedCheckpointRepairsMissingJournalRecord() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(.init(id: "checkpoint-ui", displayName: "UI", role: "Testing"))
    let session = try await service.createAgentSession(agentID: "checkpoint-ui", request: .init(title: "Recovery"))
    _ = try await service.renderAgentUI(
        agentID: "checkpoint-ui", sessionID: session.id, request: .init(messages: actionForm, expectedRevision: 0, fallbackText: "Name"))
    let action = AgentUISubmission(actionId: UUID().uuidString, revision: 1, componentId: "go", values: ["/name": .string("Restored")])
    try await service.seedUICheckpointForTesting(agent: "checkpoint-ui", session: session.id, submission: action)
    let recovered = try await service.listAgentUISurfaces(agentID: "checkpoint-ui", sessionID: session.id)
    #expect(recovered.first?.submittedActionId == action.actionId)
    _ = try await service.submitAgentUIAction(agentID: "checkpoint-ui", sessionID: session.id, surfaceID: "form", submission: action)
    let events = try await service.getAgentSession(agentID: "checkpoint-ui", sessionID: session.id).events
    #expect(events.filter { $0.id == "ui-accepted-" + action.actionId }.count == 1)
    #expect(events.filter { $0.message?.id == action.actionId }.count == 1)
    await service.stop()
}

@Test func a2uiLongChatActionRequiresConversationOwner() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(.init(id: "long-ui", displayName: "UI", role: "Testing"))
    let session = try await service.openLongChat(agentID: "long-ui", userID: "owner")
    await service.holdLongUIForTesting()
    _ = try await service.renderAgentUI(
        agentID: "long-ui", sessionID: session.id, request: .init(messages: actionForm, expectedRevision: 0, fallbackText: "Name"))
    let action = AgentUISubmission(actionId: UUID().uuidString, revision: 1, componentId: "go", values: ["/name": .string("Owner")])
    await #expect(throws: CoreService.AgentUIError.self) {
        try await service.submitAgentUIAction(
            agentID: "long-ui", sessionID: session.id, surfaceID: "form", submission: action, userID: "other")
    }
    #expect(try await service.listAgentUISurfaces(agentID: "long-ui", sessionID: session.id).first?.submittedActionId == nil)
    let child = try await service.createUIWorkerForTesting(agentID: "long-ui", parent: session.id)
    _ = try await service.renderAgentUI(
        agentID: "long-ui", sessionID: child.id,
        request: .init(messages: actionForm, expectedRevision: 0, fallbackText: "Name"))
    await #expect(throws: CoreService.AgentUIError.self) {
        try await service.submitAgentUIAction(
            agentID: "long-ui", sessionID: child.id, surfaceID: "form", submission: action, userID: "other")
    }
    #expect(try await service.listAgentUISurfaces(agentID: "long-ui", sessionID: child.id).first?.submittedActionId == nil)

    let accepted = try await service.submitAgentUIAction(
        agentID: "long-ui", sessionID: session.id, surfaceID: "form", submission: action, userID: "owner")
    #expect(accepted.status == "accepted")
    await service.stop()
}

@Test func a2uiTUIKeepsSubmissionOnUncertainDelivery() {
    #expect(!SloppyTUIForm.submissionWasRejected(URLError(.timedOut)))
    #expect(!SloppyTUIForm.submissionWasRejected(CLIClientError.httpError(503, "Unavailable")))
    #expect(SloppyTUIForm.submissionWasRejected(CLIClientError.httpError(409, "Stale revision")))
    #expect(SloppyTUIForm.submissionWasRejected(RemoteSloppyTUIBackendError.httpError(400)))
    #expect(SloppyTUIForm.submissionWasRejected(CoreService.AgentUIError.invalidAction))
}
