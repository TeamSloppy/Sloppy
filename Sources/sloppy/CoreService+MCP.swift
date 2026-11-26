import Foundation
import Protocols

// MARK: - MCP

extension CoreService {
    func listMCPSkills(serverID: String, cursor: String?) async throws -> [String: JSONValue] {
        try await mcpRegistry.remoteSkills(serverID: serverID, cursor: cursor)
    }

    func listMCPServerStatuses() async -> [MCPServerStatus] {
        await mcpRegistry.serverStatuses()
    }
}
