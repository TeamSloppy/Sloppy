import Foundation

/// Named tool-policy presets. A preset only flips explicit per-tool entries in an agent's policy, so everything
/// it changes stays visible and editable in the agent's tool policy.
enum AgentToolPreset: String, CaseIterable, Sendable {
    /// Coding focus: drops groups that coding turns rarely need (browser automation, desktop control, sites,
    /// canvas workspaces, image generation, long chat, actors, scheduling and project/MCP administration).
    /// Their schemas are no longer sent to the model, which frees thousands of tokens on every round.
    case coding
    /// Removes the explicit denials a preset added, restoring the default (allow) behavior.
    case full

    static let codingDeniedPrefixes = [
        "browser.", "safari.", "computer.", "sites.", "workspace.", "workspaces.", "artifacts.",
        "images.", "long_chat.", "actor.", "heartbeat.", "code_review.", "visor.", "channel.",
        "agent.documents.",
    ]

    static let codingDeniedExact: Set<String> = [
        "cron", "session.launch.configure", "memory.import",
        "mcp.install_server", "mcp.save_server", "mcp.remove_server", "mcp.uninstall_server",
        "project.create", "project.delete", "project.update", "project.channel_link",
    ]

    static func codingDeniedToolIDs(knownToolIDs: Set<String>) -> Set<String> {
        knownToolIDs.filter { id in
            codingDeniedExact.contains(id) || codingDeniedPrefixes.contains { id.hasPrefix($0) }
        }
    }

    /// Returns the per-tool policy entries after applying the preset. Entries unrelated to the preset are kept.
    func apply(to tools: [String: Bool], knownToolIDs: Set<String>) -> [String: Bool] {
        let managed = Self.codingDeniedToolIDs(knownToolIDs: knownToolIDs)
        var result = tools
        switch self {
        case .coding:
            for id in managed { result[id] = false }
        case .full:
            for id in managed where result[id] == false { result.removeValue(forKey: id) }
        }
        return result
    }
}
