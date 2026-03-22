import AnyLanguageModel
import Foundation
import Logging
import Protocols

struct SessionsSpawnTool: CoreTool {
    let domain = "session"
    let title = "Spawn session"
    let status = "fully_functional"
    let name = "sessions.spawn"
    let description = "Create child or standalone session."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "title", description: "Optional session title", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "parentSessionId", description: "Optional parent session ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let title = arguments["title"]?.asString
        let parent = arguments["parentSessionId"]?.asString

        context.logger.info(
            "Tool requested session spawn",
            metadata: [
                "agent_id": .string(context.agentID),
                "title": .string(optionalLabel(title)),
                "parent_session_id": .string(optionalLabel(parent))
            ]
        )

        do {
            let summary = try context.sessionStore.createSession(
                agentID: context.agentID,
                request: AgentSessionCreateRequest(title: title, parentSessionId: parent)
            )
            context.logger.info(
                "Session spawned via tool",
                metadata: [
                    "agent_id": .string(summary.agentId),
                    "session_id": .string(summary.id),
                    "title": .string(summary.title)
                ]
            )
            return toolSuccess(tool: name, data: encodeJSONValue(summary))
        } catch {
            return toolFailure(tool: name, code: "session_spawn_failed", message: "Failed to create session.", retryable: true)
        }
    }
}
