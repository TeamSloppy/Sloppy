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
    Persist a hybrid memory entry. Pass memory_id from memory.search to correct an existing entry in the same scope instead of adding a duplicate. You must choose a scope (not the end user) by passing `scope_type`; `scope_id` is filled in for you and only needs to be given to target a different id. \
    Prefer `scope_type` = agent for knowledge reusable across sessions. Use `project` for knowledge about the current project, `channel` only for facts intentionally restricted to this chat, and `global` only for rows meant to be visible to every enabled agent. Calls without a scope_type are rejected.
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
            .init(name: "memory_id", description: "Only for updating: use an existing record ID returned by memory.search or memory.recall in the same scope. Omit or pass null for a new record; empty strings also mean create. A nonempty unknown ID is an error, never an implicit create.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
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
            return toolFailure(tool: name, code: "invalid_arguments", message: "`note` is required.", retryable: false,
                               hint: "Provide non-empty memory content in note.",
                               argumentRecovery: .init(invalidFields: ["note", "content"]))
        }

        let summary = arguments["summary"]?.asString
        let kind = arguments["kind"]?.asString.flatMap { MemoryKind(rawValue: $0.lowercased()) }
        let memoryClass = arguments["class"]?.asString.flatMap { MemoryClass(rawValue: $0.lowercased()) }
            ?? arguments["memory_class"]?.asString.flatMap { MemoryClass(rawValue: $0.lowercased()) }
        guard let scope = completedMemoryScope(from: arguments, context: context) else {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "Set memory scope: either `scope_type` + `scope_id`, or `scope` as { \"type\", \"id\", optional \"channel_id\", \"project_id\", \"agent_id\" }. Example channel scope_id: agent:<agentId>:session:<sessionId>.",
                retryable: false,
                hint: memoryScopeHint(context: context),
                argumentRecovery: .init(invalidFields: ["scope_type", "scope_id", "scope"])
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

        let memoryID: String?
        switch arguments["memory_id"] {
        case nil, .null:
            memoryID = nil
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            memoryID = trimmed.isEmpty ? nil : trimmed
        default:
            return toolFailure(tool: name, code: "invalid_arguments", message: "memory_id must be a string or null.", retryable: false,
                               hint: "Omit memory_id for a new record. To update, provide an existing ID from scoped recall.",
                               argumentRecovery: .init(invalidFields: ["memory_id"], contextFields: ["scope_type", "scope_id", "scope"]))
        }

        if let memoryID {
            let entries = await context.memoryStore.entries(filter: MemoryEntryFilter(scope: scope))
            guard entries.contains(where: { $0.id == memoryID }) else {
                return toolFailure(tool: name, code: "memory_not_found", message: "No active memory with this ID exists in the specified scope.", retryable: false,
                                   hint: "For an update, find the correct ID with memory.search or memory.recall in this scope. Only if you intend to create a new record, omit memory_id. Changing note does not fix an unknown ID.",
                                   argumentRecovery: .init(invalidFields: ["memory_id"], contextFields: ["scope_type", "scope_id", "scope"]))
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
