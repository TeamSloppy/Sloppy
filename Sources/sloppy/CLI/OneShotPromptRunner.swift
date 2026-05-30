import Foundation
import Protocols

struct OneShotPromptOptions: Sendable {
    var prompt: String
    var agentID: String?
    var sessionID: String?
    var configPath: String?
    var cwd: String?
    var mode: String?
}

enum OneShotPromptRunner {
    static func run(_ options: OneShotPromptOptions) async throws -> String {
        let service = try await EmbeddedCoreServiceFactory.make(
            configPath: options.configPath,
            loggerLabel: "sloppy.cli.prompt"
        )
        let agentID = try await resolveAgentID(options.agentID, service: service)
        let session: AgentSessionSummary
        if let rawSession = options.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSession.isEmpty {
            session = try await service.getAgentSession(agentID: agentID, sessionID: rawSession).summary
        } else {
            session = try await service.createAgentSession(
                agentID: agentID,
                request: AgentSessionCreateRequest(title: "CLI prompt")
            )
        }

        if let cwd = options.cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
            _ = try await service.addAgentSessionDirectory(
                agentID: agentID,
                sessionID: session.id,
                request: AgentSessionDirectoryRequest(path: cwd)
            )
        }

        let response = try await service.postAgentSessionMessage(
            agentID: agentID,
            sessionID: session.id,
            request: AgentSessionPostMessageRequest(
                userId: "cli",
                content: options.prompt,
                mode: resolvedMode(options.mode)
            )
        )

        return assistantText(from: response.appendedEvents)
    }

    private static func resolveAgentID(_ requested: String?, service: CoreService) async throws -> String {
        if let requested = requested?.trimmingCharacters(in: .whitespacesAndNewlines), !requested.isEmpty {
            _ = try await service.getAgent(id: requested)
            return requested
        }

        let agents = try await service.listAgents(includeSystem: false)
        guard agents.count == 1, let agent = agents.first else {
            throw CLIError("Use --agent when the workspace has zero or multiple user agents.")
        }
        return agent.id
    }

    private static func resolvedMode(_ raw: String?) -> AgentChatMode? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return .defaultMode
        }
        return AgentChatMode(rawValue: value) ?? .defaultMode
    }

    private static func assistantText(from events: [AgentSessionEvent]) -> String {
        events.compactMap { event -> String? in
            guard event.type == .message,
                  event.message?.role == .assistant,
                  let message = event.message
            else { return nil }
            return message.segments.compactMap(\.text).joined(separator: "\n")
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CLIError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
