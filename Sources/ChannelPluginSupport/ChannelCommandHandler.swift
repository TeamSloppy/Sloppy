import Foundation

public struct BotCommand: Sendable {
    public let name: String
    public let description: String
    public let argument: String?

    public init(name: String, description: String, argument: String? = nil) {
        self.name = name
        self.description = description
        self.argument = argument
    }
}

/// Handles shared channel bot commands across built-in gateway plugins.
public struct ChannelCommandHandler: Sendable {
    public static let commands: [BotCommand] = [
        BotCommand(name: "help", description: "Show available commands"),
        BotCommand(name: "status", description: "Check plugin connectivity"),
        BotCommand(name: "task", description: "Create a task via Sloppy", argument: "description"),
        BotCommand(name: "model", description: "Show or switch model", argument: "model_id"),
        BotCommand(name: "context", description: "Show token usage and context info"),
        BotCommand(name: "abort", description: "Abort current agent processing"),
    ]

    private let platformName: String

    public init(platformName: String) {
        self.platformName = platformName
    }

    public func handle(text: String, from displayName: String) -> String? {
        _ = displayName
        let lower = text.lowercased()

        if lower == "/start" || lower == "/help" {
            let lines = Self.commands.map { cmd -> String in
                let usage = cmd.argument.map { " <\($0)>" } ?? ""
                let padded = "/\(cmd.name)\(usage)".padding(toLength: 22, withPad: " ", startingAt: 0)
                return "\(padded)— \(cmd.description)"
            }.joined(separator: "\n")
            return """
            Sloppy Channel Plugin (\(platformName))

            Available commands:
            \(lines)

            Any other message is forwarded to the linked Sloppy channel.
            """
        }

        if lower == "/status" {
            return "Plugin is running. Messages are forwarded to Sloppy."
        }

        if lower.hasPrefix("/task ") {
            return nil
        }

        if lower == "/model" || lower.hasPrefix("/model ") {
            return nil
        }

        if lower == "/context" {
            return nil
        }

        if lower == "/abort" {
            return nil
        }

        if lower.hasPrefix("/") {
            return "Unknown command. Send /help for available commands."
        }

        return nil
    }
}
