import Foundation
import Testing
@testable import sloppy

#if canImport(CSQLite3)
import CSQLite3

@Suite("SQLite schema versioning")
struct SQLiteSchemaVersionTests {
    private func makeTemporaryDatabasePath() throws -> (root: URL, path: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent("core.sqlite").path)
    }

    private func loadSchema() throws -> String {
        let schemaURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/sloppy/Storage/schema.sql")
        return try String(contentsOf: schemaURL, encoding: .utf8)
    }

    private func withDatabase<T>(path: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private func columnNames(table: String, db: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 1) {
            names.insert(String(cString: text))
        }
        return names
    }

    @Test("fresh database is stamped with the latest schema version and reopens cleanly")
    func freshDatabaseIsStamped() throws {
        let (root, path) = try makeTemporaryDatabasePath()
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = try loadSchema()

        #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: schema) == nil)
        #expect(try withDatabase(path: path) { SQLiteStore.schemaVersion(db: $0) } == SQLiteStore.latestSchemaVersion)

        #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: schema) == nil)
        #expect(try withDatabase(path: path) { SQLiteStore.schemaVersion(db: $0) } == SQLiteStore.latestSchemaVersion)
    }

    @Test("unversioned legacy database gains missing columns and is stamped")
    func legacyDatabaseIsUpgraded() throws {
        let (root, path) = try makeTemporaryDatabasePath()
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = try loadSchema()
        let legacySchema = schema
            .replacingOccurrences(of: "    stage_assignments_json TEXT,\n", with: "")
            .replacingOccurrences(of: "    active_stage TEXT,\n", with: "")

        #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: legacySchema) == nil)
        try withDatabase(path: path) { db in
            // Simulate a database created before schema versioning existed.
            #expect(sqlite3_exec(db, "PRAGMA user_version = 0;", nil, nil, nil) == SQLITE_OK)
            #expect(sqlite3_exec(db, "ALTER TABLE dashboard_project_tasks DROP COLUMN stage_assignments_json;", nil, nil, nil) == SQLITE_OK
                || !columnNames(table: "dashboard_project_tasks", db: db).contains("stage_assignments_json"))
            #expect(sqlite3_exec(db, "ALTER TABLE dashboard_project_tasks DROP COLUMN active_stage;", nil, nil, nil) == SQLITE_OK
                || !columnNames(table: "dashboard_project_tasks", db: db).contains("active_stage"))
        }

        #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: schema) == nil)

        try withDatabase(path: path) { db in
            let columns = columnNames(table: "dashboard_project_tasks", db: db)
            #expect(columns.contains("stage_assignments_json"))
            #expect(columns.contains("active_stage"))
            #expect(SQLiteStore.schemaVersion(db: db) == SQLiteStore.latestSchemaVersion)
        }
    }

    @Test("database written by a newer build is opened without touching its version")
    func newerDatabaseIsLeftAlone() throws {
        let (root, path) = try makeTemporaryDatabasePath()
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = try loadSchema()
        let futureVersion = SQLiteStore.latestSchemaVersion + 5

        #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: schema) == nil)
        try withDatabase(path: path) { db in
            #expect(sqlite3_exec(db, "PRAGMA user_version = \(futureVersion);", nil, nil, nil) == SQLITE_OK)
        }

        #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: schema) == nil)
        #expect(try withDatabase(path: path) { SQLiteStore.schemaVersion(db: $0) } == futureVersion)
    }
}
#endif
