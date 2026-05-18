import ArgumentParser
import Foundation

struct SourceControlCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "source-control",
        abstract: "Manage source-control providers.",
        subcommands: [
            SourceControlListCommand.self,
        ]
    )
}

struct SourceControlListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List source-control providers.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/source-control/providers")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}
