import AnyLanguageModel
import Foundation
import Protocols

struct MCPListSkillsTool: CoreTool {
    let domain = "mcp"
    let title = "List MCP skills"
    let status = "fully_functional"
    let name = "mcp.list_skills"
    let description = "List skill names, descriptions, and entry URIs from a configured MCP server."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "MCP server ID", schema: .init(type: String.self)),
            .init(name: "cursor", description: "Optional pagination cursor", schema: .init(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let server = arguments["server"]?.asString, !server.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "A server ID is required.", retryable: false)
        }
        do {
            let result = try await context.mcpRegistry.remoteSkills(serverID: server, cursor: arguments["cursor"]?.asString)
            return toolSuccess(tool: name, data: .object(result))
        } catch {
            return toolFailure(tool: name, code: "mcp_skills_failed", message: error.localizedDescription, retryable: false)
        }
    }
}

struct MCPReadSkillTool: CoreTool {
    let domain = "mcp"
    let title = "Read MCP skill"
    let status = "fully_functional"
    let name = "mcp.read_skill"
    let description = "Activate a remote MCP skill after user approval, or read a file in an activated skill's verified manifest."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "MCP server ID", schema: .init(type: String.self)),
            .init(name: "uri", description: "Skill entry URI", schema: .init(type: String.self)),
            .init(name: "fileUri", description: "Optional supporting file URI", schema: .init(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard context.channelID == nil, let sessions = context.sessionService,
              let server = arguments["server"]?.asString, let uri = arguments["uri"]?.asString else {
            return toolFailure(tool: name, code: "mcp_skill_requires_chat", message: "An interactive chat, server ID, and skill URI are required.", retryable: false)
        }
        do {
            let result = try await sessions.useMCPSkill(agentID: context.agentID, sessionID: context.sessionID,
                serverID: server, uri: uri, fileURI: arguments["fileUri"]?.asString, registry: context.mcpRegistry)
            return toolSuccess(tool: name, data: result)
        } catch {
            return toolFailure(tool: name, code: "mcp_skill_failed", message: error.localizedDescription, retryable: false)
        }
    }
}

struct MCPCancelTaskTool: CoreTool {
    let domain = "mcp"
    let title = "Cancel MCP task"
    let status = "fully_functional"
    let name = "mcp.cancel_task"
    let description = "Request cooperative cancellation of an MCP task owned by this session."

    var parameters: GenerationSchema {
        .objectSchema([.init(name: "taskId", description: "Local MCP task ID", schema: .init(type: String.self))])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let id = arguments["taskId"]?.asString, let session = context.sessionService else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "A task ID from the current session is required.", retryable: false)
        }
        do {
            try await session.cancelMCPTask(agentID: context.agentID, sessionID: context.sessionID, id: id)
            return toolSuccess(tool: name, data: .object(["taskId": .string(id), "cancellationRequested": .bool(true)]))
        } catch {
            return toolFailure(tool: name, code: "mcp_task_cancel_failed", message: error.localizedDescription, retryable: false)
        }
    }
}
