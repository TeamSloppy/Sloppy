import Foundation
import Logging
import Testing
@testable import sloppy
@testable import Protocols
import SloppyNodeCore

private struct RemoteBackendTestTimeout: Error {}

@Test
func remoteSloppyTUIBackendReadsProjectsSessionsAndSSE() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: .sloppy(label: "sloppy.tui.remote-backend.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    let port = try #require(server.boundPort)
    let project = try await service.createProject(
        ProjectCreateRequest(id: "remote-backend", name: "Remote Backend")
    ).project
    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "remote-agent",
            displayName: "Remote Agent",
            role: "Remote backend regression"
        )
    )

    let node = CoreConfig.Node(
        id: "remote-test",
        title: "Remote Test",
        url: "http://127.0.0.1:\(port)",
        token: "dev-token",
        kind: .sloppyInstance
    )
    let backend = RemoteSloppyTUIBackend(node: node, projectID: project.id)

    let projects = try await backend.listProjects()
    #expect(projects.contains(where: { $0.id == project.id }))

    let fetchedProject = try await backend.getProject(id: project.id)
    #expect(fetchedProject.name == "Remote Backend")

    let agents = try await backend.listAgents(includeSystem: false)
    #expect(agents.contains(where: { $0.id == "remote-agent" }))

    let session = try await backend.createAgentSession(
        agentID: "remote-agent",
        request: AgentSessionCreateRequest(title: "Remote Session", projectId: project.id)
    )
    #expect(session.projectId == project.id)

    let sessions = try await backend.listAgentSessions(agentID: "remote-agent", projectID: project.id)
    #expect(sessions.contains(where: { $0.id == session.id }))

    let stream: AsyncStream<AgentSessionStreamUpdate> = try await backend.streamAgentSessionEvents(agentID: "remote-agent", sessionID: session.id)
    let firstUpdate = try await firstStreamValue(stream)
    #expect(firstUpdate.kind == .sessionReady)
    #expect(firstUpdate.summary?.id == session.id)

    let approval = await service.toolApprovalService.createPending(
        agentId: "remote-agent",
        sessionId: session.id,
        displaySessionId: nil,
        channelId: nil,
        topicId: nil,
        request: ToolInvocationRequest(tool: "files.write", arguments: ["path": .string("/tmp/remote.txt")]),
        approvalKind: .riskyTool
    )
    let pendingApprovals = try await backend.listPendingToolApprovals()
    #expect(pendingApprovals.contains(where: { $0.id == approval.id }))

    let approved = try await backend.approveToolApproval(
        id: approval.id,
        request: ToolApprovalDecisionRequest(decidedBy: "remote-test", scope: .once)
    )
    #expect(approved.status == ToolApprovalStatus.approved)
}

@Test
func meshSloppyTUIBackendReadsProjectsAndAgentsThroughCoreProxy() async throws {
    let configURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tests-\(UUID().uuidString)")
        .appendingPathComponent("node.json")
    let identity = NodeIdentityGenerator.makeIdentity(
        name: "Local Mesh",
        roles: ["controller"],
        capabilities: ["run_agent", "git"]
    )
    let configStore = NodeConfigStore(configURL: configURL)
    try configStore.save(NodeConfig(identity: identity, relayURL: "http://mesh.example.test"))
    let service = CoreService(config: .test, nodeConfigStore: configStore)
    let project = try await service.createProject(
        ProjectCreateRequest(id: "mesh-backend", name: "Mesh Backend")
    ).project
    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "mesh-agent",
            displayName: "Mesh Agent",
            role: "Mesh backend regression"
        )
    )
    let node = MeshNodeRecord(
        id: identity.nodeId,
        name: identity.name,
        publicKey: identity.publicKey,
        roles: identity.roles,
        status: .online,
        capabilities: identity.capabilities
    )
    let backend = MeshSloppyTUIBackend(service: service, node: node, projectID: project.id)

    let projects = try await backend.listProjects()
    #expect(projects.contains(where: { $0.id == project.id }))

    let agents = try await backend.listAgents(includeSystem: false)
    #expect(agents.contains(where: { $0.id == "mesh-agent" }))
}

private func firstStreamValue<T: Sendable>(_ stream: AsyncStream<T>) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let value = await iterator.next() else {
                throw RemoteBackendTestTimeout()
            }
            return value
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw RemoteBackendTestTimeout()
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}
