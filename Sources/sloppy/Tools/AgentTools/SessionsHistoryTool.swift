import AnyLanguageModel
import Foundation
import Protocols

struct SessionsHistoryTool: CoreTool {
    let domain = "session"
    let title = "Session history"
    let status = "fully_functional"
    let name = "sessions.history"
    let description = "Read full event history for one session."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "sessionId", description: "Target session ID (defaults to current)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "limit", description: "Max events to return", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let targetSession = arguments["sessionId"]?.asString ?? context.sessionID
        do {
            let detail = try context.sessionStore.loadSession(agentID: context.agentID, sessionID: targetSession)
            return toolSuccess(tool: name, data: encodeJSONValue(detail))
        } catch {
            return toolFailure(tool: name, code: "session_history_failed", message: "Failed to load session history.", retryable: true)
        }
    }
}
