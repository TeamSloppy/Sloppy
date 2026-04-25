import Foundation
import Testing
@testable import sloppy
import Configuration
#if canImport(CSQLite3)
import CSQLite3
#endif

@Test
func bootstrapBulletinDefaultsToVisorConfig() {
    var config = CoreConfig.default
    config.visor.bootstrapBulletin = false
    #expect(!shouldBootstrapVisorBulletin(cliOverride: nil, config: config))

    config.visor.bootstrapBulletin = true
    #expect(shouldBootstrapVisorBulletin(cliOverride: nil, config: config))
}

@Test
func bootstrapBulletinCliOverrideWinsOverConfig() {
    var config = CoreConfig.default
    config.visor.bootstrapBulletin = false
    #expect(shouldBootstrapVisorBulletin(cliOverride: true, config: config))

    config.visor.bootstrapBulletin = true
    #expect(!shouldBootstrapVisorBulletin(cliOverride: false, config: config))
}

@available(macOS 15.0, *)
@Test
func serverEnvironmentOverridesUseSloppyTokenForLegacyAndDashboardAuth() {
    var config = CoreConfig.default
    config.auth.token = ""
    config.ui.dashboardAuth.enabled = true
    config.ui.dashboardAuth.token = ""

    let envConfig = ConfigReader(providers: [EnvironmentVariablesProvider()])
    applyServerEnvironmentOverrides(
        config: &config,
        envConfig: envConfig,
        environment: ["SLOPPY_TOKEN": "env-secret-token"]
    )

    #expect(config.auth.token == "env-secret-token")
    #expect(config.ui.dashboardAuth.token == "env-secret-token")
}

#if canImport(CSQLite3)
@Test
func prepareSQLiteDatabaseCreatesCoreSQLiteWithSchema() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-core-main-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    var config = CoreConfig.default
    config.workspace.basePath = tempRoot.path
    config.workspace.name = "workspace"
    config.sqlitePath = tempRoot
        .appendingPathComponent("workspace/state/core.sqlite")
        .path

    #expect(CorePersistenceFactory.prepareSQLiteDatabaseIfNeeded(config: config) == nil)
    #expect(FileManager.default.fileExists(atPath: config.sqlitePath))

    var db: OpaquePointer?
    #expect(sqlite3_open(config.sqlitePath, &db) == SQLITE_OK)
    defer {
        if let db {
            sqlite3_close(db)
        }
    }

    var statement: OpaquePointer?
    let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'events';"
    #expect(sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    #expect(sqlite3_step(statement) == SQLITE_ROW)
}
#endif
