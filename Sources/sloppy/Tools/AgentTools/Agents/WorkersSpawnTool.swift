import AnyLanguageModel
import AgentRuntime
import Foundation
import Protocols

struct WorkersSpawnTool: CoreTool {
    let domain = "worker"
    let title = "Spawn worker"
    let status = "fully_functional"
    let name = "workers.spawn"
    let description = "Create a worker for the current session channel and start its execution."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "objective", description: "Worker objective", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "title", description: "Optional worker title", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "mode", description: "Worker mode: fire_and_forget or interactive", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "taskId", description: "Optional task ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "tools", description: "Optional restricted tool list", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(
                name: "skillId",
                description: "Optional installed skill id (e.g. owner/repo). When set, preferred `model` is read from that skill's SKILL.md frontmatter.",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            )
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let objective = arguments["objective"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !objective.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`objective` is required.", retryable: false)
        }

        let title = trimmedArg("title", from: arguments)
        let taskId = trimmedArg("taskId", from: arguments)
        let tools = arguments["tools"]?.asArray?
            .compactMap(\.asString)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        let effectiveTaskId = taskId ?? UUID().uuidString
        let effectiveTitle = title ?? "Worker task"

        let mode: WorkerMode
        if let rawMode = trimmedArg("mode", from: arguments) {
            guard let parsed = WorkerMode(rawValue: rawMode) else {
                return toolFailure(tool: name, code: "invalid_arguments", message: "Unsupported worker mode '\(rawMode)'.", retryable: false)
            }
            mode = parsed
        } else {
            mode = .fireAndForget
        }

        // Interactive workers must be routable via `workers.route`. If we attach the calling agentID,
        // ToolExecutionWorkerExecutorAdapter will execute the objective immediately and complete, leaving
        // nothing to route. For interactive mode we intentionally spawn an independent worker.
        let effectiveAgentID: String? = (mode == .interactive) ? nil : context.agentID

        let skillId = trimmedArg("skillId", from: arguments)
        let resolvedModel = await resolveSpawnSelectedModel(skillId: skillId, context: context)

        let channelID = sessionChannelID(agentID: context.agentID, sessionID: context.sessionID)
        let spec = WorkerTaskSpec(
            taskId: effectiveTaskId,
            channelId: channelID,
            title: effectiveTitle,
            objective: objective,
            agentID: effectiveAgentID,
            tools: tools,
            mode: mode,
            selectedModel: resolvedModel
        )
        let workerId = await context.runtime.createWorker(spec: spec)

        return toolSuccess(tool: name, data: .object([
            "workerId": .string(workerId),
            "taskId": .string(spec.taskId),
            "channelId": .string(spec.channelId),
            "title": .string(spec.title),
            "mode": .string(spec.mode.rawValue)
        ]))
    }

    private func resolveSpawnSelectedModel(skillId: String?, context: ToolContext) async -> String? {
        guard let skillId, !skillId.isEmpty, let store = context.agentSkillsStore else {
            return nil
        }
        let skillPath: String
        do {
            skillPath = try store.getSkillPath(agentID: context.agentID, skillID: skillId)
        } catch {
            return nil
        }
        let skillURL = URL(fileURLWithPath: skillPath).appendingPathComponent("SKILL.md")
        guard let data = try? Data(contentsOf: skillURL), let markdown = String(data: data, encoding: .utf8) else {
            return nil
        }
        guard var raw = SkillSKILLFrontmatter.preferredModel(fromMarkdown: markdown) else {
            return nil
        }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cfg = await context.configService?.runtimeConfig(),
           let mapped = cfg.modelRouting[raw]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mapped.isEmpty
        {
            raw = mapped
        }
        return raw.isEmpty ? nil : raw
    }
}
