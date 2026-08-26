import Foundation
import Protocols
import SloppyNodeCore
import Testing
@testable import sloppy

@Test("project task keeps its execution node across create and update")
func projectTaskKeepsExecutionNode() async throws {
    let service = CoreService(config: .test)
    let projectID = "execution-node-\(UUID().uuidString)"
    _ = try await service.createProject(
        ProjectCreateRequest(
            id: projectID,
            name: "Execution node project",
            channels: [.init(title: "General", channelId: "general")]
        )
    )

    let created = try await service.createProjectTask(
        projectID: projectID,
        request: ProjectTaskCreateRequest(
            title: "Run remotely",
            actorId: "agent:builder",
            executionNodeId: "node_work"
        )
    )
    let taskID = try #require(created.tasks.last?.id)
    #expect(created.tasks.last?.actorId == "agent:builder")
    #expect(created.tasks.last?.executionNodeId == "node_work")

    let updated = try await service.updateProjectTask(
        projectID: projectID,
        taskID: taskID,
        request: ProjectTaskUpdateRequest(executionNodeId: "node_home")
    )
    let task = try #require(updated.tasks.first { $0.id == taskID })
    #expect(task.actorId == "agent:builder")
    #expect(task.executionNodeId == "node_home")
}

@Test("a task assigned to another instance never starts on the local runtime")
func remoteExecutionNodeSkipsLocalRuntime() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-execution-node-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let nodeConfigStore = NodeConfigStore(
        configURL: temporaryRoot.appendingPathComponent("node.json")
    )
    _ = try nodeConfigStore.initialize(
        name: "Work Mac",
        roles: ["controller"],
        capabilities: ["sloppy.core.remote"]
    )
    let service = CoreService(
        config: .test,
        currentDirectory: temporaryRoot.path,
        nodeConfigStore: nodeConfigStore
    )
    let projectID = "execution-node-guard-\(UUID().uuidString)"
    _ = try await service.createProject(
        ProjectCreateRequest(
            id: projectID,
            name: "Remote execution guard",
            channels: [.init(title: "General", channelId: "general")]
        )
    )

    let project = try await service.createProjectTask(
        projectID: projectID,
        request: ProjectTaskCreateRequest(
            title: "Run only at home",
            status: ProjectTaskStatus.ready.rawValue,
            executionNodeId: "home-mac"
        )
    )
    let task = try #require(project.tasks.last)
    let logURL = await service.projectTaskLogFileURL(projectID: projectID, taskID: task.id)
    let log = try String(
        contentsOf: logURL,
        encoding: .utf8
    )

    #expect(log.contains("stage=remote_instance_assigned"))
    #expect(log.contains("home-mac"))
    #expect(await service.runtime.workerSnapshots().isEmpty)
}
