import Foundation
import Logging
import Testing
@testable import AgentRuntime
@testable import sloppy
@testable import Protocols

@Test
func taskCreateWithProjectIdSucceedsWithoutChannelLink() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let projectID = "tool-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Tool Test Project", description: "", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let context = makeToolContext(service: service, sessionID: "session-no-channel")
    let tool = ProjectTaskCreateTool()

    let result = await tool.invoke(
        arguments: [
            "title": .string("Track nutrition"),
            "projectId": .string(projectID)
        ],
        context: context
    )

    #expect(result.ok == true)

    if let taskId = result.data?.asObject?["taskId"]?.asString {
        #expect(!taskId.isEmpty)
    } else {
        Issue.record("Expected taskId in result data")
    }
}

@Test
func taskCreateWithoutProjectIdFailsWhenChannelNotLinked() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let projectID = "tool-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Tool Test Project", description: "", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let context = makeToolContext(service: service, sessionID: "session-no-channel")
    let tool = ProjectTaskCreateTool()

    let result = await tool.invoke(
        arguments: ["title": .string("Track nutrition")],
        context: context
    )

    #expect(result.ok == false)
    #expect(result.error?.code == "project_not_found")
}

@Test
func taskListWithProjectIdSucceedsWithoutChannelLink() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "tool-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Tool Test Project", description: "", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Task One", description: "", priority: "medium", status: "backlog")
    )
    let taskResp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody)
    #expect(taskResp.status == 200)

    let context = makeToolContext(service: service, sessionID: "session-no-channel")
    let tool = ProjectTaskListTool()

    let result = await tool.invoke(
        arguments: ["projectId": .string(projectID)],
        context: context
    )

    #expect(result.ok == true)
    let tasks = result.data?.asObject?["tasks"]?.asArray
    #expect(tasks?.count == 1)
}

// MARK: - Helper

private func makeToolContext(service: CoreService, sessionID: String) -> ToolContext {
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
        processRegistry: SessionProcessRegistry(),
        channelSessionStore: ChannelSessionFileStore(workspaceRootURL: tmpURL),
        store: InMemoryCorePersistenceBuilder().makeStore(config: CoreConfig.test),
        searchProviderService: SearchProviderService(config: CoreConfig.default.searchTools),
        mcpRegistry: MCPClientRegistry(config: CoreConfig.default.mcp),
        logger: Logger(label: "test"),
        projectService: service,
        configService: nil,
        skillsService: nil
    )
}
