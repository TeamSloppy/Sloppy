import Foundation
import Protocols

struct MCPToolInteraction: Sendable {
    static let tasksID = "io.modelcontextprotocol/tasks"

    let capabilities: [String: JSONValue]
    let progressToken: String
    let notification: @Sendable ([String: JSONValue]) -> Void
    let answer: @Sendable ([String: JSONValue]) async throws -> [String: JSONValue]
    let registerTask: @Sendable ([String: JSONValue], CoreConfig.MCP.Server) async throws -> MCPToolReply
}
