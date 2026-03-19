import Foundation
import Testing
@testable import Core
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
    #expect(activities.count == 1)
    #expect(activities[0].field == .status)
    #expect(activities[0].oldValue == "backlog")
    #expect(activities[0].newValue == "ready")
    #expect(activities[0].actorId == "actor-alice")
    #expect(activities[0].taskId == taskID)
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
    #expect(activities.count == 1)
    #expect(activities[0].actorId == "user")
}
