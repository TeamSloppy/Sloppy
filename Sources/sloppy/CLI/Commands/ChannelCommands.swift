import ArgumentParser
import Foundation

struct ChannelCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "channel",
        abstract: "Inspect and control channels.",
        subcommands: [
            ChannelStateCommand.self,
            ChannelEventsCommand.self,
            ChannelMessageCommand.self,
            ChannelModelCommand.self,
            ChannelControlCommand.self,
        ]
    )
}

struct ChannelStateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "state", abstract: "Get channel state.")

    @Argument(help: "Channel ID") var channelId: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/channels/\(channelId)/state")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ChannelEventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "events", abstract: "Get channel event history.")

    @Argument(help: "Channel ID") var channelId: String
    @Option(name: .long, help: "Number of events to fetch") var limit: Int = 50
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/channels/\(channelId)/events", query: ["limit": "\(limit)"])
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ChannelMessageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "message", abstract: "Send a message to a channel.")

    @Argument(help: "Channel ID") var channelId: String
    @Option(name: .long, help: "Message content") var content: String
    @Option(name: .long, help: "User ID") var userId: String = "cli"
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let payload: [String: Any] = ["content": content, "userId": userId]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/channels/\(channelId)/messages", body: body)
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ChannelModelCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "model",
        abstract: "View or override channel model.",
        subcommands: [
            ChannelModelGetCommand.self,
            ChannelModelSetCommand.self,
            ChannelModelClearCommand.self,
        ]
    )
}

struct ChannelModelGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Get channel model override.")

    @Argument(help: "Channel ID") var channelId: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/channels/\(channelId)/model")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ChannelModelSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set channel model override.")

    @Argument(help: "Channel ID") var channelId: String
    @Option(name: .long, help: "Model identifier") var model: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let payload: [String: Any] = ["model": model]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.put("/v1/channels/\(channelId)/model", body: body)
            CLIStyle.success("Channel model set to \(CLIStyle.whiteBold(model)).")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ChannelModelClearCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "clear", abstract: "Clear channel model override.")

    @Argument(help: "Channel ID") var channelId: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            _ = try await client.delete("/v1/channels/\(channelId)/model")
            CLIStyle.success("Channel model override cleared.")
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ChannelControlCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "control", abstract: "Send a control action to a channel.")

    @Argument(help: "Channel ID") var channelId: String
    @Option(name: .long, help: "Action: abort, pause, resume") var action: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let payload: [String: Any] = ["action": action]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            _ = try await client.post("/v1/channels/\(channelId)/control", body: body)
            CLIStyle.success("Control action '\(action)' sent to channel \(CLIStyle.whiteBold(channelId)).")
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}
