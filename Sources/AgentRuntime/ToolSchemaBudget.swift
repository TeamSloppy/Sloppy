import AnyLanguageModel
import Foundation

/// Keeps native tool schemas within a share of the active model's context window.
///
/// Tool schemas are sent with every request. On models with small or unknown windows they can crowd out
/// the task itself, so lower-priority tools are withheld until the schemas fit. Selection depends only on
/// tool identifiers and measured schema size, never on conversation text.
public struct ToolSchemaBudget: Sendable {
    public struct Selection {
        public var tools: [any Tool]
        public var droppedNames: [String]
        public var schemaTokens: Int
    }

    /// Fraction of the model's input window that tool schemas may occupy.
    public static let defaultWindowFraction = 0.3

    /// Tools every coding turn needs; kept even when they alone exceed the budget.
    public static let essentialToolIDs: Set<String> = [
        "files.read", "files.list", "files.grep", "files.edit", "files.write",
        "runtime.exec", "runtime.process", "lsp.query",
        "session.complete", "agent_delegate.finish", "agents.delegate_finish",
        "planning.select_route", "planning.request_input", "system.list_tools",
    ]

    /// Useful but optional; kept in order while budget remains, before any other tool.
    public static let preferredToolIDs: Set<String> = [
        "memory.search", "memory.recall", "memory.save", "skills.list", "web.search", "web.fetch",
        "project.current", "project.task_list", "project.task_get", "project.task_update",
        "sessions.list", "sessions.history", "planning.progress_update", "workers.spawn", "workers.route",
        "mcp.call_tool", "mcp.list_tools",
    ]

    public var windowFraction: Double

    public init(windowFraction: Double = ToolSchemaBudget.defaultWindowFraction) {
        self.windowFraction = windowFraction
    }

    public func select(
        from tools: [any Tool],
        windowTokens: Int,
        estimator: TokenPressureEstimator = TokenPressureEstimator()
    ) -> Selection {
        let budget = Int(Double(max(1, windowTokens)) * windowFraction)
        let costs = tools.map { Self.schemaTokens(of: $0, estimator: estimator) }
        let total = costs.reduce(0, +)
        guard total > budget else { return Selection(tools: tools, droppedNames: [], schemaTokens: total) }

        func tier(_ tool: any Tool) -> Int {
            if Self.essentialToolIDs.contains(tool.name) { return 0 }
            if Self.preferredToolIDs.contains(tool.name) { return 1 }
            return 2
        }
        var keep = Set<Int>()
        var used = 0
        for (index, tool) in tools.enumerated() where tier(tool) == 0 {
            keep.insert(index)
            used += costs[index]
        }
        for wanted in [1, 2] {
            for (index, tool) in tools.enumerated() where tier(tool) == wanted && used + costs[index] <= budget {
                keep.insert(index)
                used += costs[index]
            }
        }
        let kept = tools.indices.filter { keep.contains($0) }.map { tools[$0] }
        let dropped = tools.indices.filter { !keep.contains($0) }.map { tools[$0].name }
        return Selection(tools: kept, droppedNames: dropped, schemaTokens: used)
    }

    static func schemaTokens(of tool: any Tool, estimator: TokenPressureEstimator) -> Int {
        guard tool.includesSchemaInInstructions else { return 0 }
        let definition = Transcript.ToolDefinition(tool: tool)
        guard let data = try? JSONEncoder().encode([definition]),
              let text = String(data: data, encoding: .utf8)
        else { return 0 }
        return estimator.estimateTextTokens(text)
    }
}
