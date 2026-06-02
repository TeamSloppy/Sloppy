import Foundation
import Testing
@testable import sloppy
@testable import Protocols

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
