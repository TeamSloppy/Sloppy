import ArgumentParser
import Foundation

struct ActorCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "actor",
        abstract: "Manage actor board, nodes, links, teams.",
        subcommands: [
            ActorBoardCommand.self,
            ActorNodeCommand.self,
            ActorLinkCommand.self,
            ActorTeamCommand.self,
            ActorRouteCommand.self,
        ]
    )
}

struct ActorBoardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "board", abstract: "Get the actor board.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/actors/board")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorNodeCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "node",
        abstract: "Manage actor nodes.",
        subcommands: [ActorNodeCreateCommand.self, ActorNodeUpdateCommand.self, ActorNodeDeleteCommand.self]
    )
}

struct ActorNodeCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an actor node.")

    @Option(name: .long, help: "Actor ID") var id: String
    @Option(name: .long, help: "Actor name") var name: String
    @Option(name: .long, help: "Actor role") var role: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let payload: [String: Any] = ["id": id, "name": name, "role": role]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/actors/nodes", body: body)
            CLIStyle.success("Actor node created.")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorNodeUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update an actor node.")

    @Argument(help: "Actor ID") var actorId: String
    @Option(name: .long, help: "New name") var name: String?
    @Option(name: .long, help: "New role") var role: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let role { payload["role"] = role }
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.put("/v1/actors/nodes/\(actorId)", body: body)
            CLIStyle.success("Actor node updated.")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorNodeDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an actor node.")

    @Argument(help: "Actor ID") var actorId: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            _ = try await client.delete("/v1/actors/nodes/\(actorId)")
            CLIStyle.success("Actor node \(CLIStyle.whiteBold(actorId)) deleted.")
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorLinkCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "link",
        abstract: "Manage actor links.",
        subcommands: [ActorLinkCreateCommand.self, ActorLinkDeleteCommand.self]
    )
}

struct ActorLinkCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an actor link.")

    @Option(name: .long, help: "Source actor ID") var from: String
    @Option(name: .long, help: "Target actor ID") var to: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let payload: [String: Any] = ["from": from, "to": to]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/actors/links", body: body)
            CLIStyle.success("Link created.")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorLinkDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an actor link.")

    @Argument(help: "Link ID") var linkId: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            _ = try await client.delete("/v1/actors/links/\(linkId)")
            CLIStyle.success("Link \(CLIStyle.whiteBold(linkId)) deleted.")
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorTeamCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "team",
        abstract: "Manage actor teams.",
        subcommands: [ActorTeamCreateCommand.self, ActorTeamUpdateCommand.self, ActorTeamDeleteCommand.self]
    )
}

struct ActorTeamCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an actor team.")

    @Option(name: .long, help: "Team name") var name: String
    @Option(name: .long, help: "Comma-separated member actor IDs") var members: String = ""
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let memberList = members.split(separator: ",").map(String.init)
        let payload: [String: Any] = ["name": name, "members": memberList]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/actors/teams", body: body)
            CLIStyle.success("Team created.")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorTeamUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update an actor team.")

    @Argument(help: "Team ID") var teamId: String
    @Option(name: .long, help: "New name") var name: String?
    @Option(name: .long, help: "Comma-separated member actor IDs") var members: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let members { payload["members"] = members.split(separator: ",").map(String.init) }
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.put("/v1/actors/teams/\(teamId)", body: body)
            CLIStyle.success("Team updated.")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorTeamDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an actor team.")

    @Argument(help: "Team ID") var teamId: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            _ = try await client.delete("/v1/actors/teams/\(teamId)")
            CLIStyle.success("Team \(CLIStyle.whiteBold(teamId)) deleted.")
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ActorRouteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "route", abstract: "Route a message through the actor graph.")

    @Option(name: .long, help: "Message to route") var message: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let payload: [String: Any] = ["message": message]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/actors/route", body: body)
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}
