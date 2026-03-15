import AnyLanguageModel
import Foundation
import Protocols

struct FilesReadTool: CoreTool {
    let domain = "files"
    let title = "Read file"
    let status = "fully_functional"
    let name = "files.read"
    let description = "Read UTF-8 text file from workspace."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "path", description: "Path to the file to read", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "maxBytes", description: "Max bytes to read", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let pathValue = arguments["path"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pathValue.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`path` is required.", retryable: false)
        }
        guard let fileURL = context.resolveReadablePath(pathValue) else {
            return toolFailure(tool: name, code: "path_not_allowed", message: "File path is outside allowed roots.", retryable: false)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let maxBytes = arguments["maxBytes"]?.asInt ?? context.policy.guardrails.maxReadBytes
            if data.count > max(1, maxBytes) {
                return toolFailure(tool: name, code: "file_too_large", message: "File exceeds max readable bytes.", retryable: false)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return toolFailure(tool: name, code: "binary_not_supported", message: "Only UTF-8 files are supported.", retryable: false)
            }
            return toolSuccess(tool: name, data: .object([
                "path": .string(fileURL.path),
                "content": .string(text),
                "sizeBytes": .number(Double(data.count))
            ]))
        } catch {
            return toolFailure(tool: name, code: "read_failed", message: "Failed to read file.", retryable: true)
        }
    }
}
