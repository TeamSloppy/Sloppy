import ArgumentParser

protocol SloppyGroupCommand: AsyncParsableCommand {}

extension SloppyGroupCommand {
    mutating func run() async throws {
        let visible = Self.configuration.subcommands.filter { $0.configuration.shouldDisplay }
        CLIStyle.printGroupHelp(
            commandName: Self.configuration.commandName ?? "",
            abstract: Self.configuration.abstract,
            subcommands: visible
        )
    }
}
