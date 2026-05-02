import Foundation
import Logging
import Testing
@testable import AgentRuntime
@testable import sloppy
@testable import Protocols

@Suite("project.channel_link tool")
struct ProjectChannelLinkToolTests {
    private func makeContext(service: CoreService, sessionID: String) -> ToolContext {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-channel-link-tool-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return ToolContext(
            agentID: "test-agent",
            sessionID: sessionID,
            policy: AgentToolsPolicy(guardrails: AgentToolsGuardrails()),
            workspaceRootURL: tmp,
            runtime: RuntimeSystem(),
            memoryStore: InMemoryMemoryStore(),
            sessionStore: AgentSessionFileStore(agentsRootURL: tmp),
            agentCatalogStore: AgentCatalogFileStore(agentsRootURL: tmp),
            agentSkillsStore: nil,
            processRegistry: SessionProcessRegistry(),
            channelSessionStore: ChannelSessionFileStore(workspaceRootURL: tmp),
            store: InMemoryCorePersistenceBuilder().makeStore(config: CoreConfig.test),
            searchProviderService: SearchProviderService(config: CoreConfig.default.searchTools),
            mcpRegistry: MCPClientRegistry(config: CoreConfig.default.mcp),
            logger: Logger(label: "test.project.channel_link"),
            projectService: service,
            configService: nil,
            skillsService: nil,
            lspManager: nil,
            applyAgentMarkdown: nil,
            delegateSubagent: nil
        )
    }

    @Test
    func linksCurrentChannelByProjectName() async throws {
        let service = CoreService(config: .test)
        _ = try await service.createProject(
            ProjectCreateRequest(id: "avito", name: "AVITO", channels: [.init(title: "Main", channelId: "main")])
        )
        let tool = ProjectChannelLinkTool()
        let result = await tool.invoke(
            arguments: ["projectName": .string("AVITO"), "title": .string("Telegram topic")],
            context: makeContext(service: service, sessionID: "telegram-main\u{001E}tgthread:42")
        )
        #expect(result.ok == true)
        #expect(result.data?.asObject?["status"]?.asString == "linked")
        #expect(result.data?.asObject?["projectId"]?.asString == "avito")
    }

    @Test
    func rejectsChannelAlreadyLinkedToAnotherProject() async throws {
        let service = CoreService(config: .test)
        _ = try await service.createProject(
            ProjectCreateRequest(id: "one", name: "One", channels: [.init(title: "Main", channelId: "main")])
        )
        _ = try await service.createProject(
            ProjectCreateRequest(id: "two", name: "Two", channels: [.init(title: "Other", channelId: "other")])
        )
        _ = try await service.linkProjectChannel(
            projectID: "one",
            request: ProjectChannelLinkRequest(channelId: "discord-room", title: "Discord", ensureSession: false)
        )

        let tool = ProjectChannelLinkTool()
        let result = await tool.invoke(
            arguments: ["projectId": .string("two"), "channelId": .string("discord-room")],
            context: makeContext(service: service, sessionID: "discord-room")
        )
        #expect(result.ok == false)
        #expect(result.error?.code == "channel_already_linked")
    }
}
