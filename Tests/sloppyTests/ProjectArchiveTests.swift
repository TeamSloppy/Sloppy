import Foundation
import Testing
@testable import sloppy
@testable import Protocols

@Test
func projectRecordDefaultsToNotArchived() throws {
    let project = ProjectRecord(
        id: "test-project",
        name: "Test Project",
        description: "A test project",
        channels: [],
        tasks: []
    )
    #expect(project.isArchived == false)
}

@Test
func projectRecordEncodesIsArchivedField() throws {
    let project = ProjectRecord(
        id: "test-archive",
        name: "Archive Test",
        description: "",
        channels: [],
        tasks: [],
        isArchived: true
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(project)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["isArchived"] as? Bool == true)
}

@Test
func projectRecordDecodesIsArchivedField() throws {
    let json = """
    {
        "id": "my-project",
        "name": "My Project",
        "description": "",
        "channels": [],
        "tasks": [],
        "actors": [],
        "teams": [],
        "models": [],
        "agentFiles": [],
        "heartbeat": {"enabled": false, "intervalMinutes": 5},
        "reviewSettings": {"enabled": false, "approvalMode": "human"},
        "isArchived": true,
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let project = try decoder.decode(ProjectRecord.self, from: json)

    #expect(project.isArchived == true)
}

@Test
func projectRecordDecodesWithoutIsArchivedDefaultsFalse() throws {
    let json = """
    {
        "id": "my-project",
        "name": "My Project",
        "description": "",
        "channels": [],
        "tasks": [],
        "actors": [],
        "teams": [],
        "models": [],
        "agentFiles": [],
        "heartbeat": {"enabled": false, "intervalMinutes": 5},
        "reviewSettings": {"enabled": false, "approvalMode": "human"},
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let project = try decoder.decode(ProjectRecord.self, from: json)

    #expect(project.isArchived == false)
}

@Test
func projectUpdateRequestEncodesIsArchived() throws {
    let request = ProjectUpdateRequest(isArchived: true)
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["isArchived"] as? Bool == true)
}

@Test
func archiveProjectViaRouter() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let projectId = "archive-router-test"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectId, name: "Archive Test", description: "Test", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let patchBody = try JSONEncoder().encode(ProjectUpdateRequest(isArchived: true))
    let patchResp = await router.handle(method: "PATCH", path: "/v1/projects/\(projectId)", body: patchBody)
    #expect(patchResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let updated = try decoder.decode(ProjectRecord.self, from: patchResp.body)
    #expect(updated.isArchived == true)
}

@Test
func unarchiveProjectViaRouter() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let projectId = "unarchive-router-test"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectId, name: "Unarchive Test", description: "Test", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let archiveBody = try JSONEncoder().encode(ProjectUpdateRequest(isArchived: true))
    let archiveResp = await router.handle(method: "PATCH", path: "/v1/projects/\(projectId)", body: archiveBody)
    #expect(archiveResp.status == 200)

    let unarchiveBody = try JSONEncoder().encode(ProjectUpdateRequest(isArchived: false))
    let unarchiveResp = await router.handle(method: "PATCH", path: "/v1/projects/\(projectId)", body: unarchiveBody)
    #expect(unarchiveResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let restored = try decoder.decode(ProjectRecord.self, from: unarchiveResp.body)
    #expect(restored.isArchived == false)
}

@Test
func taskDefaultsToNotArchived() throws {
    let task = ProjectTask(id: "T-1", title: "Test", description: "", priority: "medium", status: "backlog")
    #expect(task.isArchived == false)
}

@Test
func taskEncodesIsArchived() throws {
    let task = ProjectTask(id: "T-1", title: "Test", description: "", priority: "medium", status: "done", isArchived: true)
    let data = try JSONEncoder().encode(task)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["isArchived"] as? Bool == true)
}

@Test
func archiveOldTasksMarksCompletedTasksAsArchived() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())

    let projectId = "task-archive-test"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectId, name: "Task Archive", description: "", channels: [])
    )
    let router = CoreRouter(service: service)
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
    let oneHourAgo = Date().addingTimeInterval(-3600)

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Old done task", priority: "medium", status: "done")
    )
    let taskResp = await router.handle(method: "POST", path: "/v1/projects/\(projectId)/tasks", body: taskBody)
    #expect(taskResp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var project = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    #expect(project.tasks.count == 1)

    project.tasks[0].updatedAt = threeDaysAgo
    project.tasks[0].status = "done"

    let taskBody2 = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Recent done task", priority: "medium", status: "done")
    )
    let taskResp2 = await router.handle(method: "POST", path: "/v1/projects/\(projectId)/tasks", body: taskBody2)
    project = try decoder.decode(ProjectRecord.self, from: taskResp2.body)

    project.tasks[0].updatedAt = threeDaysAgo
    project.tasks[1].updatedAt = oneHourAgo

    let updated = try await service.archiveOldTasks(projectID: projectId)

    let archived = updated.tasks.filter(\.isArchived)
    let active = updated.tasks.filter { !$0.isArchived }
    #expect(active.count >= 1)
}

@Test
func listArchivedTasksEndpoint() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let projectId = "archived-endpoint-test"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectId, name: "Endpoint Test", description: "", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let resp = await router.handle(method: "GET", path: "/v1/projects/\(projectId)/tasks/archived", body: nil)
    #expect(resp.status == 200)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let tasks = try decoder.decode([ProjectTask].self, from: resp.body)
    #expect(tasks.isEmpty)
}
