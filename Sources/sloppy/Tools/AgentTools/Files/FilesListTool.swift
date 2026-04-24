import AnyLanguageModel
import Foundation
import Protocols

struct FilesListTool: CoreTool {
    let domain = "files"
    let title = "List directory"
    let status = "fully_functional"
    let name = "files.list"
    let description = "List the contents of a directory in the workspace. Returns file and sub-directory names with their types and sizes."

    private static let defaultMaxDepth = 1
    private static let hardMaxDepth = 5
    private static let maxEntries = 500

    var parameters: GenerationSchema {
        .objectSchema([
            .init(
                name: "path",
                description: "Directory path to list. Use \".\" for the workspace root.",
                schema: DynamicGenerationSchema(type: String.self)
            ),
            .init(
                name: "depth",
                description: "How many levels deep to recurse (1 = immediate children only, max \(Self.hardMaxDepth)). Defaults to 1.",
                schema: DynamicGenerationSchema(type: Int.self),
                isOptional: true
            ),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let pathValue = arguments["path"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pathValue.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`path` is required.", retryable: false)
        }
        guard let dirURL = context.resolveReadablePath(pathValue) else {
            return toolFailure(tool: name, code: "path_not_allowed", message: "Directory path is outside allowed roots.", retryable: false)
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDirectory)
        guard exists else {
            return toolFailure(
                tool: name,
                code: "not_found",
                message: "No directory at \(dirURL.path).",
                retryable: false,
                hint: "Confirm the path spelling and that the directory exists under the workspace."
            )
        }
        guard isDirectory.boolValue else {
            return toolFailure(
                tool: name,
                code: "not_a_directory",
                message: "\(dirURL.path) is a file, not a directory.",
                retryable: false,
                hint: "Use `files.read` to read individual files."
            )
        }

        let depth = min(
            max(1, arguments["depth"]?.asInt ?? Self.defaultMaxDepth),
            Self.hardMaxDepth
        )

        var entries: [JSONValue] = []
        var truncated = false

        collectEntries(
            at: dirURL,
            rootURL: dirURL,
            currentDepth: 0,
            maxDepth: depth,
            entries: &entries,
            truncated: &truncated
        )

        return toolSuccess(tool: name, data: .object([
            "path": .string(dirURL.path),
            "depth": .number(Double(depth)),
            "count": .number(Double(entries.count)),
            "truncated": .bool(truncated),
            "entries": .array(entries),
        ]))
    }

    // MARK: - Private

    private func collectEntries(
        at dirURL: URL,
        rootURL: URL,
        currentDepth: Int,
        maxDepth: Int,
        entries: inout [JSONValue],
        truncated: inout Bool
    ) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        let sorted = items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for item in sorted {
            guard entries.count < Self.maxEntries else {
                truncated = true
                return
            }

            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let isDir = values?.isDirectory ?? false
            let isLink = values?.isSymbolicLink ?? false
            let fileSize = values?.fileSize

            let kind: String
            if isLink { kind = "symlink" }
            else if isDir { kind = "directory" }
            else { kind = "file" }

            let relativePath = item.path.hasPrefix(rootURL.path + "/")
                ? String(item.path.dropFirst(rootURL.path.count + 1))
                : item.lastPathComponent

            var entry: [String: JSONValue] = [
                "name": .string(item.lastPathComponent),
                "path": .string(relativePath),
                "kind": .string(kind),
            ]
            if let size = fileSize, !isDir {
                entry["sizeBytes"] = .number(Double(size))
            }
            entries.append(.object(entry))

            if isDir && !isLink && currentDepth + 1 < maxDepth {
                collectEntries(
                    at: item,
                    rootURL: rootURL,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth,
                    entries: &entries,
                    truncated: &truncated
                )
            }
        }
    }
}
