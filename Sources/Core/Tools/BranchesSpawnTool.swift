import AnyLanguageModel
import Foundation
import Logging
import Protocols

struct BranchesSpawnTool: CoreTool {
    let domain = "branch"
    let title = "Spawn branch"
    let status = "fully_functional"
    let name = "branches.spawn"
    let description = "Run a focused side branch for the current session and return its conclusion."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "prompt", description: "Prompt for the branch", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "title", description: "Optional title for the branch", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let prompt = arguments["prompt"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = arguments["title"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`prompt` is required.", retryable: false)
        }

        let channelID = sessionChannelID(agentID: context.agentID, sessionID: context.sessionID)
        let branchTitle = (title?.isEmpty == false ? title : nil) ?? "Branch analysis"

        context.logger.info(
            "Tool requested branch spawn",
            metadata: [
                "agent_id": .string(context.agentID),
                "session_id": .string(context.sessionID),
                "channel_id": .string(channelID)
            ]
        )

        guard let execution = await context.runtime.executeBranch(
            channelId: channelID,
            prompt: prompt,
            title: branchTitle
        ) else {
            return toolFailure(tool: name, code: "branch_spawn_failed", message: "Failed to complete branch execution.", retryable: true)
        }

        return toolSuccess(tool: name, data: .object([
            "branchId": .string(execution.branchId),
            "workerId": .string(execution.workerId),
            "conclusion": encodeJSONValue(execution.conclusion)
        ]))
    }
}
