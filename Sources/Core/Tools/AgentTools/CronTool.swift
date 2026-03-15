import AnyLanguageModel
import Foundation
import Protocols

struct CronTool: CoreTool {
    let domain = "automation"
    let title = "Schedule task"
    let status = "fully_functional"
    let name = "cron"
    let description = "Schedule a recurring background task."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "schedule", description: "Cron expression (e.g. '*/5 * * * *')", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "command", description: "Command to schedule", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "channel_id", description: "Target channel ID (defaults to current session)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "action", description: "Action type", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let schedule = arguments["schedule"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let command = arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let channelId = arguments["channel_id"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? sessionChannelID(agentID: context.agentID, sessionID: context.sessionID)

        guard !schedule.isEmpty, !command.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`schedule` and `command` are required.", retryable: false)
        }

        let task = AgentCronTask(
            id: UUID().uuidString,
            agentId: context.agentID,
            channelId: channelId,
            schedule: schedule,
            command: command,
            enabled: true
        )
        await context.store.saveCronTask(task)

        return toolSuccess(tool: name, data: .object([
            "task_id": .string(task.id),
            "status": .string("created")
        ]))
    }
}
