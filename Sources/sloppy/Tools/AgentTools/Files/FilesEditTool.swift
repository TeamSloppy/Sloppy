import AnyLanguageModel
import Foundation
import Protocols

struct FilesEditTool: CoreTool {
    let domain = "files"
    let title = "Edit file"
    let status = "fully_functional"
    let name = "files.edit"
    let description = "Replace exact text fragment in file."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "path", description: "File path to edit", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "search", description: "Exact text to search for", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "replace", description: "Replacement text", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "all", description: "Replace all occurrences", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let pathValue = arguments["path"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let search = arguments["search"]?.asString ?? ""
        let replace = arguments["replace"]?.asString ?? ""
        let replaceAll = arguments["all"]?.asBool ?? false

        guard !pathValue.isEmpty, !search.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`path` and `search` are required.", retryable: false)
        }
        guard let fileURL = context.resolveWritablePath(pathValue) else {
            return toolFailure(tool: name, code: "path_not_allowed", message: "File path is outside allowed roots.", retryable: false)
        }
        if context.isAgentsUserOrMemoryMarkdownFile(fileURL) {
            return toolFailure(
                tool: name,
                code: "path_not_allowed",
                message: "USER.md and MEMORY.md must be updated with `agent.documents.set_user_markdown` or `agent.documents.set_memory_markdown`.",
                retryable: false
            )
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let detail = FileSystemToolErrorMapping.describePathIsDirectory(operation: .read, path: fileURL.path)
            return toolFailure(
                tool: name,
                code: detail.code,
                message: detail.message,
                retryable: detail.retryable,
                hint: detail.hint
            )
        }
        let original: String
        do {
            original = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            let detail = FileSystemToolErrorMapping.describe(error: error, operation: .read, path: fileURL.path)
            return toolFailure(
                tool: name,
                code: detail.code,
                message: detail.message,
                retryable: detail.retryable,
                hint: detail.hint
            )
        }

        let updated: String
        let replacements: Int
        if replaceAll {
            updated = original.replacingOccurrences(of: search, with: replace)
            replacements = occurrences(of: search, in: original)
        } else {
            if let range = original.range(of: search) {
                var copy = original
                copy.replaceSubrange(range, with: replace)
                updated = copy
                replacements = 1
            } else {
                updated = original
                replacements = 0
            }
        }
        guard replacements > 0 else {
            return toolFailure(tool: name, code: "search_not_found", message: "Search text not found.", retryable: false)
        }
        if updated.lengthOfBytes(using: .utf8) > context.policy.guardrails.maxWriteBytes {
            return toolFailure(tool: name, code: "content_too_large", message: "Result exceeds max writable bytes.", retryable: false)
        }
        do {
            try updated.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            let detail = FileSystemToolErrorMapping.describe(error: error, operation: .write, path: fileURL.path)
            return toolFailure(
                tool: name,
                code: detail.code,
                message: detail.message,
                retryable: detail.retryable,
                hint: detail.hint
            )
        }
        return toolSuccess(tool: name, data: .object([
            "path": .string(fileURL.path),
            "replacements": .number(Double(replacements))
        ]))
    }
}
