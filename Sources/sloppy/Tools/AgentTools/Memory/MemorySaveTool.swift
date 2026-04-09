import AnyLanguageModel
import AgentRuntime
import Foundation
import Protocols

struct MemorySaveTool: CoreTool {
    let domain = "memory"
    let title = "Memory save"
    let status = "fully_functional"
    let name = "memory.save"
    let description = """
    Persist a hybrid memory entry. You must set scope (not the end user): either pass `scope_type` and `scope_id` together, or pass a `scope` object with `type` and `id`. \
    For this chat and the dashboard Memories list: `scope_type` = channel, `scope_id` = agent:<agentId>:session:<sessionId>. \
    For agent-wide rows: `scope_type` = agent, `scope_id` = <agentId>. Calls without a resolved scope are rejected.
    """

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "note", description: "Memory content to save", schema: DynamicGenerationSchema(type: String.self)),
            .init(
                name: "scope_type",
                description: "Together with scope_id, or omit if using `scope` object. One of: global, project, channel, agent.",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
            .init(
                name: "scope_id",
                description: "Together with scope_type, or omit if using `scope` object. For channel: agent:<agentId>:session:<sessionId>.",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
            .init(name: "summary", description: "Optional summary", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "class", description: "Memory class (e.g. semantic, episodic)", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let note = (arguments["note"]?.asString ?? arguments["content"]?.asString ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`note` is required.", retryable: false)
        }

        let summary = arguments["summary"]?.asString
        let kind = arguments["kind"]?.asString.flatMap { MemoryKind(rawValue: $0.lowercased()) }
        let memoryClass = arguments["class"]?.asString.flatMap { MemoryClass(rawValue: $0.lowercased()) }
            ?? arguments["memory_class"]?.asString.flatMap { MemoryClass(rawValue: $0.lowercased()) }
        guard let scope = parseMemoryScope(from: arguments) else {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "Set memory scope: either `scope_type` + `scope_id`, or `scope` as { \"type\", \"id\", optional \"channel_id\", \"project_id\", \"agent_id\" }. Example channel scope_id: agent:<agentId>:session:<sessionId>.",
                retryable: false
            )
        }
        let importance = arguments["importance"]?.asNumber
        let confidence = arguments["confidence"]?.asNumber

        let sourceType = arguments["source_type"]?.asString
        let sourceId = arguments["source_id"]?.asString
        let source = sourceType.map { MemorySource(type: $0, id: sourceId) }

        var metadata: [String: JSONValue] = [:]
        if let metadataObject = arguments["metadata"]?.asObject {
            metadata = metadataObject
        }

        let ref = await context.memoryStore.save(
            entry: MemoryWriteRequest(
                note: note,
                summary: summary,
                kind: kind,
                memoryClass: memoryClass,
                scope: scope,
                source: source,
                importance: importance,
                confidence: confidence,
                metadata: metadata
            )
        )

        return toolSuccess(tool: name, data: .object([
            "id": .string(ref.id),
            "score": .number(ref.score),
            "kind": .string(ref.kind?.rawValue ?? ""),
            "class": .string(ref.memoryClass?.rawValue ?? "")
        ]))
    }
}
