import ACP
import ACPModel
import ArgumentParser
import Foundation
import Logging

struct ACPCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "acp",
        abstract: "Run Sloppy as an ACP provider.",
        subcommands: [
            ACPServeCommand.self,
        ]
    )
}

struct ACPServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Serve the selected Sloppy agent over ACP stdio."
    )

    @Option(name: [.short, .long], help: "Path to JSON config file")
    var configPath: String?

    @Option(name: .long, help: "Agent ID exposed through ACP. Overrides acp.server.agentId.")
    var agent: String?

    @Option(name: .long, help: "Default working directory for ACP sessions. Overrides acp.server.cwd.")
    var cwd: String?

    mutating func run() async throws {
        do {
            let service = try await EmbeddedCoreServiceFactory.make(
                configPath: configPath,
                loggerLabel: "sloppy.acp.server"
            )
            let config = await service.getConfig()
            guard config.acp.server.enabled else {
                CLIStyle.error("ACP server is disabled. Enable Settings > ACP > ACP Server first.")
                throw ExitCode.failure
            }

            let resolvedAgent = try Self.resolveAgentID(
                cliAgent: agent,
                configuredAgent: config.acp.server.agentId
            )
            let resolvedCwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? cwd
                : config.acp.server.cwd

            let stdioTransport = StdinTransport()
            let transport = ACPLoggingTransport(
                wrapping: stdioTransport,
                logger: Logger.sloppy(label: "sloppy.acp.server.stdio")
            )
            let acpAgent = ACP.Agent(transport: transport)
            let delegate = SloppyACPServerDelegate(
                service: service,
                agentID: resolvedAgent,
                defaultCwd: resolvedCwd,
                sendUpdate: { sessionID, update in
                    try await acpAgent.sendUpdate(sessionId: sessionID, update: update)
                }
            )
            await acpAgent.setDelegate(delegate)
            await stdioTransport.start()
            await acpAgent.start()
        } catch let exit as ExitCode {
            throw exit
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }

    private static func resolveAgentID(cliAgent: String?, configuredAgent: String?) throws -> String {
        let raw = cliAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? configuredAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard !raw.isEmpty else {
            CLIStyle.error("ACP server requires --agent or acp.server.agentId in config.")
            throw ExitCode.failure
        }
        return raw
    }
}
