import ACPModel
import Foundation
import Testing
@testable import Protocols
@testable import sloppy

private actor ACPServerUpdateRecorder {
    private(set) var updates: [(SessionId, SessionUpdate)] = []

    func append(sessionId: SessionId, update: SessionUpdate) {
        updates.append((sessionId, update))
    }
}

private func makeACPServerService() async throws -> CoreService {
    var config = CoreConfig.test
    config.acp.server = .init(enabled: true, agentId: "dev", cwd: nil)
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(
        AgentCreateRequest(id: "dev", displayName: "Dev", role: "Developer", isSystem: false)
    )
    return service
}

@Test
func sloppyACPServerInitializeAdvertisesSessionCapabilities() async throws {
    let service = try await makeACPServerService()
    let recorder = ACPServerUpdateRecorder()
    let delegate = SloppyACPServerDelegate(
        service: service,
        agentID: "dev",
        defaultCwd: nil,
        sendUpdate: { sessionId, update in await recorder.append(sessionId: sessionId, update: update) }
    )

    let response = try await delegate.handleInitialize(
        InitializeRequest(
            protocolVersion: 1,
            clientCapabilities: ClientCapabilities(
                fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
                terminal: true
            )
        )
    )

    #expect(response.protocolVersion == 1)
    #expect(response.agentInfo?.name == "sloppy")
    #expect(response.agentInfo?.title == "Sloppy")
    #expect(response.agentCapabilities.loadSession == true)
    #expect(response.agentCapabilities.mcpCapabilities == nil)
    #expect(response.agentCapabilities.promptCapabilities?.image == false)
    #expect(response.agentCapabilities.promptCapabilities?.audio == nil)
    #expect(response.agentCapabilities.promptCapabilities?.embeddedContext == nil)
    #expect(response.agentCapabilities.sessionCapabilities?.close == nil)
    #expect(response.agentCapabilities.sessionCapabilities?.list != nil)
    #expect(response.agentCapabilities.sessionCapabilities?.resume != nil)
    #expect(response.authMethods?.isEmpty == true)
}

@Test
func sloppyACPServerCreatesAndListsSessionsForConfiguredAgent() async throws {
    let service = try await makeACPServerService()
    let recorder = ACPServerUpdateRecorder()
    let delegate = SloppyACPServerDelegate(
        service: service,
        agentID: "dev",
        defaultCwd: "/tmp",
        sendUpdate: { sessionId, update in await recorder.append(sessionId: sessionId, update: update) }
    )

    let created = try await delegate.handleNewSession(
        NewSessionRequest(cwd: FileManager.default.temporaryDirectory.path)
    )
    let listed = try await delegate.handleListSessions(ListSessionsRequest(cwd: "/tmp"))

    #expect(!created.sessionId.value.isEmpty)
    #expect(created.modes == nil)
    #expect(created.models?.currentModelId == "mock:test-model")
    #expect(created.models?.availableModels.map(\.modelId).contains("mock:test-model") == true)
    #expect(listed.sessions.map(\SessionInfo.sessionId).contains(created.sessionId))
    #expect(listed.nextCursor == nil)
    #expect(await recorder.updates.count == 1)
}

@Test
func sloppyACPServerNewSessionScopesProjectFromCwd() async throws {
    let service = try await makeACPServerService()
    let recorder = ACPServerUpdateRecorder()
    let delegate = SloppyACPServerDelegate(
        service: service,
        agentID: "dev",
        defaultCwd: nil,
        sendUpdate: { sessionId, update in await recorder.append(sessionId: sessionId, update: update) }
    )
    let cwd = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-acp-project-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cwd) }

    let created = try await delegate.handleNewSession(NewSessionRequest(cwd: cwd.path))
    let detail = try await service.getAgentSession(agentID: "dev", sessionID: created.sessionId.value)
    let projectID = try #require(detail.summary.projectId)
    let project = try await service.getProject(id: projectID)

    let result = await service.invokeToolFromRuntime(
        agentID: "dev",
        sessionID: created.sessionId.value,
        request: ToolInvocationRequest(tool: "project.current", arguments: [:]),
        recordSessionEvents: false
    )

    #expect(project.repoPath == cwd.path)
    #expect(result.ok == true)
    #expect(result.data?.asObject?["projectId"]?.asString == projectID)
}

@Test
func sloppyACPServerLoadSessionDoesNotAdvertiseUnsupportedModes() async throws {
    let service = try await makeACPServerService()
    let recorder = ACPServerUpdateRecorder()
    let delegate = SloppyACPServerDelegate(
        service: service,
        agentID: "dev",
        defaultCwd: "/tmp",
        sendUpdate: { sessionId, update in await recorder.append(sessionId: sessionId, update: update) }
    )

    let created = try await delegate.handleNewSession(NewSessionRequest(cwd: "/tmp"))
    let loaded = try await delegate.handleLoadSession(
        LoadSessionRequest(sessionId: created.sessionId, cwd: "/tmp")
    )

    #expect(loaded.sessionId == created.sessionId)
    #expect(loaded.modes == nil)
    #expect(loaded.models?.currentModelId == "mock:test-model")
}

@Test
func sloppyACPServerSetModelPersistsAgentSelection() async throws {
    let service = try await makeACPServerService()
    let recorder = ACPServerUpdateRecorder()
    let delegate = SloppyACPServerDelegate(
        service: service,
        agentID: "dev",
        defaultCwd: "/tmp",
        sendUpdate: { sessionId, update in await recorder.append(sessionId: sessionId, update: update) }
    )

    let created = try await delegate.handleNewSession(NewSessionRequest(cwd: "/tmp"))
    let response = try await delegate.handleSetModel(
        SetModelRequest(sessionId: created.sessionId, modelId: "mock:test-model")
    )
    let config = try await service.getAgentConfig(agentID: "dev")

    #expect(response.success == true)
    #expect(config.selectedModel == "mock:test-model")
}

@Test
func sloppyACPServerLoadSessionReplaysStoredTranscript() async throws {
    let service = try await makeACPServerService()
    let recorder = ACPServerUpdateRecorder()
    let delegate = SloppyACPServerDelegate(
        service: service,
        agentID: "dev",
        defaultCwd: "/tmp",
        sendUpdate: { sessionId, update in await recorder.append(sessionId: sessionId, update: update) }
    )

    let created = try await delegate.handleNewSession(NewSessionRequest(cwd: "/tmp"))
    let events = [
        AgentSessionEvent(
            agentId: "dev",
            sessionId: created.sessionId.value,
            type: .message,
            message: AgentSessionMessage(
                role: .user,
                segments: [AgentMessageSegment(kind: .text, text: "Hello from VS Code")],
                userId: "acp"
            )
        ),
        AgentSessionEvent(
            agentId: "dev",
            sessionId: created.sessionId.value,
            type: .message,
            message: AgentSessionMessage(
                role: .assistant,
                segments: [AgentMessageSegment(kind: .text, text: "Hello from Sloppy")]
            )
        ),
    ]
    _ = try await service.appendAgentSessionEvents(
        agentID: "dev",
        sessionID: created.sessionId.value,
        request: AgentSessionAppendEventsRequest(events: events)
    )

    _ = try await delegate.handleLoadSession(
        LoadSessionRequest(sessionId: created.sessionId, cwd: "/tmp")
    )

    let updates = await recorder.updates.map(\.1)
    #expect(ACPServerTestHelpers.acpText(updates[safe: 1], expectedCase: "user_message_chunk") == "Hello from VS Code")
    #expect(ACPServerTestHelpers.acpText(updates[safe: 2], expectedCase: "agent_message_chunk") == "Hello from Sloppy")
}

@Test
func acpServerDeltaTrackerConvertsFullDraftsToACPChunks() async {
    let tracker = ACPServerDeltaTracker()

    #expect(await tracker.consume(fullDraft: "Пр") == "Пр")
    #expect(await tracker.consume(fullDraft: "Привет") == "ивет")
    #expect(await tracker.consume(fullDraft: "Привет! Чем") == "! Чем")
    #expect(await tracker.consume(fullDraft: "Привет! Чем") == nil)
    #expect(await tracker.didSendDelta)
}

@Test
func acpServerDeltaTrackerSuppressesFinalAssistantReplayAfterLiveDeltas() async {
    let tracker = ACPServerDeltaTracker()

    _ = await tracker.consume(fullDraft: "Hello")

    #expect(await tracker.shouldForwardFinalAssistantMessage() == false)
}

@Test
func acpServerDeltaTrackerAllowsFinalAssistantMessageWhenNoLiveDeltasWereSent() async {
    let tracker = ACPServerDeltaTracker()

    #expect(await tracker.shouldForwardFinalAssistantMessage() == true)
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private enum ACPServerTestHelpers {
    static func acpText(_ update: SessionUpdate?, expectedCase: String) -> String? {
        switch (expectedCase, update) {
        case ("user_message_chunk", .userMessageChunk(.text(let text))):
            return text.text
        case ("agent_message_chunk", .agentMessageChunk(.text(let text))):
            return text.text
        default:
            return nil
        }
    }
}
