import AnyLanguageModel
import Foundation
import Logging
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
        let targetSession = await resolveSessionIDForHistory(arguments["sessionId"]?.asString, context: context)
        do {
            let detail = try context.sessionStore.loadSession(agentID: context.agentID, sessionID: targetSession)
            return toolSuccess(tool: name, data: encodeJSONValue(detail))
        } catch {
            if let channelDetail = await loadChannelSessionDetailIfAvailable(
                sessionID: targetSession,
                context: context
            ) {
                return toolSuccess(tool: name, data: encodeJSONValue(channelDetail))
            }
            context.logger.warning(
                "sessions.history failed",
                metadata: [
                    "agent_id": .string(context.agentID),
                    "session_id": .string(targetSession),
                    "context_session_id": .string(context.sessionID),
                    "raw_session_arg": .string(arguments["sessionId"]?.asString ?? "<nil>"),
                    "error": .string(String(describing: error)),
                    "error_type": .string(String(reflecting: type(of: error)))
                ]
            )
            return toolFailure(
                tool: name,
                code: "session_history_failed",
                message: "Failed to load session history: \(error)",
                retryable: true
            )
        }
    }

    private func resolveSessionIDForHistory(_ raw: String?, context: ToolContext) async -> String {
        let resolved = resolveSessionID(raw, context: context)
        guard resolved == context.sessionID,
              let channelID = context.channelID,
              !channelID.isEmpty,
              !resolved.hasPrefix("session-")
        else {
            return resolved
        }

        let sessions = (try? await context.channelSessionStore.listSessions(
            status: .open,
            channelIds: Set([channelID]),
            limit: 1
        )) ?? []
        return sessions.first?.sessionId ?? resolved
    }

    private func loadChannelSessionDetailIfAvailable(
        sessionID: String,
        context: ToolContext
    ) async -> ChannelSessionDetail? {
        guard let channelID = context.channelID,
              !channelID.isEmpty
        else {
            return nil
        }
        let sessions = (try? await context.channelSessionStore.listSessions(
            status: .open,
            channelIds: Set([channelID]),
            limit: 1
        )) ?? []
        guard sessions.first?.sessionId == sessionID else {
            return nil
        }
        return try? await context.channelSessionStore.loadSessionDetail(sessionID: sessionID)
    }
}
