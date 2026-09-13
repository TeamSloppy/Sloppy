import Foundation
import Testing
import Protocols
@testable import sloppy

@Test
func automaticTaskPickupDisabledBlocksStartupMaintenanceAndReadyTransitions() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let project = ProjectRecord(
        id: "pickup-disabled", name: "Workers", description: "", channels: [],
        tasks: [ProjectTask(id: "ready", title: "Ready", description: "", priority: "medium", status: "ready")],
        automaticTaskPickupEnabled: false,
        autopilotSettings: ProjectAutopilotSettings(enabled: true)
    )
    await service.store.saveProject(project)
    await service.waitForStartup()
    let maintenance = await service.runKanbanMaintenanceNow()
    #expect(maintenance.dispatchAttemptedTaskIds.isEmpty)
    #expect(await service.store.project(id: project.id)?.tasks.first?.status == "ready")

    _ = try await service.updateProjectTask(projectID: project.id, taskID: "ready", request: .init(status: "backlog"))
    await service.processAutonomousExecution()
    #expect(await service.store.project(id: project.id)?.tasks.first?.status == "backlog")
    _ = try await service.updateProjectTask(projectID: project.id, taskID: "ready", request: .init(status: "ready"))
    #expect(await service.store.project(id: project.id)?.tasks.first?.status == "ready")
    #expect(await service.runtime.workerSnapshots().isEmpty)

    let unrelatedUpdate = try await service.updateProject(projectID: project.id, request: .init(name: "Renamed"))
    #expect(unrelatedUpdate.automaticTaskPickupEnabled == false)
    _ = try await service.updateProject(projectID: project.id, request: .init(automaticTaskPickupEnabled: true))
    let resumed = await service.runKanbanMaintenanceNow()
    #expect(resumed.dispatchAttemptedTaskIds == ["ready"])
    #expect(await service.store.project(id: project.id)?.tasks.first?.status != "ready")
}

@Test
func automaticTaskPickupSettingsPersistAcrossSQLiteReopen() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let schemaURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/sloppy/Storage/schema.sql")
    let schema = try String(contentsOf: schemaURL, encoding: .utf8)
    let legacySchema = schema.replacingOccurrences(
        of: "    automatic_task_pickup_enabled INTEGER NOT NULL DEFAULT 1,\n", with: ""
    )
    let path = root.appendingPathComponent("core.sqlite").path
    #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: legacySchema + """
    INSERT INTO dashboard_projects (id, name, description, created_at, updated_at)
    VALUES ('legacy', 'Legacy', '', '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z');
    """) == nil)
    let store = SQLiteStore(path: path, schemaSQL: schema)
    let project = ProjectRecord(id: "project", name: "Project", description: "", channels: [], tasks: [],
                                automaticTaskPickupEnabled: false)
    await store.saveProject(project)
    let reopened = SQLiteStore(path: path, schemaSQL: schema,
                               fallbackProjectsPath: root.appendingPathComponent("empty.json").path)
    #expect(await reopened.project(id: project.id)?.automaticTaskPickupEnabled == false)
    #expect(await reopened.listProjects().first { $0.id == project.id }?.automaticTaskPickupEnabled == false)
    #expect(await reopened.project(id: "legacy")?.automaticTaskPickupEnabled == true)
    let decoded = try JSONDecoder().decode(ProjectRecord.self, from: JSONEncoder().encode(project))
    #expect(decoded.automaticTaskPickupEnabled == false)
}
