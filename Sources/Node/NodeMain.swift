import ArgumentParser
import Foundation
import Logging
import SloppyNodeCore
import Protocols

@main
struct NodeMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sloppy-node",
        abstract: "Runs the standalone Sloppy local executor.",
        subcommands: [Init.self, Status.self, Start.self, Invoke.self],
        defaultSubcommand: Bootstrap.self
    )
}

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initializes local SloppyNode identity and config."
    )

    @Option(name: .long, help: "Human-readable node name.")
    var name: String = Host.current().localizedName ?? "local-node"

    @Option(name: .long, parsing: .upToNextOption, help: "Node roles, comma-separated or repeated.")
    var roles: [String] = ["client", "worker"]

    @Option(name: .long, parsing: .upToNextOption, help: "Node capabilities, comma-separated or repeated.")
    var capabilities: [String] = ["run_shell", "local_files"]

    @Option(name: .long, help: "Optional relay URL for future persistent connections.")
    var relay: String?

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    @Flag(name: .long, help: "Replace an existing config.")
    var force: Bool = false

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let store = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try store.initialize(
            name: name,
            roles: normalizeList(roles),
            capabilities: normalizeList(capabilities),
            relayURL: relay,
            force: force
        )

        print("Initialized SloppyNode")
        print("  id: \(config.identity.nodeId)")
        print("  name: \(config.identity.name)")
        print("  roles: \(config.identity.roles.joined(separator: ","))")
        print("  capabilities: \(config.identity.capabilities.joined(separator: ","))")
        print("  publicKey: \(config.identity.publicKey)")
        print("  config: \(store.configURL.path)")
    }
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Prints local SloppyNode identity and runtime status."
    )

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let store = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try store.load()
        let daemon = NodeDaemon(config: config)
        await daemon.connect()
        let response = await daemon.invoke(NodeActionRequest(action: .status))
        let state = response.data?.asObject?["state"]?.asString ?? "unknown"

        print("SloppyNode status")
        print("  id: \(config.identity.nodeId)")
        print("  name: \(config.identity.name)")
        print("  state: \(state)")
        print("  roles: \(config.identity.roles.joined(separator: ","))")
        print("  capabilities: \(config.identity.capabilities.joined(separator: ","))")
        print("  relay: \(config.relayURL ?? "-")")
        print("  config: \(store.configURL.path)")
    }
}

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Runs SloppyNode as a foreground daemon process."
    )

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    @Option(name: .long, help: "Heartbeat interval in seconds.")
    var heartbeatInterval: Double = 15

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let logger = Logger(label: "sloppy.node.start")
        let store = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try store.load()
        let daemon = NodeDaemon(config: config)
        await daemon.connect()
        logger.info("SloppyNode \(config.identity.nodeId) started name=\(config.identity.name) relay=\(config.relayURL ?? "none")")

        while !Task.isCancelled {
            await daemon.heartbeat()
            try await Task.sleep(nanoseconds: UInt64(max(1, heartbeatInterval) * 1_000_000_000))
        }
    }
}

struct Bootstrap: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bootstrap",
        abstract: "Runs the legacy bootstrap command."
    )

    @Option(name: [.short, .long], help: "Node identifier")
    var nodeId: String = "node-local"

    @Option(name: .long, help: "Bootstrap command path")
    var command: String = "/bin/echo"

    @Option(name: .long, parsing: .upToNextOption, help: "Bootstrap command arguments")
    var arguments: [String] = ["Node daemon ready"]

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let logger = Logger(label: "sloppy.node.main")

        let daemon = NodeDaemon(nodeId: nodeId)
        await daemon.connect()
        await daemon.heartbeat()

        do {
            let result = try await daemon.spawnProcess(command: command, arguments: arguments)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Node \(nodeId) process exit=\(result.exitCode) stdout=\(stdout)")
        } catch {
            logger.error("Node daemon failed to spawn process: \(String(describing: error))")
        }
    }
}

struct Invoke: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "invoke",
        abstract: "Runs one JSON node action request."
    )

    @Option(name: [.short, .long], help: "Node identifier")
    var nodeId: String = "node-local"

    @Flag(name: .long, help: "Read a NodeActionRequest JSON object from stdin.")
    var stdin: Bool = false

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let daemon = NodeDaemon(nodeId: nodeId)
        await daemon.connect()
        await daemon.heartbeat()

        let input: Data
        if stdin {
            input = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            throw ValidationError("Use --stdin to provide a JSON request.")
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let response: NodeActionResponse
        do {
            let request = try decoder.decode(NodeActionRequest.self, from: input)
            response = await daemon.invoke(request)
        } catch {
            response = .failure(action: .status, code: "invalid_json", message: error.localizedDescription)
        }

        let data = try encoder.encode(response)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func configURL(from path: String?) -> URL {
    guard let path, !path.isEmpty else {
        return NodeConfigStore.defaultConfigURL()
    }
    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2)))
    }
    return URL(fileURLWithPath: path)
}

private func normalizeList(_ values: [String]) -> [String] {
    values
        .flatMap { $0.split(separator: ",") }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private actor LoggingBootstrapper {
    static let shared = LoggingBootstrapper()

    private var isBootstrapped = false

    func bootstrapIfNeeded() {
        guard !isBootstrapped else {
            return
        }

        LoggingSystem.bootstrap(ColoredLogHandler.standardError)
        isBootstrapped = true
    }
}
