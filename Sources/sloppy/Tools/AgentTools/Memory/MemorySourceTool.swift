import Foundation
import AnyLanguageModel
import Protocols
import AgentRuntime

struct MemorySourceTool: CoreTool {
    let domain = "memory"
    let name = "memory.source"
    let title = "Read memory source"
    let status = "fully_functional"
    let description = "Read the preserved source snapshot for an imported memory record in this agent's scope. Uses memory_id from recall/search, not an original file path. By default starts at the record's evidence range; use returned nextOffset to continue."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "memory_id", description: "Imported record ID from memory.recall or memory.search", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "offset", description: "Optional UTF-8 byte offset. Defaults to the record's evidence range.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
            .init(name: "max_bytes", description: "Maximum bytes to return, from 4 to 32768; defaults to 4096.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
            .init(name: "source_index", description: "Select a source passage from availableSources; defaults to 0.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.memoryImportService else { return toolFailure(tool: name, code: "not_available", message: "Source archive is unavailable.", retryable: false) }
        let id = arguments["memory_id"]?.asString ?? ""
        let entries = await context.memoryStore.entries(filter: .init(scope: .agent(context.agentID)))
        guard let entry = entries.first(where: { $0.id == id }) else {
            return toolFailure(tool: name, code: "memory_source_not_found", message: "No imported record with an archived source exists in this agent's scope.", retryable: false)
        }
        do {
            let parts = (entry.source?.id ?? "").split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            let locations: [MemoryImportSourceLocation]
            if entry.source?.type == "memory_import", parts.count == 4, parts[0] == "v1", parts[1] == context.agentID {
                locations = [.init(jobId: parts[2], sourceId: parts[3], name: entry.metadata["source_name"]?.asString ?? "Source", startUTF8: entry.metadata["source_start_utf8"]?.asInt ?? 0, endUTF8: entry.metadata["source_end_utf8"]?.asInt ?? 0)]
            } else {
                locations = try await service.memoryImportSourceLocations(agentID: context.agentID, memoryID: id)
            }
            guard !locations.isEmpty else { throw MemoryImportError.invalid("No archived source is linked yet. Use the durable importer on the original attachments first.") }
            let index = arguments["source_index"]?.asInt ?? 0
            guard locations.indices.contains(index) else { throw MemoryImportError.invalid("source_index is outside availableSources.") }
            let location = locations[index]
            let source = try await service.memoryImportSource(agentID: context.agentID, id: location.jobId, sourceID: location.sourceId)
            let bytes = Array(source.content.utf8)
            let offset = arguments["offset"]?.asInt ?? location.startUTF8
            guard offset >= 0, offset <= bytes.count, offset == bytes.count || bytes[offset] & 0xC0 != 0x80 else {
                return toolFailure(tool: name, code: "invalid_arguments", message: "offset must be a valid UTF-8 boundary within the source. Use nextOffset from the previous read.", retryable: false)
            }
            let maxBytes = min(32768, max(4, arguments["max_bytes"]?.asInt ?? 4096))
            var end = min(bytes.count, offset + maxBytes)
            while end < bytes.count && bytes[end] & 0xC0 == 0x80 { end -= 1 }
            return toolSuccess(tool: name, data: .object([
                "name": .string(source.name), "sha256": .string(source.sha256), "content": .string(String(decoding: bytes[offset..<end], as: UTF8.self)),
                "offset": .number(Double(offset)), "nextOffset": .number(Double(end)), "truncated": .bool(end < bytes.count),
                "sizeBytes": .number(Double(bytes.count)),
                "availableSources": .array(locations.map { .object(["jobId": .string($0.jobId), "sourceId": .string($0.sourceId), "name": .string($0.name), "startUTF8": .number(Double($0.startUTF8))]) })
            ]))
        } catch { return toolFailure(tool: name, code: "memory_source_read_failed", message: error.localizedDescription, retryable: false) }
    }
}
