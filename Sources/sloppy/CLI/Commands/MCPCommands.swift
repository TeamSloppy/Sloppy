import ArgumentParser
import Foundation

struct MCPCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Manage MCP servers and tools.",
        subcommands: [MCPServerListCommand.self, MCPToolListCommand.self, MCPCallCommand.self]
    )
}

struct MCPServerListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "server", abstract: "List configured MCP servers.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/config")
            if let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let mcp = cfg["mcp"],
               let mcpData = try? JSONSerialization.data(withJSONObject: mcp, options: .prettyPrinted),
               let str = String(data: mcpData, encoding: .utf8) {
                print(str)
            } else {
                CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
            }
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct MCPToolListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tool", abstract: "List tools for an agent (from tool catalog).")

    @Argument(help: "Agent ID") var agentId: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/agents/\(agentId)/tools/catalog")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct MCPCallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "call", abstract: "Call an MCP tool via agent.")

    @Argument(help: "Agent ID") var agentId: String
    @Argument(help: "Tool name") var toolName: String
    @Option(name: .long, help: "JSON arguments string") var args: String = "{}"
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        guard let argsData = args.data(using: .utf8),
              let argsObj = try? JSONSerialization.jsonObject(with: argsData) else {
            CLIStyle.error("Invalid JSON for --args."); throw ExitCode.failure
        }
        let payload: [String: Any] = ["tool": toolName, "arguments": argsObj]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/agents/\(agentId)/tools/invoke", body: body)
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}
