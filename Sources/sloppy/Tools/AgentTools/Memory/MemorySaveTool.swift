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
    Persist a hybrid memory entry. Pass memory_id from memory.search to correct an existing entry in the same scope instead of adding a duplicate. You must set scope (not the end user): either pass `scope_type` and `scope_id` together, or pass a `scope` object with `type` and `id`. \
    Only for facts intentionally restricted to this chat: `scope_type` = channel, `scope_id` = agent:<agentId>:session:<sessionId>. \
    Prefer agent scope for knowledge reusable across sessions: `scope_type` = agent, `scope_id` = <agentId>. For project knowledge use scope_type = project and scope_id = the current project ID. For shared rows visible to every enabled agent: `scope_type` = global, `scope_id` = shared. Calls without a resolved scope are rejected.
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
                description: "Together with scope_type, or omit if using `scope` object. For channel: agent:<agentId>:session:<sessionId>. For shared memory: shared.",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
            .init(name: "memory_id", description: "Optional existing record ID to update in the specified scope. Updates note, summary, kind, importance, and confidence; retains class and provenance.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "summary", description: "Optional summary", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "kind", description: "One of identity, preference, decision, fact, observation, goal, todo, event.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "importance", description: "Importance from 0 to 1; prioritize recurring corrections and stable preferences.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "confidence", description: "Confidence from 0 to 1 based on evidence.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "source_type", description: "Evidence source type, such as memory_checkpoint.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "source_id", description: "Evidence source identifier, such as the session ID.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
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
        if let failure = rejectDisabledSharedMemory(scope: scope, context: context, tool: name) {
            return failure
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

        if let memoryID = arguments["memory_id"]?.asString {
            let entries = await context.memoryStore.entries(filter: MemoryEntryFilter(scope: scope))
            guard entries.contains(where: { $0.id == memoryID }) else {
                return toolFailure(tool: name, code: "memory_not_found", message: "No active memory with this ID exists in the specified scope.", retryable: false)
            }
            guard let updated = await context.memoryStore.updateEntry(
                id: memoryID, note: note, summary: summary ?? note,
                kind: kind, importance: importance, confidence: confidence
            ) else {
                return toolFailure(tool: name, code: "memory_update_failed", message: "Could not update the memory entry.", retryable: true)
            }
            return toolSuccess(tool: name, data: .object([
                "id": .string(updated.id),
                "updated": .bool(true),
                "kind": .string(updated.kind.rawValue),
                "class": .string(updated.memoryClass.rawValue)
            ]))
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
