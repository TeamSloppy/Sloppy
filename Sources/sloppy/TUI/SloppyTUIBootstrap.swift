import Configuration
import Foundation
import Logging

struct SloppyTUIRuntime {
    var service: CoreService
    var config: CoreConfig
    var configPath: String
    var workspaceRoot: URL
    var cwd: String
}

struct SloppyTUIBootstrap {
    var configPath: String?
    var cwd: String
    var environment: [String: String]

    init(
        configPath: String? = nil,
        cwd: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.configPath = configPath
        self.cwd = cwd
        self.environment = environment
    }

    func prepare() async throws -> SloppyTUIRuntime {
        let homeDirectory = CoreConfig.resolvedHomeDirectoryPath(environment: environment)
        var explicitConfigPath = normalizedServerConfigPath(configPath)
        var config = CoreConfig.load(from: explicitConfigPath, currentDirectory: homeDirectory)

        if #available(macOS 15.0, *) {
            let envConfig = ConfigReader(providers: [EnvironmentVariablesProvider()])
            if let envConfigPath = normalizedServerConfigPath(
                envConfig.string(forKey: "core.config.path", default: "")
            ) {
                explicitConfigPath = envConfigPath
                config = CoreConfig.load(from: explicitConfigPath, currentDirectory: homeDirectory)
            }

            applyServerEnvironmentOverrides(config: &config, envConfig: envConfig, environment: environment)

            if explicitConfigPath == nil {
                let workspaceConfigPath = CoreConfig.defaultConfigPath(
                    for: config.workspace,
                    currentDirectory: homeDirectory
                )
                if FileManager.default.fileExists(atPath: workspaceConfigPath) {
                    config = CoreConfig.load(from: workspaceConfigPath, currentDirectory: homeDirectory)
                    applyServerEnvironmentOverrides(config: &config, envConfig: envConfig, environment: environment)
                }
            }
        } else if explicitConfigPath == nil {
            let workspaceConfigPath = CoreConfig.defaultConfigPath(
                for: config.workspace,
                currentDirectory: homeDirectory
            )
            if FileManager.default.fileExists(atPath: workspaceConfigPath) {
                config = CoreConfig.load(from: workspaceConfigPath, currentDirectory: homeDirectory)
            }
        }

        let workspaceRoot = try prepareServerWorkspace(config: &config, currentDirectory: homeDirectory)
        let systemLogFileURL = defaultServerLogFileURL(in: workspaceRoot)
        await TUILoggingBootstrapper.shared.bootstrapIfNeeded(logFileURL: systemLogFileURL)
        let resolvedConfigPath = explicitConfigPath ??
            workspaceRoot.appendingPathComponent(CoreConfig.defaultConfigFileName).path
        let logger = Logger(label: "sloppy.tui.bootstrap")
        try ensureServerConfigFileExists(path: resolvedConfigPath, config: config, logger: logger)

        if let error = CorePersistenceFactory.prepareSQLiteDatabaseIfNeeded(config: config) {
            logger.warning("SQLite initialization failed at \(config.sqlitePath): \(error); runtime will use fallback persistence if needed")
        }

        let service = CoreService(config: config, configPath: resolvedConfigPath, currentDirectory: homeDirectory)
        await service.bootstrapChannelPlugins()

        return SloppyTUIRuntime(
            service: service,
            config: config,
            configPath: resolvedConfigPath,
            workspaceRoot: workspaceRoot,
            cwd: cwd
        )
    }
}

actor TUILoggingBootstrapper {
    static let shared = TUILoggingBootstrapper()

    private var isBootstrapped = false

    func bootstrapIfNeeded(logFileURL: URL) {
        guard !isBootstrapped else { return }
        SystemJSONLLogHandler.configure(fileURL: logFileURL)
        LoggingSystem.bootstrap { label in
            SystemJSONLLogHandler(label: label)
        }
        isBootstrapped = true
    }
}
