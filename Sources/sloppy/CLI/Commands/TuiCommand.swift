import ArgumentParser

struct TuiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Start the interactive Sloppy terminal UI."
    )

    @Option(name: [.short, .long], help: "Path to JSON config file")
    var configPath: String?

    mutating func run() async throws {
        try await SloppyTUIApp(configPath: configPath).run()
    }
}
