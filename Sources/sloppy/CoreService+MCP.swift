import Foundation

// MARK: - MCP

extension CoreService {
    func listMCPServerStatuses() async -> [MCPServerStatus] {
        await mcpRegistry.serverStatuses()
    }
}
