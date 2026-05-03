import ArgumentParser

struct TuiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Start the interactive Sloppy terminal UI."
    )

    @Option(name: [.short, .long], help: "Path to JSON config file")
    var configPath: String?

    @Option(name: [.customShort("s"), .long], help: "Resume directly from an agent session ID.")
    var session: String?

    mutating func run() async throws {
        try await SloppyTUIApp(configPath: configPath, requestedSessionID: session).run()
    }
}
