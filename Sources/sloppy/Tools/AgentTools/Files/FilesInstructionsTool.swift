import AnyLanguageModel
import Foundation
import Protocols

struct FilesInstructionsTool: CoreTool {
    let domain = "files"
    let title = "Read repository instructions"
    let status = "fully_functional"
    let name = "files.instructions"
    let description = "Find applicable AGENTS.md instructions for a file or directory, in root-to-target order. Use before working in a new repository or subtree. Paths can refer to new files."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "path", description: "File or directory you intend to work in", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "directory", description: "Set true when the target is a directory that has not been created yet", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let path = arguments["path"]?.asString, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`path` is required.", retryable: false)
        }
        guard let target = context.resolveReadablePath(path) else {
            return toolFailure(tool: name, code: "path_not_allowed", message: "Path is outside the readable roots.", retryable: false)
        }

        let fm = FileManager.default
        var directory: ObjCBool = false
        let exists = fm.fileExists(atPath: target.path, isDirectory: &directory)
        let isDirectory = exists ? directory.boolValue : arguments["directory"]?.asBool == true
        let start = isDirectory ? target : target.deletingLastPathComponent()
        let configuredRoots = [context.currentDirectoryURL.path, context.workspaceRootURL.path]
            + context.readOnlyRoots + context.policy.guardrails.allowedWriteRoots + context.policy.guardrails.allowedExecRoots
        let roots = Set(configuredRoots.compactMap { context.resolveReadablePath($0)?.path })
        var ancestry: [URL] = []
        var scope = start
        while context.resolveReadablePath(scope.path) != nil {
            ancestry.append(scope)
            if fm.fileExists(atPath: scope.appendingPathComponent(".git").path) { break }
            let parent = scope.deletingLastPathComponent()
            if parent.path == scope.path { break }
            scope = parent
        }
        if let containingRoot = ancestry.firstIndex(where: { roots.contains($0.path) }),
           let last = ancestry.last, !fm.fileExists(atPath: last.appendingPathComponent(".git").path) {
            ancestry = Array(ancestry.prefix(through: containingRoot))
        }

        var documents: [JSONValue] = []
        for scope in ancestry.reversed() {
            for filename in ["AGENTS.override.md", "AGENTS.md"] {
                let file = scope.appendingPathComponent(filename)
                guard fm.fileExists(atPath: file.path) else { continue }
                guard context.resolveReadablePath(file.path)?.path == file.path,
                      (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return toolFailure(tool: name, code: "instructions_unreadable", message: "Cannot safely read instructions at \(file.path).", retryable: false)
                }
                let result = await FilesReadTool().invoke(arguments: [
                    "path": .string(file.path),
                    "maxBytes": .number(Double(min(20_000, context.policy.guardrails.maxReadBytes)))
                ], context: context)
                guard let data = result.data?.asObject, let content = data["content"] else {
                    return toolFailure(tool: name, code: "instructions_unreadable", message: result.error?.message ?? "Cannot read instructions at \(file.path).", retryable: false)
                }
                documents.append(.object([
                    "scope": .string(scope.path), "path": .string(file.path), "content": content,
                    "truncated": data["truncated"] ?? .bool(false)
                ]))
                break
            }
        }
        return toolSuccess(tool: name, data: .object([
            "target": .string(target.path), "instructions": .array(documents)
        ]))
    }
}
