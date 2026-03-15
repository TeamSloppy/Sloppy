import AnyLanguageModel
import Foundation
import Protocols

struct SessionsStatusTool: CoreTool {
    let domain = "session"
    let title = "Session status"
    let status = "fully_functional"
    let name = "sessions.status"
    let description = "Read summary status for one session."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "sessionId", description: "Target session ID (defaults to current)", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let targetSession = arguments["sessionId"]?.asString ?? context.sessionID
        do {
            let detail = try context.sessionStore.loadSession(agentID: context.agentID, sessionID: targetSession)
            let activeProcesses = await context.processRegistry.activeCount(sessionID: targetSession)
            let sessionStatus = SessionStatusResponse(
                sessionId: targetSession,
                status: statusFrom(events: detail.events),
                messageCount: detail.summary.messageCount,
                updatedAt: detail.summary.updatedAt,
                activeProcessCount: activeProcesses
            )
            return toolSuccess(tool: name, data: encodeJSONValue(sessionStatus))
        } catch {
            return toolFailure(tool: name, code: "session_status_failed", message: "Failed to load session status.", retryable: true)
        }
    }
}
