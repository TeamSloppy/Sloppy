import AnyLanguageModel
import Foundation
import Protocols

/// Handles both `sessions.send` and `messages.send` tool IDs.
struct SessionsSendTool: CoreTool {
    let domain = "messages"
    let title = "Send message"
    let status = "fully_functional"
    let name = "messages.send"
    let description = "Send message into current or target session."

    var toolAliases: [String] { ["sessions.send"] }

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "content", description: "Message content", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "sessionId", description: "Target session ID (defaults to current)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "userId", description: "Sender user ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let targetSession = arguments["sessionId"]?.asString ?? context.sessionID
        let content = arguments["content"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userId = arguments["userId"]?.asString ?? "tool"
        guard !content.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`content` is required.", retryable: false)
        }

        do {
            _ = try context.sessionStore.loadSession(agentID: context.agentID, sessionID: targetSession)
            let channelID = sessionChannelID(agentID: context.agentID, sessionID: targetSession)
            _ = await context.runtime.postMessage(
                channelId: channelID,
                request: ChannelMessageRequest(userId: userId, content: content)
            )

            let snapshot = await context.runtime.channelState(channelId: channelID)
            let assistantText = snapshot?.messages.reversed().first(where: { $0.userId == "system" })?.content ?? "Responded inline"

            let appended = [
                AgentSessionEvent(
                    agentId: context.agentID,
                    sessionId: targetSession,
                    type: .message,
                    message: AgentSessionMessage(
                        role: .user,
                        segments: [.init(kind: .text, text: content)],
                        userId: userId
                    )
                ),
                AgentSessionEvent(
                    agentId: context.agentID,
                    sessionId: targetSession,
                    type: .message,
                    message: AgentSessionMessage(
                        role: .assistant,
                        segments: [.init(kind: .text, text: assistantText)],
                        userId: "agent"
                    )
                ),
                AgentSessionEvent(
                    agentId: context.agentID,
                    sessionId: targetSession,
                    type: .runStatus,
                    runStatus: AgentRunStatusEvent(stage: .done, label: "Done", details: "Response is ready.")
                )
            ]
            let summary = try context.sessionStore.appendEvents(agentID: context.agentID, sessionID: targetSession, events: appended)
            return toolSuccess(
                tool: name,
                data: encodeJSONValue(
                    AgentSessionMessageResponse(summary: summary, appendedEvents: appended, routeDecision: snapshot?.lastDecision)
                )
            )
        } catch {
            return toolFailure(tool: name, code: "session_send_failed", message: "Failed to send message to session.", retryable: true)
        }
    }
}
