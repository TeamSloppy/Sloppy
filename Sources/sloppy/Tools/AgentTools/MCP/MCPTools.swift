import AnyLanguageModel
import Foundation
import Metrics
import Protocols

struct MCPListServersTool: CoreTool {
    let domain = "mcp"
    let title = "List MCP servers"
    let status = "fully_functional"
    let name = "mcp.list_servers"
    let description = "List configured MCP servers and their exposed capabilities."

    var parameters: GenerationSchema { .objectSchema([]) }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let servers = await context.mcpRegistry.listServers()
        let payload = servers.map { server in
            JSONValue.object([
                "id": .string(server.id),
                "transport": .string(server.transport),
                "enabled": .bool(server.enabled),
                "exposeTools": .bool(server.exposeTools),
                "exposeResources": .bool(server.exposeResources),
                "exposePrompts": .bool(server.exposePrompts),
                "toolPrefix": server.toolPrefix.map(JSONValue.string) ?? .null
            ])
        }
        return toolSuccess(tool: name, data: .array(payload))
    }
}

struct MCPListToolsTool: CoreTool {
    let domain = "mcp"
    let title = "List MCP tools"
    let status = "fully_functional"
    let name = "mcp.list_tools"
    let description = "List tools exposed by a configured MCP server."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "Configured MCP server id", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "cursor", description: "Optional pagination cursor", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let serverID = arguments["server"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'server' is required.", retryable: false)
        }

        do {
            let result = try await context.mcpRegistry.listTools(
                serverID: serverID,
                cursor: arguments["cursor"]?.asString
            )
            return toolSuccess(
                tool: name,
                data: .object([
                    "server": .string(serverID),
                    "tools": .array(result.tools.map(MCPClientRegistry.jsonValue(from:))),
                    "nextCursor": result.nextCursor.map(JSONValue.string) ?? .null
                ])
            )
        } catch {
            return toolFailure(tool: name, code: "mcp_error", message: String(describing: error), retryable: true)
        }
    }
}

struct MCPCallToolTool: CoreTool {
    let domain = "mcp"
    let title = "Call MCP tool"
    let status = "fully_functional"
    let name = "mcp.call_tool"
    let description = "Call any tool exposed by a configured MCP server."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "Configured MCP server id", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "tool", description: "MCP tool name", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "arguments", description: "Tool arguments object", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let serverID = arguments["server"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'server' is required.", retryable: false)
        }
        guard let toolName = arguments["tool"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toolName.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'tool' is required.", retryable: false)
        }

        let toolArguments: [String: JSONValue]
        if let object = arguments["arguments"]?.asObject {
            toolArguments = object
        } else if let encoded = arguments["arguments"]?.asString {
            guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: Data(encoded.utf8)) else {
                return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'arguments' must encode a JSON object.", retryable: false)
            }
            toolArguments = object
        } else {
            toolArguments = [:]
        }

        // Discovery never grants access. Re-resolve the target against this invocation's
        // session registry and policy, including delegated scope, before calling the server.
        guard let target = await context.mcpRegistry.dynamicTools().first(where: {
            $0.serverID == serverID && $0.toolName == toolName
        }) else {
            let complete = await context.mcpRegistry.dynamicDiscoveryIsComplete()
            Counter(label: "sloppy.tool.discovery.mcp_calls", dimensions: [("outcome", complete ? "unknown_target" : "discovery_incomplete")]).increment()
            return toolFailure(tool: name, code: complete ? "unknown_tool" : "mcp_discovery_incomplete",
                message: complete ? "The MCP tool is not exposed by this session's catalog." : "The MCP catalog could not be fully loaded; retry discovery before calling this tool.",
                retryable: !complete)
        }
        let entry = ToolDiscoveryEntry(id: target.id, title: target.title, description: target.description,
            parameterNames: [], mcp: target)
        guard ToolDiscoveryService.isVisible(entry, policy: context.policy, allowedIDs: context.discoveryAllowedToolIDs) else {
            Counter(label: "sloppy.tool.discovery.mcp_calls", dimensions: [("outcome", "forbidden")]).increment()
            return toolFailure(tool: name, code: "tool_forbidden", message: "The MCP tool is outside the permitted tool scope.", retryable: false)
        }

        do {
            let result = try await context.mcpRegistry.callTool(
                serverID: serverID,
                name: toolName,
                arguments: toolArguments
            )
            Counter(label: "sloppy.tool.discovery.mcp_calls", dimensions: [("outcome", result.isError == true ? "server_error" : "success")]).increment()
            var data: [String: JSONValue] = [
                "server": .string(serverID),
                "tool": .string(toolName),
                "isError": result.isError.map(JSONValue.bool) ?? .null,
                "content": .array(result.content.map(MCPClientRegistry.jsonValue(from:)))
            ]
            if result.isError != true {
                let traits = await context.mcpRegistry.toolTraits(serverID: serverID, tool: toolName)
                if let kind = traits.verificationKind { data["verificationKind"] = .string(kind) }
                if let readOnly = traits.readOnly { data["readOnly"] = .bool(readOnly) }
            }
            return toolSuccess(tool: name, data: .object(data))
        } catch {
            Counter(label: "sloppy.tool.discovery.mcp_calls", dimensions: [("outcome", "transport_error")]).increment()
            return toolFailure(tool: name, code: "mcp_error", message: String(describing: error), retryable: true)
        }
    }
}

struct MCPListResourcesTool: CoreTool {
    let domain = "mcp"
    let title = "List MCP resources"
    let status = "fully_functional"
    let name = "mcp.list_resources"
    let description = "List resources exposed by a configured MCP server."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "Configured MCP server id", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "cursor", description: "Optional pagination cursor", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let serverID = arguments["server"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'server' is required.", retryable: false)
        }

        do {
            let result = try await context.mcpRegistry.listResources(
                serverID: serverID,
                cursor: arguments["cursor"]?.asString
            )
            return toolSuccess(
                tool: name,
                data: .object([
                    "server": .string(serverID),
                    "resources": .array(result.resources.map(MCPClientRegistry.jsonValue(from:))),
                    "nextCursor": result.nextCursor.map(JSONValue.string) ?? .null
                ])
            )
        } catch {
            return toolFailure(tool: name, code: "mcp_error", message: String(describing: error), retryable: true)
        }
    }
}

struct MCPReadResourceTool: CoreTool {
    let domain = "mcp"
    let title = "Read MCP resource"
    let status = "fully_functional"
    let name = "mcp.read_resource"
    let description = "Read a resource by URI from a configured MCP server."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "Configured MCP server id", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "uri", description: "Resource URI", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let serverID = arguments["server"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'server' is required.", retryable: false)
        }
        guard let uri = arguments["uri"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !uri.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'uri' is required.", retryable: false)
        }

        do {
            let contents = try await context.mcpRegistry.readResource(serverID: serverID, uri: uri)
            return toolSuccess(
                tool: name,
                data: .object([
                    "server": .string(serverID),
                    "uri": .string(uri),
                    "contents": .array(contents.map(MCPClientRegistry.jsonValue(from:)))
                ])
            )
        } catch {
            return toolFailure(tool: name, code: "mcp_error", message: String(describing: error), retryable: true)
        }
    }
}

struct MCPListPromptsTool: CoreTool {
    let domain = "mcp"
    let title = "List MCP prompts"
    let status = "fully_functional"
    let name = "mcp.list_prompts"
    let description = "List prompts exposed by a configured MCP server."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "Configured MCP server id", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "cursor", description: "Optional pagination cursor", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let serverID = arguments["server"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'server' is required.", retryable: false)
        }

        do {
            let result = try await context.mcpRegistry.listPrompts(
                serverID: serverID,
                cursor: arguments["cursor"]?.asString
            )
            return toolSuccess(
                tool: name,
                data: .object([
                    "server": .string(serverID),
                    "prompts": .array(result.prompts.map(MCPClientRegistry.jsonValue(from:))),
                    "nextCursor": result.nextCursor.map(JSONValue.string) ?? .null
                ])
            )
        } catch {
            return toolFailure(tool: name, code: "mcp_error", message: String(describing: error), retryable: true)
        }
    }
}

struct MCPGetPromptTool: CoreTool {
    let domain = "mcp"
    let title = "Get MCP prompt"
    let status = "fully_functional"
    let name = "mcp.get_prompt"
    let description = "Get a prompt template and resolved messages from a configured MCP server."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "Configured MCP server id", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "name", description: "Prompt name", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "arguments", description: "Prompt arguments object", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let serverID = arguments["server"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'server' is required.", retryable: false)
        }
        guard let promptName = arguments["name"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !promptName.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'name' is required.", retryable: false)
        }

        do {
            let result = try await context.mcpRegistry.getPrompt(
                serverID: serverID,
                name: promptName,
                arguments: arguments["arguments"]?.asObject ?? [:]
            )
            return toolSuccess(
                tool: name,
                data: .object([
                    "server": .string(serverID),
                    "name": .string(promptName),
                    "description": result.description.map(JSONValue.string) ?? .null,
                    "messages": .array(result.messages.map(MCPClientRegistry.jsonValue(from:)))
                ])
            )
        } catch {
            return toolFailure(tool: name, code: "mcp_error", message: String(describing: error), retryable: true)
        }
    }
}
