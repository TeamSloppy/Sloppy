import AgentRuntime
import AnyLanguageModel
import Foundation
import Protocols

struct ChannelHistoryTool: CoreTool {
    let domain = "channel"
    let title = "Channel history"
    let status = "fully_functional"
    let name = "channel.history"
    let description = "Read message history for a channel."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "channel_id", description: "Channel ID to fetch history for", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "limit", description: "Max messages to return (default 50)", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard case .string(let channelId) = arguments["channel_id"] else {
            return toolFailure(tool: name, code: "missing_channel_id", message: "Missing required parameter 'channel_id'.", retryable: false)
        }

        let limit: Int
        if case .number(let n) = arguments["limit"] {
            limit = Int(n)
        } else if case .string(let s) = arguments["limit"] {
            limit = Int(s) ?? 50
        } else {
            limit = 50
        }

        if let result = agentSessionHistory(channelId: channelId, limit: limit, context: context) {
            return result
        }

        do {
            let history = try await context.channelSessionStore.getMessageHistory(channelId: channelId, limit: limit)
            return formatHistory(channelId: channelId, entries: history)
        } catch {
            return toolFailure(tool: name, code: "history_load_failed", message: "Failed to load channel history: \(error.localizedDescription)", retryable: true)
        }
    }

    private func agentSessionHistory(channelId: String, limit: Int, context: ToolContext) -> ToolInvocationResult? {
        let sessionID: String
        if channelId == context.sessionID {
            sessionID = channelId
        } else if channelId == sessionChannelID(agentID: context.agentID, sessionID: context.sessionID) {
            sessionID = context.sessionID
        } else {
            return nil
        }

        guard let detail = try? context.sessionStore.loadSession(agentID: context.agentID, sessionID: sessionID) else {
            return nil
        }

        let messageEvents = detail.events.filter { $0.type == .message }
        let recent = messageEvents.suffix(max(1, limit))

        let entries = recent.compactMap { event -> ChannelMessageEntry? in
            guard let msg = event.message else { return nil }
            let text = msg.segments
                .filter { $0.kind == .text }
                .compactMap(\.text)
                .joined()
            guard !text.isEmpty else { return nil }
            return ChannelMessageEntry(
                id: msg.id,
                userId: msg.userId ?? msg.role.rawValue,
                content: text,
                createdAt: msg.createdAt
            )
        }

        return formatHistory(channelId: channelId, entries: Array(entries))
    }

    private func formatHistory(channelId: String, entries: [ChannelMessageEntry]) -> ToolInvocationResult {
        let isoFormatter = ISO8601DateFormatter()
        let messages: [[String: JSONValue]] = entries.map { entry in
            [
                "id": .string(entry.id),
                "user_id": .string(entry.userId),
                "content": .string(entry.content),
                "created_at": .string(isoFormatter.string(from: entry.createdAt))
            ]
        }
        return toolSuccess(tool: name, data: .object([
            "channel_id": .string(channelId),
            "messages": .array(messages.map { .object($0) }),
            "count": .number(Double(entries.count))
        ]))
    }
}
