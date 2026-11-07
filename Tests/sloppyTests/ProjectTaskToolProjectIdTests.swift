import Foundation
import Logging
import Testing
import SloppyRuntime
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
            "status": .string("backlog"),
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
func taskCreateAcceptsKanbanGraphFields() async throws {
    let fixture = try await makeTaskUpdateFixture()
    let createTool = ProjectTaskCreateTool()

    let parent = await createTool.invoke(
        arguments: [
            "title": .string("Umbrella"),
            "status": .string(ProjectTaskStatus.backlog.rawValue),
            "projectId": .string(fixture.projectID),
            "tags": .array([.string("feature")]),
            "changedBy": .string("agent:test-agent")
        ],
        context: fixture.context
    )
    let parentID = try #require(parent.data?.asObject?["taskId"]?.asString)

    let child = await createTool.invoke(
        arguments: [
            "title": .string("Child"),
            "status": .string(ProjectTaskStatus.backlog.rawValue),
            "projectId": .string(fixture.projectID),
            "parentTaskId": .string(parentID),
            "dependsOnTaskIds": .array([.string(fixture.taskID)]),
            "selectedModel": .string("mock:fast"),
            "tags": .array([.string("feature"), .string("autopilot")]),
            "changedBy": .string("agent:test-agent")
        ],
        context: fixture.context
    )

    #expect(child.ok == true)
    let childID = try #require(child.data?.asObject?["taskId"]?.asString)
    let project = try await fixture.service.getProject(id: fixture.projectID)
    let childTask = try #require(project.tasks.first { $0.id == childID })
    #expect(childTask.parentTaskId == parentID)
    #expect(childTask.dependsOnTaskIds == [fixture.taskID])
    #expect(childTask.selectedModel == "mock:fast")
    #expect(childTask.tags == ["feature", "autopilot"])
    #expect(childTask.createdBy == "agent:test-agent")
}

@Test
func taskUpdateAcceptsKanbanGraphFields() async throws {
    let fixture = try await makeTaskUpdateFixture()
    let createTool = ProjectTaskCreateTool()
    let updateTool = ProjectTaskUpdateTool()

    let parent = await createTool.invoke(
        arguments: [
            "title": .string("Parent"),
            "status": .string(ProjectTaskStatus.backlog.rawValue),
            "projectId": .string(fixture.projectID)
        ],
        context: fixture.context
    )
    let dependency = await createTool.invoke(
        arguments: [
            "title": .string("Dependency"),
            "status": .string(ProjectTaskStatus.backlog.rawValue),
            "projectId": .string(fixture.projectID)
        ],
        context: fixture.context
    )
    let parentID = try #require(parent.data?.asObject?["taskId"]?.asString)
    let dependencyID = try #require(dependency.data?.asObject?["taskId"]?.asString)

    let result = await updateTool.invoke(
        arguments: [
            "taskId": .string(fixture.taskID),
            "projectId": .string(fixture.projectID),
            "parentTaskId": .string(parentID),
            "dependsOnTaskIds": .array([.string(dependencyID)]),
            "selectedModel": .string("mock:precise"),
            "tags": .array([.string("skills"), .string("planning")])
        ],
        context: fixture.context
    )

    #expect(result.ok == true)
    let task = try #require(result.data?.asObject?["task"]?.asObject)
    #expect(task["parentTaskId"]?.asString == parentID)
    #expect(task["dependsOnTaskIds"]?.asArray?.compactMap(\.asString) == [dependencyID])
    #expect(task["selectedModel"]?.asString == "mock:precise")
    #expect(task["tags"]?.asArray?.compactMap(\.asString) == ["skills", "planning"])
}

@Test
func projectCurrentExposesAutopilotSettingsAndTaskSyncLinkedProjects() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let projectID = "tool-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Tool Test Project", description: "", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    _ = try await service.updateProject(
        projectID: projectID,
        request: ProjectUpdateRequest(
            actors: ["actor:builder"],
            teams: ["team:platform"],
            models: ["mock:fast"],
            autopilotSettings: ProjectAutopilotSettings(
                enabled: true,
                defaultAgentId: "builder",
                includedTags: ["autopilot"],
                trustedAuthors: ["agent:test-agent"]
            )
        )
    )
    _ = try await service.updateTaskSyncSettings(
        projectID: projectID,
        request: ProjectTaskSyncSettingsUpdateRequest(
            linkedProjects: [
                ProjectTaskSyncLinkedProject(
                    title: "Roadmap",
                    projectURL: "https://github.com/orgs/example/projects/1",
                    tag: "gh:roadmap"
                )
            ]
        )
    )

    let context = makeToolContext(service: service, sessionID: "session-no-channel", currentProjectID: projectID)
    let tool = ProjectCurrentTool()

    let result = await tool.invoke(arguments: [:], context: context)

    #expect(result.ok == true)
    let data = try #require(result.data?.asObject)
    let autopilot = try #require(data["autopilotSettings"]?.asObject)
    #expect(autopilot["enabled"]?.asBool == true)
    #expect(autopilot["includedTags"]?.asArray?.compactMap(\.asString) == ["autopilot"])
    #expect(autopilot["ignoredTags"]?.asArray?.compactMap(\.asString) == [])
    #expect(autopilot["trustedAuthors"]?.asArray?.compactMap(\.asString) == ["agent:test-agent"])
    #expect(data["models"]?.asArray?.compactMap(\.asString) == ["mock:fast"])

    let taskSyncSettings = try #require(data["taskSyncSettings"]?.asObject)
    let linkedProjects = try #require(taskSyncSettings["linkedProjects"]?.asArray)
    #expect(linkedProjects.first?.asObject?["tag"]?.asString == "gh:roadmap")
}

@Test
func taskListExposesKanbanGraphSummaryFields() async throws {
    let fixture = try await makeTaskUpdateFixture()
    let createTool = ProjectTaskCreateTool()
    let listTool = ProjectTaskListTool()

    let child = await createTool.invoke(
        arguments: [
            "title": .string("Child summary"),
            "kind": .string(ProjectTaskKind.execution.rawValue),
            "loopModeOverride": .string(ProjectLoopMode.agent.rawValue),
            "status": .string(ProjectTaskStatus.backlog.rawValue),
            "projectId": .string(fixture.projectID),
            "parentTaskId": .string(fixture.taskID),
            "dependsOnTaskIds": .array([.string(fixture.taskID)]),
            "selectedModel": .string("mock:fast"),
            "tags": .array([.string("tools")]),
            "changedBy": .string("agent:test-agent")
        ],
        context: fixture.context
    )
    let childID = try #require(child.data?.asObject?["taskId"]?.asString)

    let result = await listTool.invoke(
        arguments: ["projectId": .string(fixture.projectID)],
        context: fixture.context
    )

    #expect(result.ok == true)
    let tasks = try #require(result.data?.asObject?["tasks"]?.asArray)
    let listedChild = try #require(tasks.compactMap(\.asObject).first { $0["id"]?.asString == childID })
    #expect(listedChild["kind"]?.asString == ProjectTaskKind.execution.rawValue)
    #expect(listedChild["loopModeOverride"]?.asString == ProjectLoopMode.agent.rawValue)
    #expect(listedChild["parentTaskId"]?.asString == fixture.taskID)
    #expect(listedChild["dependsOnTaskIds"]?.asArray?.compactMap(\.asString) == [fixture.taskID])
    #expect(listedChild["createdBy"]?.asString == "agent:test-agent")
    #expect(listedChild["selectedModel"]?.asString == "mock:fast")
    #expect(listedChild["tags"]?.asArray?.compactMap(\.asString) == ["tools"])
    #expect(listedChild["isArchived"]?.asBool == false)
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
    let first = await createTool.invoke(
        arguments: ["title": .string("Task One"), "status": .string("backlog"), "projectId": .string(projectID)],
        context: context
    )
    let second = await createTool.invoke(
        arguments: ["title": .string("Task Two"), "status": .string("backlog"), "projectId": .string(projectID)],
        context: context
    )
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
    let first = await createTool.invoke(
        arguments: ["title": .string("Task One"), "status": .string("backlog"), "projectId": .string(projectID)],
        context: context
    )
    let second = await createTool.invoke(
        arguments: ["title": .string("Task Two"), "status": .string("backlog"), "projectId": .string(projectID)],
        context: context
    )
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

@Test
func taskUpdateInvalidStatusReturnsInvalidPayload() async throws {
    let fixture = try await makeTaskUpdateFixture()
    let tool = ProjectTaskUpdateTool()

    let result = await tool.invoke(
        arguments: [
            "taskId": .string(fixture.taskID),
            "projectId": .string(fixture.projectID),
            "status": .string("finished")
        ],
        context: fixture.context
    )

    #expect(result.ok == false)
    #expect(result.error?.code == "invalid_payload")
    #expect(result.error?.retryable == false)
    #expect(result.error?.hint?.contains("Allowed status values") == true)
}

@Test
func taskUpdateRequiresCompletionEvidence() async throws {
    let fixture = try await makeTaskUpdateFixture()
    let tool = ProjectTaskUpdateTool()

    let result = await tool.invoke(
        arguments: [
            "taskId": .string(fixture.taskID),
            "projectId": .string(fixture.projectID),
            "status": .string(ProjectTaskStatus.done.rawValue)
        ],
        context: fixture.context
    )

    #expect(result.ok == false)
    #expect(result.error?.code == "completion_confirmation_required")
}

@Test
func taskUpdateCanSetDoneWithCompletionEvidence() async throws {
    let fixture = try await makeTaskUpdateFixture()
    let tool = ProjectTaskUpdateTool()

    let result = await tool.invoke(
        arguments: [
            "taskId": .string(fixture.taskID),
            "projectId": .string(fixture.projectID),
            "status": .string(ProjectTaskStatus.done.rawValue),
            "completionConfidence": .string(ProjectTaskCompletionConfidence.done.rawValue),
            "completionNote": .string("Verified the requested change and checked the final state.")
        ],
        context: fixture.context
    )

    #expect(result.ok == true)
    #expect(result.data?.asObject?["status"]?.asString == ProjectTaskStatus.done.rawValue)
}

@Test
func projectUpdateConfiguresAutopilotWithoutResettingOtherSettings() async throws {
    let fixture = try await makeTaskUpdateFixture()
    _ = try await fixture.service.updateProject(projectID: fixture.projectID, request: .init(
        autopilotSettings: .init(enabled: false, reviewerAgentId: "reviewer", ignoredTags: ["manual"], canCommit: true)
    ))
    let result = await ProjectUpdateTool().invoke(arguments: [
        "projectId": .string(fixture.projectID),
        "autopilotSettings": .object([
            "enabled": .bool(true), "mode": .string("parallel"),
            "defaultAgentId": .string("builder"), "includedTags": .array([.string("work")]),
            "trustedAuthors": .array([.string("agent:test-agent")]), "maxParallelTasks": .number(3),
            "canUseWeb": .bool(true), "canEditFiles": .bool(true), "canRunCommands": .bool(true),
            "canStartLocalhost": .bool(true), "canPush": .bool(false),
            "pickupRules": .object(["conditions": .array([.object([
                "id": .string("source"), "field": .string("source"), "operation": .string("one_of"),
                "values": .array([.string("local")])
            ])])])
        ]),
        "taskLoopMode": .string("agent"), "automaticTaskPickupEnabled": .bool(true)
    ], context: fixture.context)
    #expect(result.ok)
    let project = try await fixture.service.getProject(id: fixture.projectID)
    let settings = project.autopilotSettings
    #expect(settings.enabled && settings.mode == .parallel)
    #expect(settings.defaultAgentId == "builder" && settings.reviewerAgentId == "reviewer")
    #expect(settings.includedTags == ["work"] && settings.ignoredTags == ["manual"])
    #expect(settings.trustedAuthors == ["agent:test-agent"] && settings.maxParallelTasks == 3)
    #expect(settings.canUseWeb && settings.canEditFiles && settings.canRunCommands && settings.canStartLocalhost)
    #expect(settings.canCommit && !settings.canPush)
    #expect(settings.pickupRules.conditions.first?.field == .source)
    #expect(project.taskLoopMode == .agent && project.automaticTaskPickupEnabled)
    #expect(result.data?.asObject?["autopilotSettings"]?.asObject?["pickupRules"] != nil)

    let disabled = await ProjectUpdateTool().invoke(arguments: [
        "projectId": .string(fixture.projectID),
        "autopilotSettings": .object(["enabled": .bool(false), "reviewerAgentId": .string("")]),
        "taskLoopMode": .string("human"), "automaticTaskPickupEnabled": .bool(false)
    ], context: fixture.context)
    #expect(disabled.ok)
    let updated = try await fixture.service.getProject(id: fixture.projectID)
    #expect(!updated.autopilotSettings.enabled && updated.autopilotSettings.reviewerAgentId == nil)
    #expect(updated.autopilotSettings.defaultAgentId == "builder")
    #expect(updated.autopilotSettings.canCommit)
    #expect(updated.taskLoopMode == .human && !updated.automaticTaskPickupEnabled)
}

@Test
func projectUpdateRejectsInvalidAutopilotSettingsAtomically() async throws {
    let fixture = try await makeTaskUpdateFixture()
    let before = try await fixture.service.getProject(id: fixture.projectID)
    let invalid: [[String: JSONValue]] = [
        ["autopilotSettings": .string("null")],
        ["autopilotSettings": .object(["mode": .string("invalid")])],
        ["autopilotSettings": .object(["enabled": .string("true")])],
        ["autopilotSettings": .object(["canPuhs": .bool(true)])],
        ["autopilotSettings": .object(["pickupRules": .object(["conditions": .array([.object([
            "id": .string("bad"), "field": .string("tag"), "operation": .string("contains"),
            "values": .array([.string("work")])
        ])])])])],
        ["taskLoopMode": .string("invalid")],
        ["automaticTaskPickupEnabled": .string("true")]
    ]
    for patch in invalid {
        var arguments = patch
        arguments["projectId"] = .string(fixture.projectID)
        arguments["name"] = .string("Must not save")
        let result = await ProjectUpdateTool().invoke(arguments: arguments, context: fixture.context)
        #expect(!result.ok && result.error?.code == "invalid_arguments")
        #expect(try await fixture.service.getProject(id: fixture.projectID) == before)
    }
}

@Test
func projectUpdateMetadataPreservesAutopilotAndNewProjectDefaultIsEnabled() async throws {
    let fixture = try await makeTaskUpdateFixture()
    #expect(try await fixture.service.getProject(id: fixture.projectID).autopilotSettings.enabled)
    _ = try await fixture.service.updateProject(projectID: fixture.projectID, request: .init(autopilotSettings: .init(enabled: false)))
    let result = await ProjectUpdateTool().invoke(arguments: [
        "projectId": .string(fixture.projectID), "name": .string("Renamed")
    ], context: fixture.context)
    #expect(result.ok)
    #expect(try await !fixture.service.getProject(id: fixture.projectID).autopilotSettings.enabled)
}

@Test
func projectUpdateAutopilotPatchPreservesNullsAndNestedRules() throws {
    let current = ProjectAutopilotSettings(enabled: false, defaultAgentId: "builder", canCommit: true,
        pickupRules: .init(matchMode: .any, conditions: [.init(id: "tag", field: .tag, values: ["work"])]))
    let updated = try ProjectAutopilotToolSettings.applying(.object([
        "enabled": .null, "defaultAgentId": .null, "canCommit": .null,
        "pickupRules": .object(["conditions": .array([])])
    ]), to: current)
    #expect(!updated.enabled && updated.defaultAgentId == "builder" && updated.canCommit)
    #expect(updated.pickupRules.matchMode == .any && updated.pickupRules.conditions.isEmpty)
}

@Test
func projectUpdateAdvertisesTypedAutopilotSettings() throws {
    let data = try JSONEncoder().encode(ProjectUpdateTool().parameters)
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let autopilot = try #require(properties["autopilotSettings"] as? [String: Any])
    #expect(autopilot["type"] as? String == "object")
    let settings = try #require(autopilot["properties"] as? [String: Any])
    #expect((settings["enabled"] as? [String: Any])?["type"] as? String == "boolean")
    #expect(settings["pickupRules"] != nil && settings["canPush"] != nil)
    #expect(properties["taskLoopMode"] != nil && properties["automaticTaskPickupEnabled"] != nil)
}

// MARK: - Helper

private func makeTaskUpdateFixture() async throws -> (service: CoreService, context: ToolContext, projectID: String, taskID: String) {
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
        ProjectTaskCreateRequest(
            title: "Task Update Diagnostics",
            description: "Exercise agent tool update errors",
            priority: "medium",
            status: ProjectTaskStatus.inProgress.rawValue
        )
    )
    let taskResp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody)
    #expect(taskResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let project = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    let taskID = try #require(project.tasks.first?.id)
    let context = makeToolContext(service: service, sessionID: "session-no-channel")
    return (service, context, projectID, taskID)
}

private func makeToolContext(service: CoreService, sessionID: String, currentProjectID: String? = nil) -> ToolContext {
    let tmpURL = FileManager.default.temporaryDirectory
    return ToolContext(
        agentID: "test-agent",
        sessionID: sessionID,
        policy: AgentToolsPolicy(),
        workspaceRootURL: tmpURL,
        currentProjectID: currentProjectID,
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
        logger: .sloppy(label: "test"),
        projectService: service,
        configService: nil,
        skillsService: nil,
        lspManager: nil,
        applyAgentMarkdown: nil,
        delegateSubagent: nil
    )
}
