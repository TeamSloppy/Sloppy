import Foundation
import Logging
import PluginSDK
import Testing
@testable import AgentRuntime
@testable import sloppy
@testable import Protocols

@Test
func projectCurrentReturnsProjectForLinkedChannel() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let channelID = "linked-session"
    let projectID = "current-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(
            id: projectID,
            name: "Current Project",
            description: "Project resolved by project.current",
            channels: [ProjectChannelCreateRequest(title: "Linked", channelId: channelID)],
            actors: ["implementer"],
            teams: ["core"]
        )
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let result = await ProjectCurrentTool().invoke(arguments: [:], context: makeProjectCurrentToolContext(service: service, sessionID: channelID))

    #expect(result.ok == true)
    let data = try #require(result.data?.asObject)
    #expect(data["projectId"]?.asString == projectID)
    #expect(data["projectName"]?.asString == "Current Project")
    #expect(data["channelId"]?.asString == channelID)
    #expect(data["matchedChannelId"]?.asString == channelID)
    #expect(data["taskCount"]?.asNumber == 0)
    #expect(data["actors"]?.asArray?.first?.asString == "implementer")
    #expect(data["teams"]?.asArray?.first?.asString == "core")
}

@Test
func projectCurrentReturnsNotFoundForUnlinkedChannel() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let projectID = "current-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Unlinked Project", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let result = await ProjectCurrentTool().invoke(
        arguments: ["channelId": .string("missing-channel")],
        context: makeProjectCurrentToolContext(service: service, sessionID: "default-session")
    )

    #expect(result.ok == false)
    #expect(result.error?.code == "project_not_found")
}

@Test
func projectCurrentRespectsTopicId() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let baseChannelID = "telegram-main"
    let topicID = "42"
    let scopedChannelID = ChannelGatewayScope.scopedChannelId(baseChannelId: baseChannelID, topicKey: topicID)
    let projectID = "current-topic-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(
            id: projectID,
            name: "Topic Project",
            channels: [ProjectChannelCreateRequest(title: "Topic", channelId: scopedChannelID)]
        )
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let result = await ProjectCurrentTool().invoke(
        arguments: [
            "channelId": .string(baseChannelID),
            "topicId": .string(topicID)
        ],
        context: makeProjectCurrentToolContext(service: service, sessionID: "default-session")
    )

    #expect(result.ok == true)
    let data = try #require(result.data?.asObject)
    #expect(data["projectId"]?.asString == projectID)
    #expect(data["topicId"]?.asString == topicID)
    #expect(data["effectiveChannelId"]?.asString == scopedChannelID)
    #expect(data["matchedChannelId"]?.asString == scopedChannelID)
}

private func makeProjectCurrentToolContext(service: CoreService, sessionID: String) -> ToolContext {
    let tmpURL = FileManager.default.temporaryDirectory
    return ToolContext(
        agentID: "test-agent",
        sessionID: sessionID,
        policy: AgentToolsPolicy(),
        workspaceRootURL: tmpURL,
        runtime: RuntimeSystem(),
        memoryStore: InMemoryMemoryStore(),
        sessionStore: AgentSessionFileStore(agentsRootURL: tmpURL),
        agentCatalogStore: AgentCatalogFileStore(agentsRootURL: tmpURL),
        agentSkillsStore: nil,
        processRegistry: SessionProcessRegistry(),
        channelSessionStore: ChannelSessionFileStore(workspaceRootURL: tmpURL),
        store: InMemoryCorePersistenceBuilder().makeStore(config: CoreConfig.test),
        searchProviderService: SearchProviderService(config: CoreConfig.default.searchTools),
        mcpRegistry: MCPClientRegistry(config: CoreConfig.default.mcp),
        logger: Logger(label: "test"),
        projectService: service,
        configService: nil,
        skillsService: nil,
        lspManager: nil,
        applyAgentMarkdown: nil,
        delegateSubagent: nil
    )
}
