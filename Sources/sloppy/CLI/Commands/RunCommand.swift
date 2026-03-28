import ArgumentParser
import Configuration
import Foundation
import Logging
import Protocols
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the Sloppy server."
    )

    @Option(name: [.short, .long], help: "Path to JSON config file")
    var configPath: String?

    @Flag(name: .long, inversion: .prefixedNo, help: "Overrides config and controls the immediate visor bulletin after boot")
    var bootstrapBulletin: Bool?

    @Option(name: .customLong("generate-openapi"), help: "Generate OpenAPI (Swagger) specification and save to the provided path")
    var openapiPath: String?

    mutating func run() async throws {
        var runtimeLogger: Logger?

        do {
            var explicitConfigPath = normalizedServerConfigPath(configPath)
            var config = CoreConfig.load(from: explicitConfigPath)

            if #available(macOS 15.0, *) {
                let envConfig = ConfigReader(providers: [EnvironmentVariablesProvider()])
                if let envConfigPath = normalizedServerConfigPath(
                    envConfig.string(forKey: "core.config.path", default: "")
                ) {
                    explicitConfigPath = envConfigPath
                    config = CoreConfig.load(from: explicitConfigPath)
                }

                applyServerEnvironmentOverrides(config: &config, envConfig: envConfig)

                if explicitConfigPath == nil {
                    let workspaceConfigPath = CoreConfig.defaultConfigPath(for: config.workspace)
                    if FileManager.default.fileExists(atPath: workspaceConfigPath) {
                        config = CoreConfig.load(from: workspaceConfigPath)
                        applyServerEnvironmentOverrides(config: &config, envConfig: envConfig)
                    }
                }
            } else if explicitConfigPath == nil {
                let workspaceConfigPath = CoreConfig.defaultConfigPath(for: config.workspace)
                if FileManager.default.fileExists(atPath: workspaceConfigPath) {
                    config = CoreConfig.load(from: workspaceConfigPath)
                }
            }

            let workspaceRoot = try prepareServerWorkspace(config: &config)
            let systemLogFileURL = defaultServerLogFileURL(in: workspaceRoot)
            await ServerLoggingBootstrapper.shared.bootstrapIfNeeded(logFileURL: systemLogFileURL)
            let logger = Logger(label: "sloppy.core.main")
            runtimeLogger = logger
            await ServerFatalSignalLogger.shared.installIfNeeded()
            logger.info("Workspace prepared at \(workspaceRoot.path)")
            logger.info("System logs are persisted at \(systemLogFileURL.path)")

            let resolvedConfigPath = explicitConfigPath ??
                workspaceRoot.appendingPathComponent(CoreConfig.defaultConfigFileName).path
            try ensureServerConfigFileExists(path: resolvedConfigPath, config: config, logger: logger)

            if let error = CorePersistenceFactory.prepareSQLiteDatabaseIfNeeded(config: config) {
                logger.warning("SQLite initialization failed at \(config.sqlitePath): \(error); runtime will use fallback persistence if needed")
            }

            let service = CoreService(config: config, configPath: resolvedConfigPath)
            let router = CoreRouter(service: service)
            let server = CoreHTTPServer(
                host: config.listen.host,
                port: config.listen.port,
                router: router,
                logger: logger
            )

            if let openapiPath = openapiPath {
                let data = try await router.generateOpenAPISpec()
                try data.write(to: URL(fileURLWithPath: openapiPath))
                logger.info("OpenAPI specification generated at \(openapiPath)")

                let docsPublicURL = serverRepoRootURL()
                    .appendingPathComponent("docs/public/swagger.json")
                try FileManager.default.createDirectory(
                    at: docsPublicURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: docsPublicURL, options: .atomic)
                logger.info("OpenAPI specification copied to \(docsPublicURL.path)")
                return
            }

            logger.info("sloppy initialized")

            await service.bootstrapChannelPlugins()

            try server.start()
            printServerStartupBanner(config: config)
            logger.info("sloppy HTTP server listening on \(config.listen.host):\(config.listen.port)")

            if shouldBootstrapVisorBulletin(cliOverride: bootstrapBulletin, config: config) {
                let bulletin = await service.triggerVisorBulletin()
                logger.info("Visor bulletin generated: \(bulletin.headline)")
            }

            logger.info("sloppy foreground server mode is active")
            defer {
                try? server.shutdown()
                Task { await service.shutdownChannelPlugins() }
            }
            try server.waitUntilClosed()
        } catch {
            if let runtimeLogger {
                runtimeLogger.critical("sloppy is exiting because of an unrecoverable error: \(String(describing: error))")
            } else {
                emitServerBootstrapWarning("sloppy is exiting because of an unrecoverable error: \(String(describing: error))")
            }
            throw error
        }
    }
}

// MARK: - Server helpers (previously file-level private in SloppyApp.swift)

func shouldBootstrapVisorBulletin(cliOverride: Bool?, config: CoreConfig) -> Bool {
    cliOverride ?? config.visor.bootstrapBulletin
}

@available(macOS 15.0, *)
func applyServerEnvironmentOverrides(config: inout CoreConfig, envConfig: ConfigReader) {
    config.listen.host = envConfig.string(forKey: "core.listen.host", default: config.listen.host)
    config.listen.port = envConfig.int(forKey: "core.listen.port", default: config.listen.port)
    config.workspace.name = envConfig.string(forKey: "core.workspace.name", default: config.workspace.name)
    let workspaceBasePath = envConfig.string(
        forKey: "core.workspace.base_path",
        default: config.workspace.basePath
    )
    config.workspace.basePath = envConfig.string(
        forKey: "core.workspace.basePath",
        default: workspaceBasePath
    )
    config.auth.token = envConfig.string(forKey: "core.auth.token", default: config.auth.token)
    config.sqlitePath = envConfig.string(forKey: "core.sqlite.path", default: config.sqlitePath)
}

func serverRepoRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func normalizedServerConfigPath(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed
}

func ensureServerConfigFileExists(path: String, config: CoreConfig, logger: Logger) throws {
    let fileManager = FileManager.default
    let configURL = URL(fileURLWithPath: path)
    if fileManager.fileExists(atPath: configURL.path) { return }

    let parentDirectory = configURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let payload = try encoder.encode(config) + Data("\n".utf8)
    try payload.write(to: configURL, options: .atomic)
    logger.info("Config initialized at \(configURL.path)")
}

func prepareServerWorkspace(config: inout CoreConfig) throws -> URL {
    let workspaceRoot = config.resolvedWorkspaceRootURL()

    do {
        try createServerWorkspaceDirectories(at: workspaceRoot)
        config.sqlitePath = resolveServerSQLitePath(sqlitePath: config.sqlitePath, workspaceRoot: workspaceRoot)
        return workspaceRoot
    } catch {
        let fallbackBasePath = "/tmp/sloppy"
        let fallbackRoot = URL(fileURLWithPath: fallbackBasePath, isDirectory: true)
            .appendingPathComponent(config.workspace.name, isDirectory: true)

        emitServerBootstrapWarning(
            "Failed to create workspace at \(workspaceRoot.path), falling back to \(fallbackRoot.path): \(error)"
        )

        try createServerWorkspaceDirectories(at: fallbackRoot)
        config.workspace.basePath = fallbackBasePath
        config.sqlitePath = resolveServerSQLitePath(sqlitePath: config.sqlitePath, workspaceRoot: fallbackRoot)
        return fallbackRoot
    }
}

func createServerWorkspaceDirectories(at workspaceRoot: URL) throws {
    let fileManager = FileManager.default
    let directories = [
        workspaceRoot,
        workspaceRoot.appendingPathComponent("agents", isDirectory: true),
        workspaceRoot.appendingPathComponent("actors", isDirectory: true),
        workspaceRoot.appendingPathComponent("sessions", isDirectory: true),
        workspaceRoot.appendingPathComponent("artifacts", isDirectory: true),
        workspaceRoot.appendingPathComponent("memory", isDirectory: true),
        workspaceRoot.appendingPathComponent("logs", isDirectory: true),
        workspaceRoot.appendingPathComponent("plugins", isDirectory: true),
        workspaceRoot.appendingPathComponent("tmp", isDirectory: true)
    ]

    for directory in directories {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

func resolveServerSQLitePath(sqlitePath: String, workspaceRoot: URL) -> String {
    if sqlitePath.hasPrefix("/") { return sqlitePath }
    return workspaceRoot.appendingPathComponent(sqlitePath).path
}

func defaultServerLogFileURL(in workspaceRoot: URL, now: Date = Date()) -> URL {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    let suffix = formatter.string(from: now)
    return workspaceRoot
        .appendingPathComponent("logs", isDirectory: true)
        .appendingPathComponent("core-\(suffix).log")
}

func emitServerBootstrapWarning(_ message: String) {
    let payload = "[warning] \(message)\n"
    payload.withCString { pointer in
        _ = write(STDERR_FILENO, pointer, strlen(pointer))
    }
}

func printServerStartupBanner(config: CoreConfig) {
    let isColor: Bool = {
        if let term = ProcessInfo.processInfo.environment["TERM"], !term.isEmpty, term != "dumb" {
            return true
        }
        return ProcessInfo.processInfo.environment["COLORTERM"] != nil
            || ProcessInfo.processInfo.environment["FORCE_COLOR"] != nil
    }()

    let cyan  = isColor ? "\u{1B}[36m" : ""
    let green = isColor ? "\u{1B}[32m" : ""
    let dim   = isColor ? "\u{1B}[2m"  : ""
    let bold  = isColor ? "\u{1B}[1m"  : ""
    let reset = isColor ? "\u{1B}[0m"  : ""

    let host = config.listen.host
    let port = config.listen.port
    let authStatus = config.auth.token.isEmpty ? "none" : "ready"

    let rows: [(String, String)] = [
        ("Server", "\(port)"),
        ("API", "http://\(host):\(port)"),
        ("Health", "http://\(host):\(port)/health"),
        ("Auth", authStatus),
        ("Memory", config.memory.backend),
        ("Workspace", config.workspace.name),
    ]

    var info = ""
    for (label, value) in rows {
        let padded = label.padding(toLength: 16, withPad: " ", startingAt: 0)
        info += "\(dim)\(padded)\(reset)\(green)\(value)\(reset)\n"
    }

    let banner = """

    \(cyan)\(bold) ██████  ██       ██████  ██████  ██████  ██    ██
    ██       ██      ██    ██ ██   ██ ██   ██  ██  ██
     █████   ██      ██    ██ ██████  ██████    ████
         ██  ██      ██    ██ ██      ██         ██
    ██████   ███████  ██████  ██      ██         ██\(reset)

    \(cyan)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\(reset)
    \(info)
    """

    let data = Array(banner.utf8)
    data.withUnsafeBufferPointer { buf in
        _ = write(STDERR_FILENO, buf.baseAddress, buf.count)
    }
}

private func signalNameForCode(_ code: Int32) -> String {
    switch code {
    case SIGABRT: return "SIGABRT"
    case SIGILL: return "SIGILL"
    case SIGTRAP: return "SIGTRAP"
    case SIGSEGV: return "SIGSEGV"
    case SIGBUS: return "SIGBUS"
    case SIGFPE: return "SIGFPE"
    default: return "UNKNOWN"
    }
}

private func coreFatalSignalHandler(_ signalCode: Int32) {
    let signalName = signalNameForCode(signalCode)
    let text = "sloppy fatal signal \(signalCode) (\(signalName)). Process will exit.\n"
    text.withCString { pointer in
        _ = write(STDERR_FILENO, pointer, strlen(pointer))
    }

    _ = signal(signalCode, SIG_DFL)
    _ = raise(signalCode)
}

actor ServerLoggingBootstrapper {
    static let shared = ServerLoggingBootstrapper()

    private var isBootstrapped = false

    func bootstrapIfNeeded(logFileURL: URL) {
        guard !isBootstrapped else { return }
        SystemJSONLLogHandler.configure(fileURL: logFileURL)
        LoggingSystem.bootstrap { label in
            MultiplexLogHandler([
                ColoredLogHandler.standardError(label: label),
                SystemJSONLLogHandler(label: label)
            ])
        }
        isBootstrapped = true
    }
}

actor ServerFatalSignalLogger {
    static let shared = ServerFatalSignalLogger()

    private var isInstalled = false
    private let trackedSignals: [Int32] = [SIGABRT, SIGILL, SIGTRAP, SIGSEGV, SIGBUS, SIGFPE]

    func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true
        for code in trackedSignals {
            _ = signal(code, coreFatalSignalHandler)
        }
    }
}
