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
    #expect(response.agentCapabilities.loadSession == true)
    #expect(response.agentCapabilities.sessionCapabilities?.list != nil)
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
    #expect(listed.sessions.map(\.sessionId).contains(created.sessionId))
    #expect(await recorder.updates.count == 1)
}
