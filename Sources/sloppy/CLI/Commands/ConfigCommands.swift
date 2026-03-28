import ArgumentParser
import Foundation

struct ConfigCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View and update runtime configuration.",
        subcommands: [ConfigGetCommand.self, ConfigSetCommand.self]
    )
}

struct ConfigGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Get current runtime configuration.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/config")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ConfigSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Update runtime configuration.")

    @Option(name: .long, help: "Path to JSON config file") var file: String?
    @Option(name: .long, help: "Inline JSON config string") var json: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let body: Data
        if let file {
            body = try Data(contentsOf: URL(fileURLWithPath: file))
        } else if let json {
            guard let data = json.data(using: .utf8) else {
                CLIStyle.error("Invalid JSON string."); throw ExitCode.failure
            }
            body = data
        } else {
            CLIStyle.error("Provide --file or --json."); throw ExitCode.failure
        }
        do {
            let data = try await client.put("/v1/config", body: body)
            CLIStyle.success("Config updated.")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}
