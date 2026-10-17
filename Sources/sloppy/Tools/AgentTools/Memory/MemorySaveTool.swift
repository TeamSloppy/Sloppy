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
    Persist a hybrid memory entry. Give every fact that can change a short stable `topic` (for example "billing service deploy key id"): saving again with the same topic in the same scope REPLACES the earlier entry, so that is how to correct a fact, with no search or memory_id needed. You must choose a scope (not the end user) by passing `scope_type`; `scope_id` is filled in for you and only needs to be given to target a different id. \
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
            .init(name: "topic", description: "Short stable name of what this fact is about, e.g. 'billing service deploy key id'. Saving again with the same topic in the same scope replaces the earlier entry; use it for anything that may be corrected later.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "memory_id", description: "Alternative to topic for editing one specific record: use an existing record ID returned by memory.search or memory.recall in the same scope. Omit or pass null for a new record; empty strings also mean create. A nonempty unknown ID is an error, never an implicit create.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
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
        let topic = MemoryTopic.display(arguments["topic"]?.asString)

        let sourceType = arguments["source_type"]?.asString
        let sourceId = arguments["source_id"]?.asString
        let source = sourceType.map { MemorySource(type: $0, id: sourceId) }

        var metadata: [String: JSONValue] = [:]
        if let metadataObject = arguments["metadata"]?.asObject {
            metadata = metadataObject
        }
        if let topic { metadata[MemoryTopic.metadataKey] = .string(topic) }

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

        // Same topic in the same scope: replace the earlier entry instead of adding a contradicting second one.
        if let topic {
            let key = MemoryTopic.key(topic)
            let earlier = await context.memoryStore.entries(filter: MemoryEntryFilter(scope: scope))
                .filter { $0.metadata[MemoryTopic.metadataKey]?.asString.map(MemoryTopic.key) == key }
                .sorted { $0.updatedAt > $1.updatedAt }
            if let target = earlier.first {
                guard let updated = await context.memoryStore.updateEntry(
                    id: target.id, note: note, summary: summary ?? note,
                    kind: kind, importance: importance, confidence: confidence
                ) else {
                    return toolFailure(tool: name, code: "memory_update_failed", message: "Could not update the memory entry.", retryable: true)
                }
                // Older duplicates of the same topic (from before topics existed) would still contradict the new value.
                for stale in earlier.dropFirst() { _ = await context.memoryStore.softDelete(id: stale.id) }
                return toolSuccess(tool: name, data: .object([
                    "id": .string(updated.id),
                    "updated": .bool(true),
                    "topic": .string(topic),
                    "replaced_note": .string(target.note),
                    "kind": .string(updated.kind.rawValue),
                    "class": .string(updated.memoryClass.rawValue)
                ]))
            }
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
