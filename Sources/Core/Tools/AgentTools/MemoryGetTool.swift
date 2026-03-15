import AnyLanguageModel
import AgentRuntime
import Foundation
import Protocols

/// Handles both `memory.get` and `memory.recall` tool IDs.
struct MemoryGetTool: CoreTool {
    let domain = "memory"
    let title = "Memory recall"
    let status = "fully_functional"
    let name = "memory.recall"
    let description = "Recall scoped memory using hybrid retrieval."

    var toolAliases: [String] { ["memory.get"] }

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "query", description: "Recall query", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "limit", description: "Max results to return", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let query = arguments["query"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`query` is required.", retryable: false)
        }

        let limit = max(1, arguments["limit"]?.asInt ?? 8)
        let scope = parseMemoryScope(from: arguments)
        let hits = await context.memoryStore.recall(
            request: MemoryRecallRequest(query: query, limit: limit, scope: scope)
        )

        let payload: [JSONValue] = hits.map { hit in
            .object([
                "id": .string(hit.ref.id),
                "score": .number(hit.ref.score),
                "note": .string(hit.note),
                "summary": hit.summary.map(JSONValue.string) ?? .null,
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
