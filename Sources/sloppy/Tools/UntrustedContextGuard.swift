import Foundation
import Protocols

/// Typed taint tracking for prompt-injection defense.
///
/// A session becomes tainted once a tool that returns attacker-controllable content (web pages, browser
/// pages, MCP servers, channel history) has produced a result in it. The decision is derived only from
/// persisted tool-result events, never from the text of model or tool output.
enum UntrustedContextGuard {
    private static let untrustedOutputTools: Set<String> = [
        "channel.history",
    ]

    private static let untrustedOutputPrefixes = ["web.", "browser.", "safari.", "mcp."]

    /// Whether the output of `toolID` may carry attacker-controlled instructions.
    /// Tools unknown to the built-in catalog are dynamic MCP tools and are untrusted by construction.
    static func producesUntrustedOutput(
        toolID rawToolID: String,
        builtInToolIDs: Set<String> = ToolCatalog.knownToolIDs
    ) -> Bool {
        let toolID = rawToolID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !toolID.isEmpty else { return false }
        if untrustedOutputTools.contains(toolID) {
            return true
        }
        if untrustedOutputPrefixes.contains(where: { toolID.hasPrefix($0) }) {
            return true
        }
        return !builtInToolIDs.contains(toolID)
    }

    /// Whether any tool result already recorded in the session came from an untrusted-output tool.
    static func isTainted(
        events: [AgentSessionEvent],
        builtInToolIDs: Set<String> = ToolCatalog.knownToolIDs
    ) -> Bool {
        events.contains { event in
            guard event.type == .toolResult, let result = event.toolResult else {
                return false
            }
            return producesUntrustedOutput(toolID: result.tool, builtInToolIDs: builtInToolIDs)
        }
    }

    /// Whether a risky call in a tainted session must be approved by a human for this invocation only.
    static func requiresPerInvocationApproval(
        sessionEvents: [AgentSessionEvent],
        settings: AgentToolApprovalSettings,
        callRequiresHumanApproval: Bool
    ) -> Bool {
        guard settings.untrustedContextGuard == .requireApproval, callRequiresHumanApproval else {
            return false
        }
        return isTainted(events: sessionEvents)
    }
}
