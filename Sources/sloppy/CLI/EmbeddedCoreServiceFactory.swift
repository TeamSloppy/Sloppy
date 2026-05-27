import Foundation
import Logging

struct EmbeddedCoreServiceFactory {
    static func make(configPath: String?, loggerLabel: String) async throws -> CoreService {
        let homeDirectory = CoreConfig.resolvedHomeDirectoryPath()
        var explicitConfigPath = normalizedServerConfigPath(configPath)
        var config = try loadServerConfigRecovering(from: explicitConfigPath, currentDirectory: homeDirectory)

        if explicitConfigPath == nil {
            let workspaceConfigPath = CoreConfig.defaultConfigPath(
                for: config.workspace,
                currentDirectory: homeDirectory
            )
            if CoreConfigFileStore.hasConfigOrBackup(at: workspaceConfigPath) {
                explicitConfigPath = workspaceConfigPath
                config = try loadServerConfigRecovering(from: workspaceConfigPath, currentDirectory: homeDirectory)
            }
        }

        let workspaceRoot = try prepareServerWorkspace(config: &config, currentDirectory: homeDirectory)
        let systemLogFileURL = defaultServerLogFileURL(in: workspaceRoot)
        await ServerLoggingBootstrapper.shared.bootstrapIfNeeded(logFileURL: systemLogFileURL)

        let logger = Logger(label: loggerLabel)
        logger.info("Embedded Sloppy core workspace prepared at \(workspaceRoot.path)")

        let resolvedConfigPath = explicitConfigPath ??
            workspaceRoot.appendingPathComponent(CoreConfig.defaultConfigFileName).path
        try ensureServerConfigFileExists(path: resolvedConfigPath, config: config, logger: logger)

        if let error = CorePersistenceFactory.prepareSQLiteDatabaseIfNeeded(config: config) {
            logger.warning("SQLite initialization failed at \(config.sqlitePath): \(error); runtime will use fallback persistence if needed")
        }

        return CoreService(config: config, configPath: resolvedConfigPath, currentDirectory: homeDirectory)
    }
}
