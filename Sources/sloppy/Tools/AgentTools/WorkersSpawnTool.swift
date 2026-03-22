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
            .init(name: "tools", description: "Optional restricted tool list", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true)
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

        let channelID = sessionChannelID(agentID: context.agentID, sessionID: context.sessionID)
        let spec = WorkerTaskSpec(
            taskId: effectiveTaskId,
            channelId: channelID,
            title: effectiveTitle,
            objective: objective,
            tools: tools,
            mode: mode
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
}
