import AnyLanguageModel
import Foundation
import Protocols

/// Spawns isolated subagent session(s) and returns only final summaries (no intermediate tool traces in the parent context).
struct AgentsDelegateTaskTool: CoreTool {
    let domain = "agents"
    let title = "Delegate task"
    let status = "fully_functional"
    let name = "agents.delegate_task"
    let description = """
    Spawn one or more subagents in isolated sessions. Each subagent has its own conversation and tool scope; only the final text is returned—intermediate tool results do not appear in your context.

    Provide exactly one of:
    - `goal`: a single task string (optional shared `context` is prepended), or
    - `tasks`: up to 3 goal strings executed in parallel (same as passing an array of `{ \"goal\": \"...\" }` objects).

    Optional `toolsets` narrows tools (e.g. terminal, file, web, skills, lsp, mcp, project, visor, system). If omitted, the subagent inherits your allowed tools minus a fixed safety denylist (no recursive delegation, no clarify, no shared memory writes, no session messaging, no `runtime.exec`).

    Subagents have no memory of this chat—put paths, errors, and constraints in `context` or each goal.
    """

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "goal", description: "Single task description.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(
                name: "tasks",
                description: "Alternative to goal: up to 3 parallel goals (strings or objects with a `goal` field).",
                schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)),
                isOptional: true
            ),
            .init(
                name: "context",
                description: "Shared background (paths, errors, constraints) prepended to each run.",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
            .init(
                name: "toolsets",
                description: "Optional toolset names: terminal, file, web, skills, lsp, mcp, project, visor, system.",
                schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)),
                isOptional: true
            ),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let runner = context.delegateSubagent else {
            return toolFailure(
                tool: name,
                code: "delegation_unavailable",
                message: "Subagent delegation is not configured.",
                retryable: false
            )
        }

        let sharedContext = trimmedArg("context", from: arguments)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolsetList = arguments["toolsets"]?.asArray?
            .compactMap(\.asString)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let toolsets = (toolsetList?.isEmpty == false) ? toolsetList : nil

        let singleGoal = arguments["goal"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tasksValue = arguments["tasks"]

        var batchGoals: [String] = []
        if let tasksArray = tasksValue?.asArray {
            for item in tasksArray {
                if let s = item.asString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    batchGoals.append(s)
                } else if let obj = item.asObject,
                    let g = obj["goal"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !g.isEmpty {
                    batchGoals.append(g)
                }
            }
        }

        let hasSingle = !singleGoal.isEmpty
        let hasBatch = !batchGoals.isEmpty

        if hasSingle, hasBatch {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "Provide either `goal` or `tasks`, not both.",
                retryable: false
            )
        }
        if !hasSingle, !hasBatch {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "One of `goal` or non-empty `tasks` is required.",
                retryable: false
            )
        }
        if batchGoals.count > 3 {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "At most 3 tasks are allowed in `tasks`.",
                retryable: false
            )
        }

        let workingDirectory = context.workspaceRootURL.path
        let agentID = context.agentID

        if hasSingle {
            var objective = ""
            if let sharedContext, !sharedContext.isEmpty {
                objective += "[Context]\n\(sharedContext)\n\n"
            }
            objective += "[Goal]\n\(singleGoal)"
            let taskId = UUID().uuidString
            let summary = await runner(agentID, taskId, objective, workingDirectory, toolsets)
                ?? ""
            return toolSuccess(
                tool: name,
                data: .object([
                    "results": .array([
                        .object([
                            "goal": .string(singleGoal),
                            "summary": .string(summary),
                        ]),
                    ]),
                ])
            )
        }

        let results = await withTaskGroup(of: JSONValue.self) { group in
            for goal in batchGoals {
                group.addTask {
                    var objective = ""
                    if let sharedContext, !sharedContext.isEmpty {
                        objective += "[Context]\n\(sharedContext)\n\n"
                    }
                    objective += "[Goal]\n\(goal)"
                    let taskId = UUID().uuidString
                    let summary = await runner(agentID, taskId, objective, workingDirectory, toolsets) ?? ""
                    return .object([
                        "goal": .string(goal),
                        "summary": .string(summary),
                    ])
                }
            }
            var collected: [JSONValue] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        return toolSuccess(tool: name, data: .object(["results": .array(results)]))
    }
}
