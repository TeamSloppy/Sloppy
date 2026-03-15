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

        do {
            let history = try await context.channelSessionStore.getMessageHistory(channelId: channelId, limit: limit)
            let messages: [[String: JSONValue]] = history.map { entry in
                [
                    "id": .string(entry.id),
                    "user_id": .string(entry.userId),
                    "content": .string(entry.content),
                    "created_at": .string(ISO8601DateFormatter().string(from: entry.createdAt))
                ]
            }
            return toolSuccess(tool: name, data: .object([
                "channel_id": .string(channelId),
                "messages": .array(messages.map { .object($0) }),
                "count": .number(Double(history.count))
            ]))
        } catch {
            return toolFailure(tool: name, code: "history_load_failed", message: "Failed to load channel history: \(error.localizedDescription)", retryable: true)
        }
    }
}
