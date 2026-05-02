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

@Test
func taskCancelAcceptsMultipleTaskIds() async throws {
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
    let createTool = ProjectTaskCreateTool()
    let first = await createTool.invoke(arguments: ["title": .string("Task One"), "projectId": .string(projectID)], context: context)
    let second = await createTool.invoke(arguments: ["title": .string("Task Two"), "projectId": .string(projectID)], context: context)
    let firstID = try #require(first.data?.asObject?["taskId"]?.asString)
    let secondID = try #require(second.data?.asObject?["taskId"]?.asString)

    let cancelTool = ProjectTaskCancelTool()
    let result = await cancelTool.invoke(
        arguments: [
            "taskIds": .array([.string(firstID), .string(secondID)]),
            "projectId": .string(projectID),
            "reason": .string("No longer needed")
        ],
        context: context
    )

    #expect(result.ok == true)
    #expect(result.data?.asObject?["cancelledCount"]?.asNumber == 2)

    let project = try await service.getProject(id: projectID)
    let statuses = Dictionary(uniqueKeysWithValues: project.tasks.map { ($0.id, $0.status) })
    #expect(statuses[firstID] == ProjectTaskStatus.cancelled.rawValue)
    #expect(statuses[secondID] == ProjectTaskStatus.cancelled.rawValue)
}

@Test
func taskDeleteAcceptsMultipleReferences() async throws {
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
    let createTool = ProjectTaskCreateTool()
    let first = await createTool.invoke(arguments: ["title": .string("Task One"), "projectId": .string(projectID)], context: context)
    let second = await createTool.invoke(arguments: ["title": .string("Task Two"), "projectId": .string(projectID)], context: context)
    let firstID = try #require(first.data?.asObject?["taskId"]?.asString)
    let secondID = try #require(second.data?.asObject?["taskId"]?.asString)

    let deleteTool = ProjectTaskDeleteTool()
    let result = await deleteTool.invoke(
        arguments: [
            "references": .array([.string(firstID), .string(secondID.lowercased())]),
            "projectId": .string(projectID)
        ],
        context: context
    )

    #expect(result.ok == true)
    #expect(result.data?.asObject?["deletedCount"]?.asNumber == 2)

    let project = try await service.getProject(id: projectID)
    #expect(project.tasks.isEmpty)
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
