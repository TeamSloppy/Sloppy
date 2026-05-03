import ArgumentParser

struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "Open the interactive model picker for the current TUI agent."
    )

    @Option(name: [.short, .long], help: "Path to JSON config file")
    var configPath: String?

    @Option(name: [.customShort("s"), .long], help: "Resume model selection from an agent session ID.")
    var session: String?

    mutating func run() async throws {
        try await SloppyTUIApp(
            configPath: configPath,
            requestedSessionID: session,
            initialAction: .modelPicker(exitAfterSelection: true)
        ).run()
    }
}
