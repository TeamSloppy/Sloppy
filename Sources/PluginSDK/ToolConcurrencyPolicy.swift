import Foundation

/// Typed classification of tools that may run concurrently with their neighbours in one model batch.
///
/// Only tools with no side effects belong here. Everything else (including unknown, MCP and shell
/// tools) is exclusive: it runs alone, in the order the model issued it.
public enum ToolConcurrencyPolicy {
    public static let readOnlyToolIDs: Set<String> = [
        "files.read", "files.list", "files.grep", "images.inspect", "web.search", "web.fetch",
        "memory.recall", "memory.get", "memory.search", "memory.source",
        "sessions.list", "sessions.history", "sessions.status", "agents.list",
        "skills.list", "skills.search", "project.list", "project.current", "project.task_list", "project.task_get",
        "workspace.get", "workspace.elements.query", "debug.read_logs", "system.list_tools", "system.search_tools",
    ]

    /// Splits `count` calls into consecutive segments. A segment is either a run of concurrency-safe
    /// calls (executed together) or a single exclusive call (a barrier).
    static func segments(count: Int, isSafe: (Int) -> Bool) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var index = 0
        while index < count {
            guard isSafe(index) else {
                result.append(index..<(index + 1))
                index += 1
                continue
            }
            var end = index + 1
            while end < count, isSafe(end) { end += 1 }
            result.append(index..<end)
            index = end
        }
        return result
    }
}
