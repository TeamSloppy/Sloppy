import ArgumentParser
import Foundation

struct SkillsCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "Browse the skills registry.",
        subcommands: [SkillsSearchCommand.self]
    )
}

struct SkillsSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "Search available skills.")

    @Option(name: .long, help: "Search query") var query: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        var queryParams: [String: String] = [:]
        if let query { queryParams["query"] = query }
        do {
            let data = try await client.get("/v1/skills/registry", query: queryParams)
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}
