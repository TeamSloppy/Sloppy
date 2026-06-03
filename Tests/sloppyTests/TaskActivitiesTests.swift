import Foundation
import Testing
@testable import AgentRuntime
@testable import sloppy
@testable import Protocols

private func firstKanbanEvent(
    from stream: AsyncStream<KanbanEvent>,
    timeoutSeconds: TimeInterval = 2,
    where predicate: @escaping @Sendable (KanbanEvent) -> Bool
) async -> KanbanEvent? {
    await withTaskGroup(of: KanbanEvent?.self) { group in
        group.addTask {
            for await event in stream {
                if predicate(event) {
                    return event
                }
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            return nil
        }
        let event = await group.next() ?? nil
        group.cancelAll()
        return event
    }
}

private func makeProjectWithTask(router: CoreRouter) async throws -> (projectID: String, taskID: String) {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "activity-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Activity Test Project", description: "Test", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Test Task", description: "Initial desc", priority: "medium", status: "backlog")
    )
    let taskResp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody)
    #expect(taskResp.status == 200)
    let project = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    let taskID = try #require(project.tasks.first?.id)
    return (projectID, taskID)
}

@Test
func listTaskActivitiesReturnsEmptyInitially() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/activities",
        body: nil
    )
    #expect(resp.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let activities = try decoder.decode([TaskActivity].self, from: resp.body)
    #expect(activities.isEmpty)
}

@Test
func listTaskRunsReturnsEmptyInitially() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/runs",
        body: nil
    )
    #expect(resp.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let runs = try decoder.decode([ProjectTaskRun].self, from: resp.body)
    #expect(runs.isEmpty)
}

@Test
func completingTaskRecordsSyntheticRunWithHandoffEvidence() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(
            status: ProjectTaskStatus.done.rawValue,
            completionConfidence: .done,
            completionNote: "Implemented parser cleanup and verified with swift test.",
            changedBy: "agent-dev"
        )
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    #expect(updateResp.status == 200)

    let runsResp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/runs",
        body: nil
    )
    #expect(runsResp.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let runs = try decoder.decode([ProjectTaskRun].self, from: runsResp.body)
    let run = try #require(runs.first)
    #expect(run.outcome == .completed)
    #expect(run.summary == "Implemented parser cleanup and verified with swift test.")
    #expect(run.metadata["source"] == "agent-dev")
    #expect(run.metadata["completionConfidence"] == ProjectTaskCompletionConfidence.done.rawValue)
    #expect(run.endedAt != nil)

    let logsResp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/logs",
        body: nil
    )
    #expect(logsResp.status == 200)
    let logs = try decoder.decode([TaskLogEntry].self, from: logsResp.body)
    #expect(logs.contains {
        $0.kind == "run"
            && $0.title == "Task run completed"
            && $0.message == "Implemented parser cleanup and verified with swift test."
    })
}

@Test
func updateTaskStatusRecordsActivity() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(status: "ready", changedBy: "actor-alice")
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    #expect(updateResp.status == 200)

    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/activities",
        body: nil
    )
    #expect(resp.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let activities = try decoder.decode([TaskActivity].self, from: resp.body)
    let patchActivity = activities.first { $0.actorId == "actor-alice" && $0.field == .status }
    #expect(patchActivity != nil)
    #expect(patchActivity?.oldValue == "backlog")
    #expect(patchActivity?.newValue == "ready")
    #expect(patchActivity?.taskId == taskID)
}

@Test
func readyTaskWithoutLinkedAgentBlocksAndComments() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(status: "ready", changedBy: "user")
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    #expect(updateResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let project = try decoder.decode(ProjectRecord.self, from: updateResp.body)
    let task = try #require(project.tasks.first(where: { $0.id == taskID }))
    #expect(task.status == ProjectTaskStatus.blocked.rawValue)

    let commentsResp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
        body: nil
    )
    #expect(commentsResp.status == 200)
    let comments = try decoder.decode([TaskComment].self, from: commentsResp.body)
    #expect(comments.contains {
        $0.authorActorId == "system"
            && $0.content.contains("Task flow problem")
            && $0.content.contains("no linked agent")
    })

    let logsResp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/logs",
        body: nil
    )
    #expect(logsResp.status == 200)
    let entries = try decoder.decode([TaskLogEntry].self, from: logsResp.body)
    #expect(entries.contains { $0.kind == "lifecycle" && $0.title == "missing agent" })
    #expect(entries.contains {
        $0.kind == "activity"
            && $0.actorId == "system"
            && $0.field == "status"
            && $0.newValue == ProjectTaskStatus.blocked.rawValue
    })
}

@Test
func updateTaskPriorityRecordsActivity() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(priority: "high", changedBy: "user")
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    #expect(updateResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/activities",
        body: nil
    )
    let activities = try decoder.decode([TaskActivity].self, from: resp.body)
    #expect(activities.count == 1)
    #expect(activities[0].field == .priority)
    #expect(activities[0].oldValue == "medium")
    #expect(activities[0].newValue == "high")
}

@Test
func updateTaskTitleRecordsActivity() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(title: "Updated Title", changedBy: "user")
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    #expect(updateResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/activities",
        body: nil
    )
    let activities = try decoder.decode([TaskActivity].self, from: resp.body)
    #expect(activities.count == 1)
    #expect(activities[0].field == .title)
    #expect(activities[0].oldValue == "Test Task")
    #expect(activities[0].newValue == "Updated Title")
}

@Test
func updateMultipleFieldsRecordsMultipleActivities() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(title: "New Title", priority: "high", status: "in_progress", changedBy: "actor-bob")
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    #expect(updateResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/activities",
        body: nil
    )
    let activities = try decoder.decode([TaskActivity].self, from: resp.body)
    #expect(activities.count == 3)

    let fields = Set(activities.map { $0.field })
    #expect(fields.contains(.status))
    #expect(fields.contains(.priority))
    #expect(fields.contains(.title))
    #expect(activities.allSatisfy { $0.actorId == "actor-bob" })
}

@Test
func noChangeNoActivity() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(title: "Test Task", priority: "medium", status: "backlog")
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    #expect(updateResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/activities",
        body: nil
    )
    let activities = try decoder.decode([TaskActivity].self, from: resp.body)
    #expect(activities.isEmpty)
}

@Test
func changedByDefaultsToUser() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(status: "ready")
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    #expect(updateResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/activities",
        body: nil
    )
    let activities = try decoder.decode([TaskActivity].self, from: resp.body)
    let patchActivity = activities.first { $0.actorId == "user" && $0.field == .status }
    #expect(patchActivity != nil)
}

@Test
func taskLogsCombineActivityLifecycleAndToolCalls() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(priority: "high", changedBy: "actor-alice")
    )
    _ = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)",
        body: updateBody
    )
    await service.appendTaskLifecycleLog(
        projectID: projectID,
        taskID: taskID,
        stage: "worker_spawned",
        channelID: "chan-1",
        workerID: "worker-1",
        message: "Task delegated.",
        actorID: "actor-alice",
        agentID: "agent-alice"
    )
    await service.persistToolInvocationAnalytics(
        agentId: "agent-alice",
        sessionId: "session-1",
        sessionTitle: "task-\(taskID)",
        toolId: "files.read",
        ok: true,
        durationMs: 12
    )

    let response = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/logs",
        body: nil
    )
    #expect(response.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let entries = try decoder.decode([TaskLogEntry].self, from: response.body)
    #expect(entries.contains { $0.kind == "created" })
    #expect(entries.contains { $0.kind == "activity" && $0.field == "priority" && $0.newValue == "high" })
    #expect(entries.contains { $0.kind == "lifecycle" && $0.workerId == "worker-1" })
    #expect(entries.contains { $0.kind == "tool_invocation" && $0.tool == "files.read" && $0.agentId == "agent-alice" })
}

@Test
func startupDispatchesPersistedReadyTasks() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let task = ProjectTask(
        id: "task-startup-ready",
        title: "Ready on boot",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.ready.rawValue
    )
    let projectID = "startup-ready-\(UUID().uuidString)"
    let project = ProjectRecord(
        id: projectID,
        name: "Startup Ready",
        description: "",
        channels: [ProjectChannel(id: "project-channel-startup", title: "Startup", channelId: "startup-channel")],
        tasks: [task]
    )
    await service.store.saveProject(project)

    await service.waitForStartup()

    let updated = try await service.getProject(id: projectID)
    let updatedTask = try #require(updated.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.status != ProjectTaskStatus.ready.rawValue)
}

@Test
func readyTaskWithBlockedDependencyReturnsToBacklogWithoutWorker() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let projectID = "dependency-ready-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Dependency Ready Test", description: "Test", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let blockedBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(
            title: "Blocked dependency",
            description: "",
            priority: "medium",
            status: ProjectTaskStatus.blocked.rawValue
        )
    )
    let blockedResp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: blockedBody)
    #expect(blockedResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let blockedProject = try decoder.decode(ProjectRecord.self, from: blockedResp.body)
    let blockedTask = try #require(blockedProject.tasks.first)
    let dependentBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(
            title: "Dependent task",
            description: "",
            priority: "medium",
            status: ProjectTaskStatus.backlog.rawValue,
            dependsOnTaskIds: [blockedTask.id]
        )
    )
    let dependentResp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: dependentBody)
    #expect(dependentResp.status == 200)
    let dependentProject = try decoder.decode(ProjectRecord.self, from: dependentResp.body)
    let dependentTask = try #require(dependentProject.tasks.first(where: { $0.id != blockedTask.id }))

    let readyBody = try JSONEncoder().encode(ProjectTaskUpdateRequest(status: ProjectTaskStatus.ready.rawValue))
    let readyResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(dependentTask.id)",
        body: readyBody
    )
    #expect(readyResp.status == 200)

    let updatedProject = try decoder.decode(ProjectRecord.self, from: readyResp.body)
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == dependentTask.id }))
    #expect(updatedTask.status == ProjectTaskStatus.backlog.rawValue)
    let workers = await service.workerSnapshots()
    #expect(workers.allSatisfy { $0.taskId != dependentTask.id })

    let commentsResp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(dependentTask.id)/comments",
        body: nil
    )
    #expect(commentsResp.status == 200)
    let comments = try decoder.decode([TaskComment].self, from: commentsResp.body)
    #expect(comments.contains {
        $0.authorActorId == "system"
            && $0.content.contains("Task is waiting for dependencies")
            && $0.content.contains(blockedTask.id)
    })
}

@Test
func startupReadyTaskWithBlockedDependencyReturnsToBacklogWithoutWorker() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let dependency = ProjectTask(
        id: "task-startup-dependency",
        title: "Blocked dependency",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.blocked.rawValue
    )
    let dependent = ProjectTask(
        id: "task-startup-dependent",
        title: "Ready dependent on boot",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.ready.rawValue,
        dependsOnTaskIds: [dependency.id]
    )
    let projectID = "startup-ready-dependency-\(UUID().uuidString)"
    let project = ProjectRecord(
        id: projectID,
        name: "Startup Ready Dependency",
        description: "",
        channels: [ProjectChannel(id: "project-channel-startup", title: "Startup", channelId: "startup-channel")],
        tasks: [dependency, dependent]
    )
    await service.store.saveProject(project)

    await service.waitForStartup()

    let updated = try await service.getProject(id: projectID)
    let updatedTask = try #require(updated.tasks.first(where: { $0.id == dependent.id }))
    #expect(updatedTask.status == ProjectTaskStatus.backlog.rawValue)
    let workers = await service.workerSnapshots()
    #expect(workers.allSatisfy { $0.taskId != dependent.id })
}

@Test
func creatingTaskRejectsMissingAndCrossProjectDependencies() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectA = "dependency-project-a-\(UUID().uuidString)"
    let projectB = "dependency-project-b-\(UUID().uuidString)"
    let createA = try JSONEncoder().encode(ProjectCreateRequest(id: projectA, name: "A", description: "", channels: []))
    let createB = try JSONEncoder().encode(ProjectCreateRequest(id: projectB, name: "B", description: "", channels: []))
    #expect(await router.handle(method: "POST", path: "/v1/projects", body: createA).status == 201)
    #expect(await router.handle(method: "POST", path: "/v1/projects", body: createB).status == 201)

    let taskBody = try JSONEncoder().encode(ProjectTaskCreateRequest(title: "Dependency source", status: ProjectTaskStatus.done.rawValue))
    let taskResp = await router.handle(method: "POST", path: "/v1/projects/\(projectA)/tasks", body: taskBody)
    #expect(taskResp.status == 200)
    let project = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    let foreignTask = try #require(project.tasks.first)

    let missingBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Missing dependency", dependsOnTaskIds: ["task-does-not-exist"])
    )
    let missingResp = await router.handle(method: "POST", path: "/v1/projects/\(projectB)/tasks", body: missingBody)
    #expect(missingResp.status == 400)

    let crossProjectBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Cross-project dependency", dependsOnTaskIds: [foreignTask.id])
    )
    let crossProjectResp = await router.handle(method: "POST", path: "/v1/projects/\(projectB)/tasks", body: crossProjectBody)
    #expect(crossProjectResp.status == 400)
}

@Test
func updatingTaskRejectsSelfDependencyAndCycles() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let projectID = "dependency-cycle-\(UUID().uuidString)"

    let createProject = try JSONEncoder().encode(ProjectCreateRequest(id: projectID, name: "Cycle", description: "", channels: []))
    #expect(await router.handle(method: "POST", path: "/v1/projects", body: createProject).status == 201)

    let firstResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks",
        body: try JSONEncoder().encode(ProjectTaskCreateRequest(title: "First"))
    )
    #expect(firstResp.status == 200)
    let firstProject = try decoder.decode(ProjectRecord.self, from: firstResp.body)
    let first = try #require(firstProject.tasks.first)

    let secondResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks",
        body: try JSONEncoder().encode(ProjectTaskCreateRequest(title: "Second", dependsOnTaskIds: [first.id]))
    )
    #expect(secondResp.status == 200)
    let secondProject = try decoder.decode(ProjectRecord.self, from: secondResp.body)
    let second = try #require(secondProject.tasks.first(where: { $0.id != first.id }))

    let selfResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(first.id)",
        body: try JSONEncoder().encode(ProjectTaskUpdateRequest(dependsOnTaskIds: [first.id]))
    )
    #expect(selfResp.status == 400)

    let cycleResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(first.id)",
        body: try JSONEncoder().encode(ProjectTaskUpdateRequest(dependsOnTaskIds: [second.id]))
    )
    #expect(cycleResp.status == 400)
}

@Test
func completingFinalDependencyPromotesDependentTaskToReady() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let projectID = "dependency-promotion-\(UUID().uuidString)"

    let createProject = try JSONEncoder().encode(ProjectCreateRequest(id: projectID, name: "Promotion", description: "", channels: []))
    #expect(await router.handle(method: "POST", path: "/v1/projects", body: createProject).status == 201)

    let dependencyResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks",
        body: try JSONEncoder().encode(ProjectTaskCreateRequest(title: "Dependency", status: ProjectTaskStatus.backlog.rawValue))
    )
    #expect(dependencyResp.status == 200)
    let dependencyProject = try decoder.decode(ProjectRecord.self, from: dependencyResp.body)
    let dependency = try #require(dependencyProject.tasks.first)

    let dependentResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks",
        body: try JSONEncoder().encode(
            ProjectTaskCreateRequest(
                title: "Dependent",
                status: ProjectTaskStatus.backlog.rawValue,
                dependsOnTaskIds: [dependency.id]
            )
        )
    )
    #expect(dependentResp.status == 200)
    let dependentProject = try decoder.decode(ProjectRecord.self, from: dependentResp.body)
    let dependent = try #require(dependentProject.tasks.first(where: { $0.id != dependency.id }))

    let doneResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(dependency.id)",
        body: try JSONEncoder().encode(ProjectTaskUpdateRequest(status: ProjectTaskStatus.done.rawValue, changedBy: "user"))
    )
    #expect(doneResp.status == 200)
    let promotedProject = try decoder.decode(ProjectRecord.self, from: doneResp.body)
    let promoted = try #require(promotedProject.tasks.first(where: { $0.id == dependent.id }))
    #expect(promoted.status == ProjectTaskStatus.ready.rawValue)
}

@Test
func staleInProgressTaskWithoutActiveWorkerIsReclaimedToReady() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let task = ProjectTask(
        id: "TASK-1",
        title: "Stale claim",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: "agent-dev"
    )
    let projectID = "stale-claim-\(UUID().uuidString)"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Stale Claim", description: "", channels: [], tasks: [task]))
    await service.startTaskRun(
        projectID: projectID,
        taskID: task.id,
        actorID: task.claimedActorId,
        agentID: task.claimedAgentId,
        workerID: "missing-worker",
        channelID: nil
    )

    let reclaimed = await service.reclaimStaleProjectTaskClaims(staleAfter: 0)
    #expect(reclaimed.map(\.id).contains(task.id))

    let updatedProject = try await service.getProject(id: projectID)
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.status == ProjectTaskStatus.ready.rawValue)
    #expect(updatedTask.claimedActorId == nil)
    #expect(updatedTask.claimedAgentId == nil)

    let runs = await service.listTaskRuns(projectID: projectID, taskID: task.id)
    #expect(runs.last?.outcome == .reclaimed)
    #expect(runs.last?.endedAt != nil)
}

@Test
func repeatedSpawnFailuresTripCircuitBreakerAndBlockTask() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let task = ProjectTask(
        id: "TASK-1",
        title: "Spawn failure",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.ready.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: "agent-dev"
    )
    let projectID = "spawn-failure-\(UUID().uuidString)"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Spawn Failure", description: "", channels: [], tasks: [task]))

    let first = try await service.recordProjectTaskSpawnFailure(
        projectID: projectID,
        taskID: task.id,
        error: "profile not found",
        failureLimit: 2
    )
    #expect(first.tasks.first(where: { $0.id == task.id })?.status == ProjectTaskStatus.ready.rawValue)

    let second = try await service.recordProjectTaskSpawnFailure(
        projectID: projectID,
        taskID: task.id,
        error: "profile not found",
        failureLimit: 2
    )
    let blockedTask = try #require(second.tasks.first(where: { $0.id == task.id }))
    #expect(blockedTask.status == ProjectTaskStatus.blocked.rawValue)
    #expect(blockedTask.claimedActorId == nil)
    #expect(blockedTask.claimedAgentId == nil)

    let runs = await service.listTaskRuns(projectID: projectID, taskID: task.id)
    #expect(runs.suffix(2).allSatisfy { $0.outcome == .failed })

    let logs = try await service.listTaskLogs(projectID: projectID, taskID: task.id)
    #expect(logs.contains { $0.kind == "lifecycle" && $0.title == "circuit breaker" })
}

@Test
func kanbanMaintenanceSweepUsesConfiguredStaleClaimTimeout() async throws {
    var config = CoreConfig.test
    config.kanban.staleClaimTimeoutSeconds = 0
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let task = ProjectTask(
        id: "TASK-1",
        title: "Sweep stale claim",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: "agent-dev"
    )
    let projectID = "kanban-sweep-\(UUID().uuidString)"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Kanban Sweep", description: "", channels: [], tasks: [task]))
    await service.startTaskRun(
        projectID: projectID,
        taskID: task.id,
        actorID: task.claimedActorId,
        agentID: task.claimedAgentId,
        workerID: "missing-worker",
        channelID: nil
    )

    let result = await service.runKanbanMaintenanceNow()
    #expect(result.reclaimedTaskIds == [task.id])
    #expect(result.dispatchAttemptedTaskIds.isEmpty)

    let updatedProject = try await service.getProject(id: projectID)
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.status == ProjectTaskStatus.ready.rawValue)
}

@Test
func kanbanMaintenanceSweepDispatchesReadyTaskThroughWorkerPath() async throws {
    var config = CoreConfig.test
    config.kanban.staleClaimTimeoutSeconds = 300
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let agentID = "kanban-dispatch-agent-\(UUID().uuidString)"
    _ = try await service.createAgent(AgentCreateRequest(id: agentID, displayName: "Kanban Dispatch", role: "Testing"))
    let task = ProjectTask(
        id: "TASK-1",
        title: "Dispatch ready task",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.ready.rawValue,
        tags: ["autopilot"]
    )
    let projectID = "kanban-dispatch-\(UUID().uuidString)"
    await service.store.saveProject(ProjectRecord(
        id: projectID,
        name: "Kanban Dispatch",
        description: "",
        channels: [ProjectChannel(id: "main", title: "Main", channelId: "channel-1")],
        tasks: [task],
        autopilotSettings: ProjectAutopilotSettings(enabled: true, defaultAgentId: agentID)
    ))
    let stream = await service.kanbanEventService.subscribe(projectId: projectID)

    let result = await service.runKanbanMaintenanceNow()
    #expect(result.reclaimedTaskIds.isEmpty)
    #expect(result.dispatchAttemptedTaskIds == [task.id])

    let event = await firstKanbanEvent(from: stream) { event in
        event.type == .taskUpdated &&
            event.task?.id == task.id &&
            event.task?.status == ProjectTaskStatus.inProgress.rawValue
    }
    #expect(event?.task?.claimedAgentId == agentID)

    let updatedProject = try await service.getProject(id: projectID)
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.status != ProjectTaskStatus.ready.rawValue)
    #expect(updatedTask.claimedAgentId == agentID)

    let runs = await service.listTaskRuns(projectID: projectID, taskID: task.id)
    #expect(runs.contains { $0.agentId == agentID && $0.startedAt <= Date() })
    let run = try #require(runs.first { $0.agentId == agentID })

    let heartbeats = await service.listTaskWorkerHeartbeats(projectID: projectID, taskID: task.id)
    #expect(heartbeats.contains { heartbeat in
        heartbeat.workerId == run.workerId &&
            heartbeat.agentId == agentID &&
            heartbeat.status == .running &&
            heartbeat.message != nil
    })

    let logs = try await service.listTaskLogs(projectID: projectID, taskID: task.id)
    #expect(logs.contains { $0.kind == "lifecycle" && $0.title == "worker spawned" })
}

@Test
func kanbanMaintenanceSweepReclaimsOrphanedTaskAndEmitsEvidence() async throws {
    var config = CoreConfig.test
    config.kanban.staleClaimTimeoutSeconds = 0
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let task = ProjectTask(
        id: "TASK-1",
        title: "Orphaned task",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: "agent-dev"
    )
    let projectID = "kanban-orphan-\(UUID().uuidString)"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Kanban Orphan", description: "", channels: [], tasks: [task]))
    await service.startTaskRun(
        projectID: projectID,
        taskID: task.id,
        actorID: task.claimedActorId,
        agentID: task.claimedAgentId,
        workerID: "missing-worker",
        channelID: nil
    )
    let stream = await service.kanbanEventService.subscribe(projectId: projectID)

    let result = await service.runKanbanMaintenanceNow()
    #expect(result.reclaimedTaskIds == [task.id])

    let event = await firstKanbanEvent(from: stream) { event in
        event.type == .taskUpdated && event.task?.id == task.id
    }
    #expect(event?.task?.status == ProjectTaskStatus.ready.rawValue)

    let activities = await service.listTaskActivities(projectID: projectID, taskID: task.id)
    #expect(activities.contains { $0.field == .status && $0.oldValue == ProjectTaskStatus.inProgress.rawValue && $0.newValue == ProjectTaskStatus.ready.rawValue })

    let logs = try await service.listTaskLogs(projectID: projectID, taskID: task.id)
    #expect(logs.contains { $0.kind == "lifecycle" && $0.title == "stale claim reclaimed" })
}

@Test
func kanbanMaintenanceSweepDoesNotReclaimFreshActiveWorker() async throws {
    var config = CoreConfig.test
    config.kanban.staleClaimTimeoutSeconds = 300
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let task = ProjectTask(
        id: "TASK-1",
        title: "Fresh worker",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: "agent-dev"
    )
    let projectID = "kanban-fresh-\(UUID().uuidString)"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Kanban Fresh", description: "", channels: [], tasks: [task]))
    await service.waitForStartup(dispatchReadyTasks: false)
    let now = Date()
    await service.runtime.recover(
        channels: [RecoveryChannelState(id: "channel-1", createdAt: now, updatedAt: now)],
        tasks: [
            RecoveryTaskState(
                id: task.id,
                channelId: "channel-1",
                status: ProjectTaskStatus.inProgress.rawValue,
                title: task.title,
                objective: "Keep claim active",
                createdAt: now,
                updatedAt: now
            )
        ],
        events: [],
        artifacts: []
    )
    let workerID = try #require(await service.runtime.workerSnapshots().first(where: { $0.taskId == task.id })?.workerId)
    await service.startTaskRun(
        projectID: projectID,
        taskID: task.id,
        actorID: task.claimedActorId,
        agentID: task.claimedAgentId,
        workerID: workerID,
        channelID: "channel-1"
    )

    let result = await service.runKanbanMaintenanceNow()
    #expect(result.reclaimedTaskIds.isEmpty)

    let updatedProject = try await service.getProject(id: projectID)
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.status == ProjectTaskStatus.inProgress.rawValue)
    #expect(updatedTask.claimedActorId == "actor-dev")
    #expect(updatedTask.claimedAgentId == "agent-dev")
}

@Test
func freshTaskWorkerHeartbeatPreventsReclaimForOldActiveWorker() async throws {
    var config = CoreConfig.test
    config.kanban.staleClaimTimeoutSeconds = 300
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let oldStart = Date(timeIntervalSince1970: 1_700_000_000)
    let now = oldStart.addingTimeInterval(1_000)
    let task = ProjectTask(
        id: "TASK-1",
        title: "Fresh heartbeat",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: "agent-dev"
    )
    let projectID = "kanban-heartbeat-fresh-\(UUID().uuidString)"
    let workerID = "worker-heartbeat-fresh"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Kanban Heartbeat Fresh", description: "", channels: [], tasks: [task]))
    await service.waitForStartup(dispatchReadyTasks: false)
    await service.runtime.recover(
        channels: [RecoveryChannelState(id: "channel-1", createdAt: oldStart, updatedAt: oldStart)],
        tasks: [
            RecoveryTaskState(
                id: task.id,
                channelId: "channel-1",
                status: ProjectTaskStatus.inProgress.rawValue,
                title: task.title,
                objective: "Keep claim active",
                createdAt: oldStart,
                updatedAt: oldStart
            )
        ],
        events: [
            EventEnvelope(
                messageType: .workerSpawned,
                ts: oldStart,
                channelId: "channel-1",
                taskId: task.id,
                workerId: workerID,
                payload: .object([:])
            )
        ],
        artifacts: []
    )
    await service.startTaskRun(
        projectID: projectID,
        taskID: task.id,
        actorID: task.claimedActorId,
        agentID: task.claimedAgentId,
        workerID: workerID,
        channelID: "channel-1"
    )
    await service.recordTaskWorkerHeartbeat(
        projectID: projectID,
        taskID: task.id,
        workerID: workerID,
        agentID: task.claimedAgentId,
        status: .running,
        message: "Still working.",
        updatedAt: now.addingTimeInterval(-30)
    )

    let result = await service.reclaimStaleProjectTaskClaims(staleAfter: 300, now: now)
    #expect(result.isEmpty)

    let updatedProject = try await service.getProject(id: projectID)
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.status == ProjectTaskStatus.inProgress.rawValue)
}

@Test
func staleTaskWorkerHeartbeatReclaimsOldActiveWorkerWithoutCountingFailure() async throws {
    var config = CoreConfig.test
    config.kanban.staleClaimTimeoutSeconds = 300
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let oldStart = Date(timeIntervalSince1970: 1_700_100_000)
    let now = oldStart.addingTimeInterval(1_000)
    let task = ProjectTask(
        id: "TASK-1",
        title: "Stale heartbeat",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: "agent-dev"
    )
    let projectID = "kanban-heartbeat-stale-\(UUID().uuidString)"
    let workerID = "worker-heartbeat-stale"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Kanban Heartbeat Stale", description: "", channels: [], tasks: [task]))
    await service.waitForStartup(dispatchReadyTasks: false)
    await service.runtime.recover(
        channels: [RecoveryChannelState(id: "channel-1", createdAt: oldStart, updatedAt: oldStart)],
        tasks: [
            RecoveryTaskState(
                id: task.id,
                channelId: "channel-1",
                status: ProjectTaskStatus.inProgress.rawValue,
                title: task.title,
                objective: "Keep claim active",
                createdAt: oldStart,
                updatedAt: oldStart
            )
        ],
        events: [
            EventEnvelope(
                messageType: .workerSpawned,
                ts: oldStart,
                channelId: "channel-1",
                taskId: task.id,
                workerId: workerID,
                payload: .object([:])
            )
        ],
        artifacts: []
    )
    await service.startTaskRun(
        projectID: projectID,
        taskID: task.id,
        actorID: task.claimedActorId,
        agentID: task.claimedAgentId,
        workerID: workerID,
        channelID: "channel-1"
    )
    await service.recordTaskWorkerHeartbeat(
        projectID: projectID,
        taskID: task.id,
        workerID: workerID,
        agentID: task.claimedAgentId,
        status: .running,
        message: "Old progress.",
        updatedAt: now.addingTimeInterval(-600)
    )

    let result = await service.reclaimStaleProjectTaskClaims(staleAfter: 300, now: now)
    #expect(result.map(\.id) == [task.id])

    let updatedProject = try await service.getProject(id: projectID)
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.status == ProjectTaskStatus.ready.rawValue)

    let runs = await service.listTaskRuns(projectID: projectID, taskID: task.id)
    #expect(runs.last?.outcome == .reclaimed)
    #expect(runs.last?.metadata["reason"] == "stale_claim")
    #expect(await service.consecutiveTaskRunFailures(projectID: projectID, taskID: task.id) == 0)
}

@Test
func workerFailedRuntimeEventTripsConfiguredCircuitBreaker() async throws {
    var config = CoreConfig.test
    config.kanban.spawnFailureLimit = 1
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let task = ProjectTask(
        id: "TASK-1",
        title: "Failed worker",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: "agent-dev"
    )
    let projectID = "worker-failed-\(UUID().uuidString)"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Worker Failed", description: "", channels: [], tasks: [task]))
    await service.startTaskRun(
        projectID: projectID,
        taskID: task.id,
        actorID: task.claimedActorId,
        agentID: task.claimedAgentId,
        workerID: "worker-1",
        channelID: "channel-1"
    )

    await service.handleKanbanRuntimeEvent(
        EventEnvelope(
            messageType: .workerFailed,
            channelId: "channel-1",
            taskId: task.id,
            workerId: "worker-1",
            payload: .object(["error": .string("profile not found")])
        )
    )

    let updatedProject = try await service.getProject(id: projectID)
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.status == ProjectTaskStatus.blocked.rawValue)
}

@Test
func realWorkerStartFailureRecordsSpawnFailureAndBlocksAfterLimit() async throws {
    var config = CoreConfig.test
    config.kanban.spawnFailureLimit = 2
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let agentID = "worker-launch-\(UUID().uuidString)"
    _ = try await service.createAgent(AgentCreateRequest(id: agentID, displayName: "Worker Launch", role: "Testing"))
    _ = try await service.updateAgentToolsPolicy(
        agentID: agentID,
        request: AgentToolsUpdateRequest(defaultPolicy: .deny, tools: [:])
    )
    let task = ProjectTask(
        id: "TASK-1",
        title: "Launch failure",
        description: "",
        priority: "medium",
        status: ProjectTaskStatus.inProgress.rawValue,
        claimedActorId: "actor-dev",
        claimedAgentId: agentID
    )
    let projectID = "worker-launch-\(UUID().uuidString)"
    await service.store.saveProject(ProjectRecord(id: projectID, name: "Worker Launch", description: "", channels: [], tasks: [task]))
    await service.startTaskRun(
        projectID: projectID,
        taskID: task.id,
        actorID: task.claimedActorId,
        agentID: task.claimedAgentId,
        workerID: nil,
        channelID: nil
    )
    let stream = await service.kanbanEventService.subscribe(projectId: projectID)

    _ = await service.runAgentTask(agentID: agentID, taskID: task.id, objective: "Do work", workingDirectory: nil)
    let afterFirst = try await service.getProject(id: projectID)
    #expect(afterFirst.tasks.first(where: { $0.id == task.id })?.status == ProjectTaskStatus.ready.rawValue)

    _ = await service.runAgentTask(agentID: agentID, taskID: task.id, objective: "Do work", workingDirectory: nil)
    let afterSecond = try await service.getProject(id: projectID)
    let blockedTask = try #require(afterSecond.tasks.first(where: { $0.id == task.id }))
    #expect(blockedTask.status == ProjectTaskStatus.blocked.rawValue)

    let event = await firstKanbanEvent(from: stream) { event in
        event.type == .taskUpdated && event.task?.id == task.id && event.task?.status == ProjectTaskStatus.blocked.rawValue
    }
    #expect(event != nil)

    let runs = await service.listTaskRuns(projectID: projectID, taskID: task.id)
    #expect(runs.suffix(2).allSatisfy { $0.outcome == .failed })

    let activities = await service.listTaskActivities(projectID: projectID, taskID: task.id)
    #expect(activities.contains { $0.field == .status && $0.newValue == ProjectTaskStatus.blocked.rawValue })

    let logs = try await service.listTaskLogs(projectID: projectID, taskID: task.id)
    #expect(logs.contains { $0.kind == "lifecycle" && $0.title == "circuit breaker" })
}
