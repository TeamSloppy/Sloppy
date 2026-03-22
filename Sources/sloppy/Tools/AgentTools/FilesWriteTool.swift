import AnyLanguageModel
import Foundation
import Protocols

struct FilesWriteTool: CoreTool {
    let domain = "files"
    let title = "Write file"
    let status = "fully_functional"
    let name = "files.write"
    let description = "Create or overwrite UTF-8 file in workspace."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "path", description: "Destination file path", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "content", description: "UTF-8 content to write", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "allowEmpty", description: "Allow writing empty content", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let pathValue = arguments["path"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = arguments["content"]?.asString ?? ""
        guard !pathValue.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`path` is required.", retryable: false)
        }
        guard !content.isEmpty || arguments["allowEmpty"]?.asBool == true else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`content` is required.", retryable: false)
        }
        guard let fileURL = context.resolveWritablePath(pathValue) else {
            return toolFailure(tool: name, code: "path_not_allowed", message: "File path is outside allowed roots.", retryable: false)
        }
        let byteCount = content.lengthOfBytes(using: .utf8)
        if byteCount > context.policy.guardrails.maxWriteBytes {
            return toolFailure(tool: name, code: "content_too_large", message: "Content exceeds max writable bytes.", retryable: false)
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return toolSuccess(tool: name, data: .object([
                "path": .string(fileURL.path),
                "sizeBytes": .number(Double(byteCount))
            ]))
        } catch {
            return toolFailure(tool: name, code: "write_failed", message: "Failed to write file.", retryable: true)
        }
    }
}
