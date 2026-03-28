import ArgumentParser
import Foundation

@main
struct SloppyApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sloppy",
        abstract: "AI agent runtime and CLI.",
        subcommands: [
            RunCommand.self,
            AgentCommand.self,
            ProjectCommand.self,
            ChannelCommand.self,
            ConfigCommand.self,
            ProvidersCommand.self,
            ActorCommand.self,
            PluginCommand.self,
            MCPCommand.self,
            VisorCommand.self,
            SkillsCommand.self,
            StatusCommand.self,
            UpdateCommand.self,
            LogsCommand.self,
            WorkersCommand.self,
            BulletinsCommand.self,
            TokenUsageCommand.self,
        ]
    )

    @Flag(name: .customLong("version"), help: "Print the current sloppy version.")
    var printVersion: Bool = false

    mutating func run() async throws {
        if printVersion {
            print("sloppy \(SloppyVersion.current)")
            return
        }
        CLIStyle.printHelp()
    }
}
