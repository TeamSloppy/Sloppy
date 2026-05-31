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
func projectAutopilotIgnoresUntaggedBacklogTask() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let project = ProjectRecord(
        id: "autopilot-untagged",
        name: "Autopilot Untagged",
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
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: "builder")
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
