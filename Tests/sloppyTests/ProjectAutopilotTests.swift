import Foundation
import Testing
@testable import sloppy
@testable import Protocols

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
