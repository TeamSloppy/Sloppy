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
        subcommands: [Invoke.self],
        defaultSubcommand: Bootstrap.self
    )
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
