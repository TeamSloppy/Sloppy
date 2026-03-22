import AnyLanguageModel
import AgentRuntime
import Foundation
import Protocols

struct WorkersRouteTool: CoreTool {
    let domain = "worker"
    let title = "Route worker"
    let status = "fully_functional"
    let name = "workers.route"
    let description = "Send a structured continuation, completion, or failure command to an interactive worker."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "workerId", description: "Target worker ID", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "command", description: "Command: continue, complete, or fail", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "summary", description: "Optional summary", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "error", description: "Optional error message", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "report", description: "Optional report", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let workerId = arguments["workerId"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !workerId.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`workerId` is required.", retryable: false)
        }
        let rawCommand = arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let command = WorkerRouteCommandAction(rawValue: rawCommand), !rawCommand.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`command` is required.", retryable: false)
        }

        let routeCommand = WorkerRouteCommand(
            command: command,
            summary: trimmedArg("summary", from: arguments),
            error: trimmedArg("error", from: arguments),
            report: trimmedArg("report", from: arguments)
        )

        let channelID = sessionChannelID(agentID: context.agentID, sessionID: context.sessionID)
        let message: String
        do {
            message = String(decoding: try JSONEncoder().encode(routeCommand), as: UTF8.self)
        } catch {
            return toolFailure(tool: name, code: "encode_failed", message: "Failed to encode worker route command.", retryable: true)
        }

        let accepted = await context.runtime.routeMessage(channelId: channelID, workerId: workerId, message: message)
        guard accepted else {
            return toolFailure(tool: name, code: "worker_route_rejected", message: "Worker route was not accepted.", retryable: false)
        }

        let snapshots = await context.runtime.workerSnapshots()
        let snapshot = snapshots.first(where: { $0.workerId == workerId })
        return toolSuccess(tool: name, data: .object([
            "workerId": .string(workerId),
            "accepted": .bool(true),
            "status": snapshot.map { .string($0.status.rawValue) } ?? .null,
            "latestReport": snapshot?.latestReport.map(JSONValue.string) ?? .null
        ]))
    }
}
