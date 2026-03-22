import AnyLanguageModel
import Foundation
import Protocols

struct SessionsListTool: CoreTool {
    let domain = "session"
    let title = "List sessions"
    let status = "fully_functional"
    let name = "sessions.list"
    let description = "List sessions for current agent."

    var parameters: GenerationSchema {
        .objectSchema([])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        do {
            let sessions = try context.sessionStore.listSessions(agentID: context.agentID)
            return toolSuccess(tool: name, data: encodeJSONValue(sessions))
        } catch {
            return toolFailure(tool: name, code: "session_list_failed", message: "Failed to list sessions.", retryable: true)
        }
    }
}
