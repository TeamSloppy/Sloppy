import Foundation
import AnyLanguageModel
import Testing
@testable import PluginSDK
@testable import sloppy
@testable import Protocols

private struct AutopilotFixedJSONModel: LanguageModel {
    typealias UnavailableReason = Never

    let output: String

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard type == String.self else {
            fatalError("AutopilotFixedJSONModel only supports String responses")
        }
        return LanguageModelSession.Response(
            content: output as! Content,
            rawContent: GeneratedContent(output),
            transcriptEntries: []
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                guard let response = try? await respond(
                    within: session,
                    to: prompt,
                    generating: type,
                    includeSchemaInPrompt: includeSchemaInPrompt,
                    options: options
                ) else {
                    continuation.finish()
                    return
                }
                continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                continuation.finish()
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

private actor AutopilotRecordingModelProvider: ModelProvider {
    nonisolated let id: String = "autopilot-recording"
    nonisolated let supportedModels: [String]

    private var requestedModels: [String] = []
    private let output: String

    init(models: [String], output: String) {
        self.supportedModels = models
        self.output = output
    }

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        requestedModels.append(modelName)
        return AutopilotFixedJSONModel(output: output)
    }

    func requestedModelsSnapshot() -> [String] {
        requestedModels
    }
}

private actor AutopilotFailingModelProvider: ModelProvider {
    nonisolated let id: String = "autopilot-failing"
    nonisolated let supportedModels: [String]

    private var requestCount = 0

    init(models: [String]) {
        self.supportedModels = models
    }

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        requestCount += 1
        throw URLError(.timedOut)
    }

    func requestedCountSnapshot() -> Int {
        requestCount
    }
}

@Test
func projectAutopilotDisabledDoesNothing() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let project = ProjectRecord(
        id: "autopilot-disabled",
        name: "Autopilot Disabled",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [
            ProjectTask(
                id: "task-1",
                title: "Tagged",
                description: "",
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue,
                tags: ["autopilot"]
            )
        ],
        autopilotSettings: ProjectAutopilotSettings(enabled: false, defaultAgentId: "builder")
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    let saved = await service.store.project(id: project.id)
    #expect(saved?.tasks.first?.status == ProjectTaskStatus.backlog.rawValue)
}

@Test
func projectAutopilotIncludeTagsRestrictUntaggedBacklogTask() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let project = ProjectRecord(
        id: "autopilot-included-tags-restrict-untagged",
        name: "Autopilot Include Tags Restrict Untagged",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [
            ProjectTask(
                id: "task-1",
                title: "Untagged",
                description: "",
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue
            )
        ],
        autopilotSettings: ProjectAutopilotSettings(
            enabled: true,
            defaultAgentId: "builder",
            includedTags: ["autopilot"]
        )
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    let saved = await service.store.project(id: project.id)
    #expect(saved?.tasks.first?.status == ProjectTaskStatus.backlog.rawValue)
}

@Test
func projectAutopilotDefaultAllowsUntaggedBacklogTask() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let project = ProjectRecord(
        id: "autopilot-default-allows-untagged",
        name: "Autopilot Default Allows Untagged",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [
            ProjectTask(
                id: "task-1",
                title: "Untagged",
                description: "",
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue
            )
        ],
        autopilotSettings: ProjectAutopilotSettings(enabled: true)
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    let saved = await service.store.project(id: project.id)
    #expect(saved?.tasks.first?.status == ProjectTaskStatus.blocked.rawValue)
    #expect(saved?.tasks.first?.description.contains("Autopilot blocked") == true)
}

@Test
func projectAutopilotIgnoredTagsExcludeBacklogTask() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let project = ProjectRecord(
        id: "autopilot-ignored-tags",
        name: "Autopilot Ignored Tags",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [
            ProjectTask(
                id: "task-1",
                title: "Ignored",
                description: "",
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue,
                tags: ["autopilot", "manual"]
            )
        ],
        autopilotSettings: ProjectAutopilotSettings(
            enabled: true,
            includedTags: ["autopilot"],
            ignoredTags: ["manual"]
        )
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    let saved = await service.store.project(id: project.id)
    #expect(saved?.tasks.first?.status == ProjectTaskStatus.backlog.rawValue)
}

@Test
func projectAutopilotBlocksTaggedTaskWithoutDefaultAgent() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let project = ProjectRecord(
        id: "autopilot-missing-agent",
        name: "Autopilot Missing Agent",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [
            ProjectTask(
                id: "task-1",
                title: "Tagged",
                description: "",
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue,
                tags: ["autopilot"]
            )
        ],
        autopilotSettings: ProjectAutopilotSettings(enabled: true)
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    let saved = await service.store.project(id: project.id)
    #expect(saved?.tasks.first?.status == ProjectTaskStatus.blocked.rawValue)
    #expect(saved?.tasks.first?.description.contains("Autopilot blocked") == true)
}

@Test
func projectAutopilotWorkerToolsAlwaysIncludeTaskLifecycleTools() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let task = ProjectTask(
        id: "task-1",
        title: "Plan file explorer",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.ready.rawValue,
        kind: .planning,
        tags: ["autopilot"]
    )
    let project = ProjectRecord(
        id: "autopilot-worker-tools",
        name: "Autopilot Worker Tools",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [task],
        autopilotSettings: ProjectAutopilotSettings(
            enabled: true,
            defaultAgentId: "builder",
            canUseWeb: true,
            canEditFiles: true,
            canRunCommands: true,
            canStartLocalhost: true
        )
    )

    let tools = await service.workerToolsForTask(task: task, project: project)

    #expect(tools.contains("project_tasks"))
    #expect(tools.contains("file"))
    #expect(tools.contains("shell"))
    #expect(tools.contains("browser"))
    #expect(tools.contains("web.search"))
}

@Test
func projectAutopilotPlannerUsesDefaultAgentSelectedModel() async throws {
    var config = CoreConfig.test
    config.models = [
        .init(title: "First", apiKey: "", apiUrl: "", model: "mock:first"),
        .init(title: "Selected", apiKey: "", apiUrl: "", model: "mock:selected"),
    ]
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let output = """
    {
      "subtasks": [
        {
          "id": "build",
          "title": "Build the fix",
          "description": "Implement the requested change",
          "dependsOn": []
        }
      ]
    }
    """
    let provider = AutopilotRecordingModelProvider(models: ["mock:first", "mock:selected"], output: output)
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:first")

    let agent = try await service.createAgent(
        AgentCreateRequest(id: "autopilot-builder", displayName: "Builder", role: "Developer")
    )
    let agentConfig = try await service.getAgentConfig(agentID: agent.id)
    _ = try await service.updateAgentConfig(
        agentID: agent.id,
        request: AgentConfigUpdateRequest(
            role: agentConfig.role,
            selectedModel: "mock:selected",
            documents: agentConfig.documents,
            heartbeat: agentConfig.heartbeat,
            channelSessions: agentConfig.channelSessions,
            runtime: agentConfig.runtime
        )
    )

    let project = ProjectRecord(
        id: "autopilot-selected-model",
        name: "Autopilot Selected Model",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [
            ProjectTask(
                id: "task-1",
                title: "Tagged",
                description: "",
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue,
                tags: ["autopilot"]
            )
        ],
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: agent.id)
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    #expect(await provider.requestedModelsSnapshot() == ["mock:selected"])
}

@Test
func projectAutopilotStopsPlanningTickAfterTransientPlannerFailure() async throws {
    var config = CoreConfig.test
    config.models = [
        .init(title: "Planner", apiKey: "", apiUrl: "", model: "mock:planner"),
    ]
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let provider = AutopilotFailingModelProvider(models: ["mock:planner"])
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:planner")

    let project = ProjectRecord(
        id: "autopilot-transient-once",
        name: "Autopilot Transient Once",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [
            ProjectTask(
                id: "task-1",
                title: "Tagged one",
                description: "",
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue,
                tags: ["autopilot"]
            ),
            ProjectTask(
                id: "task-2",
                title: "Tagged two",
                description: "",
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue,
                tags: ["autopilot"]
            ),
        ],
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: "builder")
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    #expect(await provider.requestedCountSnapshot() == 1)
    let firstComments = await service.listTaskComments(projectID: project.id, taskID: "task-1")
    let secondComments = await service.listTaskComments(projectID: project.id, taskID: "task-2")
    #expect(firstComments.count == 1)
    #expect(secondComments.isEmpty)
}

@Test
func projectAutopilotBlocksTaskWhenDelegatedSubagentMissesFinishTool() async throws {
    var config = CoreConfig.test
    config.models = [
        .init(title: "Worker", apiKey: "", apiUrl: "", model: "mock:worker"),
    ]
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let provider = AutopilotRecordingModelProvider(models: ["mock:worker"], output: "I investigated but did not finish structurally.")
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:worker")

    let agent = try await service.createAgent(
        AgentCreateRequest(id: "autopilot-worker", displayName: "Worker", role: "Developer")
    )
    let task = ProjectTask(
        id: "task-1",
        title: "Implement delegated fix",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        parentTaskId: "root",
        createdBy: "autopilot",
        tags: ["autopilot"]
    )
    let project = ProjectRecord(
        id: "autopilot-delegated-failure",
        name: "Autopilot Delegated Failure",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [task],
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: agent.id)
    )
    await service.store.saveProject(project)

    let result = await service.runSubagentTask(
        agentID: agent.id,
        taskID: task.id,
        objective: "Finish the task.",
        workingDirectory: nil,
        toolsetNames: ["file"],
        selectedModel: "mock:worker"
    )

    let saved = try #require(await service.store.project(id: project.id))
    let savedTask = try #require(saved.tasks.first(where: { $0.id == task.id }))
    let comments = await service.listTaskComments(projectID: project.id, taskID: task.id)

    #expect(result?.contains("agent_delegate.finish") == true)
    #expect(savedTask.status == ProjectTaskStatus.blocked.rawValue)
    #expect(comments.contains { $0.content.contains(result ?? "") })
}

@Test
func projectAutopilotLauncherSkipsStaleBlockedReadyTaskID() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let agent = try await service.createAgent(
        AgentCreateRequest(id: "autopilot-stale-worker", displayName: "Worker", role: "Developer")
    )
    let task = ProjectTask(
        id: "task-1",
        title: "Stale ready child",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.blocked.rawValue,
        parentTaskId: "root",
        createdBy: "autopilot",
        tags: ["autopilot"]
    )
    let project = ProjectRecord(
        id: "autopilot-stale-ready-id",
        name: "Autopilot Stale Ready ID",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [task],
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: agent.id)
    )
    await service.store.saveProject(project)

    await service.launchAutopilotReadyTasks(projectID: project.id, taskIDs: [task.id])

    let saved = try #require(await service.store.project(id: project.id))
    let savedTask = try #require(saved.tasks.first(where: { $0.id == task.id }))
    let sessions = try await service.listAgentSessions(agentID: agent.id, projectID: nil, limit: nil, offset: 0)

    #expect(savedTask.status == ProjectTaskStatus.blocked.rawValue)
    #expect(sessions.isEmpty)
}

@Test
func projectAutopilotSkipsBacklogRootWithBlockedDependency() async throws {
    var config = CoreConfig.test
    config.models = [
        .init(title: "Planner", apiKey: "", apiUrl: "", model: "mock:planner"),
    ]
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let output = """
    {
      "subtasks": [
        {
          "id": "build",
          "title": "Build the fix",
          "description": "Implement the requested change",
          "dependsOn": []
        }
      ]
    }
    """
    let provider = AutopilotRecordingModelProvider(models: ["mock:planner"], output: output)
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:planner")

    let dependency = ProjectTask(
        id: "task-1",
        title: "Blocked dependency",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.blocked.rawValue
    )
    let dependent = ProjectTask(
        id: "task-2",
        title: "Dependent autopilot root",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.backlog.rawValue,
        dependsOnTaskIds: [dependency.id],
        tags: ["autopilot"]
    )
    let project = ProjectRecord(
        id: "autopilot-blocked-root-dependency",
        name: "Autopilot Blocked Root Dependency",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [dependency, dependent],
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: "builder")
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    let saved = try #require(await service.store.project(id: project.id))
    let savedDependent = try #require(saved.tasks.first(where: { $0.id == dependent.id }))
    #expect(savedDependent.status == ProjectTaskStatus.backlog.rawValue)
    #expect(saved.tasks.filter { $0.parentTaskId == dependent.id }.isEmpty)
    #expect(await provider.requestedModelsSnapshot().isEmpty)
}

@Test
func projectAutopilotPlansBacklogRootAfterDependencyDone() async throws {
    var config = CoreConfig.test
    config.models = [
        .init(title: "Planner", apiKey: "", apiUrl: "", model: "mock:planner"),
    ]
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let output = """
    {
      "subtasks": [
        {
          "id": "build",
          "title": "Build the fix",
          "description": "Implement the requested change",
          "dependsOn": []
        }
      ]
    }
    """
    let provider = AutopilotRecordingModelProvider(models: ["mock:planner"], output: output)
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:planner")

    let dependency = ProjectTask(
        id: "task-1",
        title: "Completed dependency",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.done.rawValue
    )
    let dependent = ProjectTask(
        id: "task-2",
        title: "Dependent autopilot root",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.backlog.rawValue,
        dependsOnTaskIds: [dependency.id],
        tags: ["autopilot"]
    )
    let project = ProjectRecord(
        id: "autopilot-done-root-dependency",
        name: "Autopilot Done Root Dependency",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [dependency, dependent],
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: "builder")
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    let saved = try #require(await service.store.project(id: project.id))
    let savedDependent = try #require(saved.tasks.first(where: { $0.id == dependent.id }))
    #expect(savedDependent.status == ProjectTaskStatus.inProgress.rawValue)
    #expect(saved.tasks.contains { $0.parentTaskId == dependent.id })
    #expect(await provider.requestedModelsSnapshot() == ["mock:planner"])
}

@Test
func projectAutopilotKeepsChildBacklogWhenDependencyBlocked() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let root = ProjectTask(
        id: "task-1",
        title: "Root",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        tags: ["autopilot"]
    )
    let blockedChild = ProjectTask(
        id: "task-2",
        title: "Blocked child",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.blocked.rawValue,
        parentTaskId: root.id,
        createdBy: "autopilot",
        tags: ["autopilot"]
    )
    let dependentChild = ProjectTask(
        id: "task-3",
        title: "Dependent child",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.backlog.rawValue,
        parentTaskId: root.id,
        createdBy: "autopilot",
        dependsOnTaskIds: [blockedChild.id],
        tags: ["autopilot"]
    )
    let project = ProjectRecord(
        id: "autopilot-blocked-child-dependency",
        name: "Autopilot Blocked Child Dependency",
        description: "",
        channels: [ProjectChannel(id: "channel-1", title: "Main", channelId: "chan")],
        tasks: [root, blockedChild, dependentChild],
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: "builder")
    )
    await service.store.saveProject(project)

    await service.processAutonomousExecution()

    let saved = try #require(await service.store.project(id: project.id))
    let savedDependentChild = try #require(saved.tasks.first(where: { $0.id == dependentChild.id }))
    #expect(savedDependentChild.status == ProjectTaskStatus.backlog.rawValue)
}
