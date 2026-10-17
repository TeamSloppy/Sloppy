import AnyLanguageModel
import AgentRuntime
import Foundation
import Protocols

struct MemorySearchTool: CoreTool {
    let domain = "memory"
    let title = "Memory file search"
    let status = "fully_functional"
    let name = "memory.search"
    let description = "Search memory. Without a scope it searches this agent, the current project and this conversation (plus shared memory when enabled). Pass `scope_type` (agent, project, channel or global) only to narrow the search; `scope_id` is filled in automatically."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "query", description: "Search query", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "limit", description: "Max results to return", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
            .init(
                name: "scope_type",
                description: "Together with scope_id, or omit if using `scope` object. One of: global, project, channel, agent.",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
            .init(
                name: "scope_id",
                description: "Together with scope_type, or omit if using `scope` object. For channel: agent:<agentId>:session:<sessionId>. For shared memory: shared.",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
            .init(
                name: "scope",
                description: "Optional object with `type` and `id`, plus optional channel_id, project_id, or agent_id.",
                schema: DynamicGenerationSchema(
                    name: "MemoryScopeArgument",
                    properties: [
                        .init(name: "type", description: "One of: global, project, channel, agent.", schema: DynamicGenerationSchema(type: String.self)),
                        .init(name: "id", description: "Scope identifier.", schema: DynamicGenerationSchema(type: String.self)),
                        .init(name: "channel_id", description: "Optional channel id.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
                        .init(name: "project_id", description: "Optional project id.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
                        .init(name: "agent_id", description: "Optional agent id.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
                    ]
                ),
                isOptional: true
            )
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let query = arguments["query"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`query` is required.", retryable: false)
        }

        let limit = max(1, arguments["limit"]?.asInt ?? 8)
        let scope = completedMemoryScope(from: arguments, context: context)
        if let failure = rejectDisabledSharedMemory(scope: scope, context: context, tool: name) {
            return failure
        }
        let channelId = sessionMemoryChannelID(context: context)
        var hits: [MemoryHit] = []
        // An unscoped search must not read the whole store, which holds other agents' and projects' memory.
        for searched in scope.map({ [$0] }) ?? visibleMemoryScopes(context: context) {
            hits += await context.memoryStore.recallDiagnosed(
                request: MemoryRecallRequest(query: query, limit: limit, scope: searched),
                channelId: channelId, source: .toolSearch, diagnostics: context.runtime.memoryDiagnostics
            )
        }
        if scope == nil {
            var seen = Set<String>()
            hits = hits
                .sorted { $0.ref.score != $1.ref.score ? $0.ref.score > $1.ref.score : $0.ref.id < $1.ref.id }
                .filter { seen.insert($0.ref.id).inserted }
            hits = Array(hits.prefix(limit))
        }

        let payload: [JSONValue] = hits.map { hit in
            .object([
                "memory_id": .string(hit.ref.id),
                "topic": hit.topic.map(JSONValue.string) ?? .null,
                "score": .number(hit.ref.score),
                "note": .string(hit.note),
                "summary": hit.summary.map(JSONValue.string) ?? .null,
                "source": hit.ref.source.map { .object(["type": .string($0.type), "id": $0.id.map(JSONValue.string) ?? .null]) } ?? .null,
                "kind": .string(hit.ref.kind?.rawValue ?? ""),
                "class": .string(hit.ref.memoryClass?.rawValue ?? "")
            ])
        }

        return toolSuccess(tool: name, data: .object([
            "query": .string(query),
            "count": .number(Double(payload.count)),
            "items": .array(payload)
        ]))
    }
}
