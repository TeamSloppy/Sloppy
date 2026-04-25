import Foundation
import Testing
@testable import sloppy
@testable import Protocols

@Suite("Gateway channel tool invocation")
struct GatewayToolInvocationTests {
    private func makeService() -> CoreService {
        CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    }

    private func makeAgent(service: CoreService, agentID: String) async throws {
        _ = try await service.createAgent(
            AgentCreateRequest(id: agentID, displayName: "Gateway Agent", role: "Gateway tool tests")
        )
    }

    @Test("gateway channel tool calls honor linked agent tool policy")
    func gatewayChannelToolCallsHonorAgentPolicy() async throws {
        let service = makeService()
        let agentID = "gateway-tools-\(UUID().uuidString)"
        try await makeAgent(service: service, agentID: agentID)

        _ = try await service.updateAgentToolsPolicy(
            agentID: agentID,
            request: AgentToolsUpdateRequest(
                defaultPolicy: .deny,
                tools: [:],
                guardrails: AgentToolsGuardrails()
            )
        )

        let result = await service.invokeToolFromChannelRuntime(
            agentID: agentID,
            channelID: "channel:telegram",
            request: ToolInvocationRequest(
                tool: "files.read",
                arguments: ["path": .string("README.md")]
            )
        )

        #expect(result.ok == false)
        #expect(result.error?.code == "tool_forbidden")
    }

    @Test("gateway channel tool calls resolve relative paths from linked project root")
    func gatewayChannelToolCallsResolveRelativePathsFromProjectRoot() async throws {
        let service = makeService()
        let agentID = "gateway-project-\(UUID().uuidString)"
        try await makeAgent(service: service, agentID: agentID)

        let repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gateway-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        let noteURL = repoRoot.appendingPathComponent("note.txt")
        try Data("hello from gateway".utf8).write(to: noteURL)

        _ = try await service.createProject(
            ProjectCreateRequest(
                id: "gateway-project",
                name: "Gateway Project",
                channels: [.init(title: "Telegram", channelId: "channel:telegram")],
                repoPath: repoRoot.path
            )
        )

        let result = await service.invokeToolFromChannelRuntime(
            agentID: agentID,
            channelID: "channel:telegram",
            request: ToolInvocationRequest(
                tool: "files.read",
                arguments: ["path": .string("note.txt")]
            )
        )

        #expect(result.ok == true)
        guard case .object(let payload)? = result.data else {
            Issue.record("Expected object payload from files.read")
            return
        }
        #expect(payload["path"]?.asString == noteURL.path)
        #expect(payload["content"]?.asString == "hello from gateway")
    }
}
