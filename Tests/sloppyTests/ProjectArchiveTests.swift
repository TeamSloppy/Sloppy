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
