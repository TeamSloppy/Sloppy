import AnyLanguageModel
import Foundation
import Protocols

struct CronTool: CoreTool {
    let domain = "automation"
    let title = "Schedule cron job"
    let status = "fully_functional"
    let name = "cron"
    let description = "Schedule a recurring cron job that sends a message into the session channel on a cron schedule. Use this to set up periodic reminders, greetings, or automated triggers."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "schedule", description: "Cron expression (e.g. '0 9 * * *' for every day at 9 AM)", schema: DynamicGenerationSchema(type: String.self), isOptional: false),
            .init(name: "command", description: "Message text or trigger command to send on each cron tick", schema: DynamicGenerationSchema(type: String.self), isOptional: false),
            .init(name: "channel_id", description: "Target channel ID (defaults to current session channel)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
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
