import Foundation
import Testing
import Protocols
@testable import sloppy

@Test("column entry dates survive SQLite reopen and legacy-schema migration")
func projectTaskKanbanPersistence() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let schemaURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/sloppy/Storage/schema.sql")
    let schema = try String(contentsOf: schemaURL, encoding: .utf8)
    let legacySchema = schema.replacingOccurrences(
        of: ",\n    kanban_column_entered_at TEXT", with: ""
    )
    let path = root.appendingPathComponent("core.sqlite").path
    #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: legacySchema) == nil)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    var project = ProjectRecord(id: "project", name: "Project", description: "", channels: [], tasks: [
        ProjectTask(id: "known", title: "Known date", description: "", priority: "low", status: "in_progress",
                    kanbanColumnEnteredAt: date),
        ProjectTask(id: "legacy", title: "Unknown date", description: "", priority: "low", status: "done",
                    kanbanColumnEnteredAt: nil),
    ])
    let store = SQLiteStore(path: path, schemaSQL: schema)
    await store.saveProject(project)
    // Reopen with a separate empty fallback file so this assertion exercises SQLite.
    let reopened = SQLiteStore(path: path, schemaSQL: schema,
                               fallbackProjectsPath: root.appendingPathComponent("empty-fallback.json").path)
    let loaded = try #require(await reopened.project(id: project.id))
    #expect(loaded.tasks.first { $0.id == "known" }?.kanbanColumnEnteredAt == date)
    #expect(loaded.tasks.first { $0.id == "legacy" }?.kanbanColumnEnteredAt == nil)
    project.tasks[0].title = "Edited"
    await store.saveProject(project)
    #expect(await reopened.project(id: project.id)?.tasks.first { $0.id == "known" }?.kanbanColumnEnteredAt == date)
}
