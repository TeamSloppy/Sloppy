import Foundation
import Testing
@testable import sloppy
import Configuration
import Logging
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

@Test
func relayStartupOptionsStorePublicURLAndDisableDashboard() throws {
    var config = CoreConfig.default

    try applyRelayStartupOptions(
        config: &config,
        relayPublicURL: "https://sloppy.example.com",
        relayOnly: true
    )

    #expect(config.nodeMeshPublicURL == "https://sloppy.example.com")
    #expect(!shouldStartDashboard(guiOverride: nil, dashboardOverride: nil, relayOnly: true))
    let metadata = try #require(relayStartupMetadata(config: config))
    #expect(metadata.publicWebSocketURL == "wss://sloppy.example.com/v1/node/mesh/ws")
}

@Test
func relayStartupOptionsRejectInvalidPublicURL() {
    var config = CoreConfig.default

    #expect(throws: Error.self) {
        try applyRelayStartupOptions(
            config: &config,
            relayPublicURL: "not a url",
            relayOnly: false
        )
    }
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

@available(macOS 15.0, *)
@Test
func serverEnvironmentOverridesUseNodeMeshPublicURL() {
    var config = CoreConfig.default

    let envConfig = ConfigReader(providers: [EnvironmentVariablesProvider()])
    applyServerEnvironmentOverrides(
        config: &config,
        envConfig: envConfig,
        environment: ["SLOPPY_NODE_MESH_PUBLIC_URL": "https://relay.example.com"]
    )

    #expect(config.nodeMeshPublicURL == "https://relay.example.com")
}

@Test
func configFileStoreRestoresInvalidPrimaryFromBackup() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-config-restore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configPath = tempRoot.appendingPathComponent("sloppy.json").path
    let backupPath = CoreConfigFileStore.backupPath(for: configPath)
    try Data("{ nope".utf8).write(to: URL(fileURLWithPath: configPath))

    var backupConfig = CoreConfig.default
    backupConfig.listen.port = 26001
    try encodeConfig(backupConfig).write(to: URL(fileURLWithPath: backupPath))

    let result = try CoreConfigFileStore.loadRecovering(path: configPath, currentDirectory: tempRoot.path)

    #expect(result.restoredFromBackup)
    #expect(result.config.listen.port == 26001)
    let restored = try JSONDecoder().decode(CoreConfig.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
    #expect(restored.listen.port == 26001)
}

@Test
func configFileStoreRejectsInvalidPrimaryWithoutBackup() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-config-invalid-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configURL = tempRoot.appendingPathComponent("sloppy.json")
    try Data("{ nope".utf8).write(to: configURL)

    #expect(throws: CoreConfigFileError.self) {
        _ = try CoreConfigFileStore.loadRecovering(path: configURL.path, currentDirectory: tempRoot.path)
    }
    let raw = try String(contentsOf: configURL, encoding: .utf8)
    #expect(raw == "{ nope")
}

@Test
func configFileStoreRestoresMissingPrimaryFromBackup() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-config-missing-primary-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configPath = tempRoot.appendingPathComponent("sloppy.json").path
    let backupPath = CoreConfigFileStore.backupPath(for: configPath)
    var backupConfig = CoreConfig.default
    backupConfig.listen.port = 26002
    try encodeConfig(backupConfig).write(to: URL(fileURLWithPath: backupPath))

    let result = try CoreConfigFileStore.loadRecovering(path: configPath, currentDirectory: tempRoot.path)

    #expect(result.restoredFromBackup)
    #expect(result.config.listen.port == 26002)
    #expect(FileManager.default.fileExists(atPath: configPath))
}

@Test
func missingConfigWithoutBackupInitializesDefaultConfig() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-config-default-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configPath = tempRoot.appendingPathComponent("sloppy.json").path
    let result = try CoreConfigFileStore.loadRecovering(path: configPath, currentDirectory: tempRoot.path)

    #expect(result.initializedFromDefault)
    try ensureServerConfigFileExists(
        path: configPath,
        config: result.config,
        logger: Logger(label: "sloppy.test.config")
    )
    let initialized = try JSONDecoder().decode(CoreConfig.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
    #expect(initialized.listen.port == CoreConfig.default.listen.port)
}

private func encodeConfig(_ config: CoreConfig) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(config) + Data("\n".utf8)
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
