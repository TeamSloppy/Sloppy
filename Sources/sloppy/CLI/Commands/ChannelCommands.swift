import ArgumentParser
import Foundation

enum ChannelIDResolver {
    static func resolve(channelId: String, agent: String?) -> String {
        guard let agent = agent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !agent.isEmpty else {
            return channelId
        }
        return "agent:\(agent):session:\(channelId)"
    }
}

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
    @Option(name: .long, help: "Agent ID (resolves channel as agent:AGENT:session:CHANNEL_ID)") var agent: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let resolvedId = ChannelIDResolver.resolve(channelId: channelId, agent: agent)
        do {
            let data = try await client.get("/v1/channels/\(resolvedId)/state")
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
    @Option(name: .long, help: "Agent ID (resolves channel as agent:AGENT:session:CHANNEL_ID)") var agent: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let resolvedId = ChannelIDResolver.resolve(channelId: channelId, agent: agent)
        do {
            let data = try await client.get("/v1/channels/\(resolvedId)/events", query: ["limit": "\(limit)"])
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
    @Option(name: .long, help: "Agent ID (resolves channel as agent:AGENT:session:CHANNEL_ID)") var agent: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let resolvedId = ChannelIDResolver.resolve(channelId: channelId, agent: agent)
        let payload: [String: Any] = ["content": content, "userId": userId]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/channels/\(resolvedId)/messages", body: body)
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
    @Option(name: .long, help: "Agent ID (resolves channel as agent:AGENT:session:CHANNEL_ID)") var agent: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let resolvedId = ChannelIDResolver.resolve(channelId: channelId, agent: agent)
        do {
            let data = try await client.get("/v1/channels/\(resolvedId)/model")
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
    @Option(name: .long, help: "Agent ID (resolves channel as agent:AGENT:session:CHANNEL_ID)") var agent: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let resolvedId = ChannelIDResolver.resolve(channelId: channelId, agent: agent)
        let payload: [String: Any] = ["model": model]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.put("/v1/channels/\(resolvedId)/model", body: body)
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
    @Option(name: .long, help: "Agent ID (resolves channel as agent:AGENT:session:CHANNEL_ID)") var agent: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let resolvedId = ChannelIDResolver.resolve(channelId: channelId, agent: agent)
        do {
            _ = try await client.delete("/v1/channels/\(resolvedId)/model")
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
    @Option(name: .long, help: "Agent ID (resolves channel as agent:AGENT:session:CHANNEL_ID)") var agent: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let resolvedId = ChannelIDResolver.resolve(channelId: channelId, agent: agent)
        let payload: [String: Any] = ["action": action]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            _ = try await client.post("/v1/channels/\(resolvedId)/control", body: body)
            CLIStyle.success("Control action '\(action)' sent to channel \(CLIStyle.whiteBold(resolvedId)).")
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}
