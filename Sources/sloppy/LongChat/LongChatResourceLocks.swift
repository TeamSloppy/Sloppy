import Foundation

/// Scheduling scopes, not filesystem permissions. Workers still use the original tool policy.
enum LongChatResourceLocks {
    static func canonicalKeys(_ keys: [String], projectID: String?, repositoryPath: String?) throws -> [String] {
        let root = try repositoryPath.map { try canonicalPath($0) }
        var result: Set<String> = []
        var hasPathScope = false
        for raw in keys {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw invalidScope("Resource keys must not be empty.") }
            if key.lowercased().hasPrefix("path:") {
                let value = String(key.dropFirst(5))
                guard !value.isEmpty, !value.contains("\0"), !value.split(separator: "/").contains("..") else {
                    throw invalidScope("A path scope must name a file or directory without parent traversal.")
                }
                let absolute: String
                if value.hasPrefix("/") {
                    absolute = try canonicalPath(value)
                } else if let root {
                    absolute = try canonicalPath(URL(fileURLWithPath: root).appendingPathComponent(value).path)
                } else {
                    throw invalidScope("Relative path scopes require a project with a repository path.")
                }
                if let root, !contains(root, absolute) {
                    throw invalidScope("Path scope is outside the selected project checkout: \(value)")
                }
                result.insert("path:" + absolute)
                hasPathScope = true
            } else if key.lowercased().hasPrefix("workspace:"), String(key.dropFirst(10)).hasPrefix("/") {
                let value = String(key.dropFirst(10))
                guard !value.split(separator: "/").contains("..") else {
                    throw invalidScope("Workspace lock paths must not contain parent traversal.")
                }
                result.insert("workspace:" + (try canonicalPath(value)))
            } else {
                result.insert(key.lowercased())
            }
        }
        // A project supplies context. Only work without declared file scopes needs
        // an automatic whole-checkout lock. Explicit coarse locks remain exclusive.
        if hasPathScope, projectID != nil, root == nil {
            throw invalidScope("The selected project has no checkout for file-scoped work.")
        }
        let explicitProjectLock = projectID.map { result.contains("project:" + $0.lowercased()) } ?? false
        if !hasPathScope || explicitProjectLock {
            if let root { result.insert("workspace:" + root) }
            if let projectID { result.insert("project:" + projectID.lowercased()) }
        }
        return result.sorted()
    }

    static func conflicts(_ requested: [String], with occupied: Set<String>) -> Bool {
        requested.contains { key in
            occupied.contains { other in
                if key == other { return true }
                guard let left = filesystemPath(key)?.lowercased(), let right = filesystemPath(other)?.lowercased() else { return false }
                return contains(left, right) || contains(right, left)
            }
        }
    }

    static func pathScopes(_ keys: [String]) -> [String] {
        keys.filter { $0.hasPrefix("path:") }.map { String($0.dropFirst(5)) }
    }

    private static func filesystemPath(_ key: String) -> String? {
        for prefix in ["path:", "workspace:"] where key.hasPrefix(prefix) {
            let path = String(key.dropFirst(prefix.count))
            if path.hasPrefix("/") { return path }
        }
        return nil
    }

    private static func canonicalPath(_ path: String) throws -> String {
        // Resolve existing ancestors first: Foundation leaves the entire URL unresolved
        // when a new file/directory at its tail does not exist yet.
        var ancestor = URL(fileURLWithPath: path).standardizedFileURL
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)) != nil {
                throw invalidScope("Cannot resolve a dangling or cyclic symlink in a scheduling path.")
            }
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in suffix.reversed() { resolved.appendPathComponent(component) }
        return resolved.path
    }

    private static func contains(_ root: String, _ path: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    private static func invalidScope(_ message: String) -> LongChatDelegationDecoder.ValidationError {
        .init(message: message,
            hint: "Use path:<project-relative file or directory> for each area this task may edit. Use an absolute path when no project checkout is selected. Correct resourceKeys and retry with the same requestKey; path scopes do not grant additional permissions.")
    }
}
