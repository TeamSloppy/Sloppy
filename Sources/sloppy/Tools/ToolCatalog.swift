import Foundation
import Protocols

enum ToolCatalog {
    /// Tool catalog entries auto-generated from the ToolRegistry.
    static let builtInEntries: [AgentToolCatalogEntry] = ToolRegistry.makeDefault().catalogEntries

    static func entries(mcpRegistry: MCPClientRegistry?) async -> [AgentToolCatalogEntry] {
        guard let mcpRegistry else {
            return builtInEntries
        }
        let dynamicEntries = await mcpRegistry.dynamicTools().map { tool in
            AgentToolCatalogEntry(
                id: tool.id,
                domain: "mcp",
                title: tool.title,
                status: "fully_functional",
                description: tool.description
            )
        }
        return (builtInEntries + dynamicEntries).sorted { $0.id < $1.id }
    }

    static func knownToolIDs(mcpRegistry: MCPClientRegistry?) async -> Set<String> {
        guard let mcpRegistry else {
            return knownToolIDs
        }
        return knownToolIDs.union(await mcpRegistry.dynamicToolIDs())
    }

    static func listToolsPayload(mcpRegistry: MCPClientRegistry?) async -> [JSONValue] {
        let catalogEntries = await entries(mcpRegistry: mcpRegistry)
        let dynamicTools = Dictionary(uniqueKeysWithValues: await (mcpRegistry?.dynamicTools() ?? []).map { ($0.id, $0) })

        return catalogEntries.map { entry in
            let parameters = dynamicTools[entry.id]?.inputSchema ?? parameterSchema(for: entry.id)
            return .object([
                "name": .string(entry.id),
                "title": .string(entry.title),
                "domain": .string(entry.domain),
                "status": .string(entry.status),
                "description": .string(entry.description),
                "parameters": parameters
            ])
        }
    }

    static let knownToolIDs: Set<String> = ToolRegistry.makeDefault().knownToolIDs

    private static func parameterSchema(for toolID: String) -> JSONValue {
        parameterSchemas[toolID] ?? .object(["type": .string("object")])
    }

    static let parameterSchemas: [String: JSONValue] = [
        "system.list_tools": .object(["type": .string("object")]),
        "files.read": .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")]),
                "maxBytes": .object(["type": .string("number")])
            ]),
            "required": .array([.string("path")])
        ]),
        "files.write": .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")]),
                "content": .object(["type": .string("string")]),
                "allowEmpty": .object(["type": .string("boolean")])
            ]),
            "required": .array([.string("path"), .string("content")])
        ]),
        "files.edit": .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")]),
                "search": .object(["type": .string("string")]),
                "replace": .object(["type": .string("string")]),
                "all": .object(["type": .string("boolean")])
            ]),
            "required": .array([.string("path"), .string("search"), .string("replace")])
        ]),
        "runtime.exec": .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object(["type": .string("string")]),
                "arguments": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "cwd": .object(["type": .string("string")]),
                "timeoutMs": .object(["type": .string("number")])
            ]),
            "required": .array([.string("command")])
        ]),
        "runtime.process": .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object(["type": .string("string")]),
                "command": .object(["type": .string("string")]),
                "arguments": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "cwd": .object(["type": .string("string")]),
                "processId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("action")])
        ]),
        "branches.spawn": .object([
            "type": .string("object"),
            "properties": .object([
                "prompt": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")])
            ]),
            "required": .array([.string("prompt")])
        ]),
        "workers.spawn": .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "objective": .object(["type": .string("string")]),
                "mode": .object([
                    "type": .string("string"),
                    "enum": .array([.string("fire_and_forget"), .string("interactive")])
                ]),
                "taskId": .object(["type": .string("string")]),
                "tools": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ])
            ]),
            "required": .array([.string("objective")])
        ]),
        "workers.route": .object([
            "type": .string("object"),
            "properties": .object([
                "workerId": .object(["type": .string("string")]),
                "command": .object([
                    "type": .string("string"),
                    "enum": .array([.string("continue"), .string("complete"), .string("fail")])
                ]),
                "summary": .object(["type": .string("string")]),
                "error": .object(["type": .string("string")]),
                "report": .object(["type": .string("string")])
            ]),
            "required": .array([.string("workerId"), .string("command")])
        ]),
        "sessions.spawn": .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "parentSessionId": .object(["type": .string("string")])
            ])
        ]),
        "sessions.list": .object(["type": .string("object")]),
        "sessions.history": .object([
            "type": .string("object"),
            "properties": .object([
                "sessionId": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ])
        ]),
        "sessions.status": .object([
            "type": .string("object"),
            "properties": .object([
                "sessionId": .object(["type": .string("string")])
            ])
        ]),
        "sessions.send": .object([
            "type": .string("object"),
            "properties": .object([
                "sessionId": .object(["type": .string("string")]),
                "content": .object(["type": .string("string")]),
                "userId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("content")])
        ]),
        "messages.send": .object([
            "type": .string("object"),
            "properties": .object([
                "sessionId": .object(["type": .string("string")]),
                "content": .object(["type": .string("string")]),
                "userId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("content")])
        ]),
        "agents.list": .object(["type": .string("object")]),
        "channel.history": .object([
            "type": .string("object"),
            "properties": .object([
                "channel_id": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ]),
            "required": .array([.string("channel_id")])
        ]),
        "memory.get": .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ]),
            "required": .array([.string("query")])
        ]),
        "memory.recall": .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ]),
            "required": .array([.string("query")])
        ]),
        "memory.search": .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ]),
            "required": .array([.string("query")])
        ]),
        "memory.save": .object([
            "type": .string("object"),
            "properties": .object([
                "note": .object(["type": .string("string")]),
                "summary": .object(["type": .string("string")]),
                "class": .object(["type": .string("string")])
            ]),
            "required": .array([.string("note")])
        ]),
        "mcp.list_servers": .object(["type": .string("object")]),
        "mcp.list_tools": .object([
            "type": .string("object"),
            "properties": .object([
                "server": .object(["type": .string("string")]),
                "cursor": .object(["type": .string("string")])
            ]),
            "required": .array([.string("server")])
        ]),
        "mcp.call_tool": .object([
            "type": .string("object"),
            "properties": .object([
                "server": .object(["type": .string("string")]),
                "tool": .object(["type": .string("string")]),
                "arguments": .object(["type": .string("object")])
            ]),
            "required": .array([.string("server"), .string("tool")])
        ]),
        "mcp.list_resources": .object([
            "type": .string("object"),
            "properties": .object([
                "server": .object(["type": .string("string")]),
                "cursor": .object(["type": .string("string")])
            ]),
            "required": .array([.string("server")])
        ]),
        "mcp.read_resource": .object([
            "type": .string("object"),
            "properties": .object([
                "server": .object(["type": .string("string")]),
                "uri": .object(["type": .string("string")])
            ]),
            "required": .array([.string("server"), .string("uri")])
        ]),
        "mcp.list_prompts": .object([
            "type": .string("object"),
            "properties": .object([
                "server": .object(["type": .string("string")]),
                "cursor": .object(["type": .string("string")])
            ]),
            "required": .array([.string("server")])
        ]),
        "mcp.get_prompt": .object([
            "type": .string("object"),
            "properties": .object([
                "server": .object(["type": .string("string")]),
                "name": .object(["type": .string("string")]),
                "arguments": .object(["type": .string("object")])
            ]),
            "required": .array([.string("server"), .string("name")])
        ]),
        "web.search": .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "count": .object(["type": .string("number")])
            ]),
            "required": .array([.string("query")])
        ]),
        "web.fetch": .object([
            "type": .string("object"),
            "properties": .object([
                "url": .object(["type": .string("string")])
            ]),
            "required": .array([.string("url")])
        ]),
        "cron": .object([
            "type": .string("object"),
            "properties": .object([
                "schedule": .object(["type": .string("string")]),
                "command": .object(["type": .string("string")]),
                "channel_id": .object(["type": .string("string")]),
                "action": .object(["type": .string("string")])
            ])
        ]),
        "project.task_list": .object(["type": .string("object")]),
        "project.task_create": .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "description": .object(["type": .string("string")]),
                "priority": .object(["type": .string("string")]),
                "status": .object(["type": .string("string")]),
                "actorId": .object(["type": .string("string")]),
                "teamId": .object(["type": .string("string")]),
                "channelId": .object(["type": .string("string")]),
                "topicId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("title")])
        ]),
        "project.task_get": .object([
            "type": .string("object"),
            "properties": .object([
                "taskId": .object(["type": .string("string")]),
                "reference": .object(["type": .string("string")]),
                "channelId": .object(["type": .string("string")])
            ])
        ]),
        "project.task_update": .object([
            "type": .string("object"),
            "properties": .object([
                "taskId": .object(["type": .string("string")]),
                "reference": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")]),
                "description": .object(["type": .string("string")]),
                "priority": .object(["type": .string("string")]),
                "status": .object(["type": .string("string")]),
                "actorId": .object(["type": .string("string")]),
                "teamId": .object(["type": .string("string")]),
                "channelId": .object(["type": .string("string")]),
                "topicId": .object(["type": .string("string")])
            ])
        ]),
        "project.task_cancel": .object([
            "type": .string("object"),
            "properties": .object([
                "taskId": .object(["type": .string("string")]),
                "reference": .object(["type": .string("string")]),
                "reason": .object(["type": .string("string")]),
                "channelId": .object(["type": .string("string")]),
                "topicId": .object(["type": .string("string")])
            ])
        ]),
        "project.escalate_to_user": .object([
            "type": .string("object"),
            "properties": .object([
                "reason": .object(["type": .string("string")]),
                "taskId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("reason")])
        ]),
        "actor.discuss_with_actor": .object([
            "type": .string("object"),
            "properties": .object([
                "actorId": .object(["type": .string("string")]),
                "topic": .object(["type": .string("string")]),
                "message": .object(["type": .string("string")])
            ]),
            "required": .array([.string("actorId")])
        ]),
        "actor.conclude_discussion": .object([
            "type": .string("object"),
            "properties": .object([
                "discussionId": .object(["type": .string("string")]),
                "summary": .object(["type": .string("string")])
            ]),
            "required": .array([.string("discussionId")])
        ])
    ]
}
