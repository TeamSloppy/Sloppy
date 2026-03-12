import AnyLanguageModel
import Foundation
import Logging
import Protocols

struct ActorConcludeDiscussionTool: CoreTool {
    let domain = "actor"
    let title = "Conclude discussion"
    let status = "fully_functional"
    let name = "actor.conclude_discussion"
    let description = "Conclude and close a discussion channel started by discuss_with_actor."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "discussionChannelId", description: "Discussion channel ID to conclude", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "summary", description: "Discussion summary", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let discussionChannelId = arguments["discussionChannelId"]?.asString ?? ""
        let summary = arguments["summary"]?.asString ?? "Discussion concluded."

        guard !discussionChannelId.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`discussionChannelId` is required.", retryable: false)
        }

        context.logger.info(
            "actor.discussion.concluded",
            metadata: [
                "discussion_channel": .string(discussionChannelId),
                "summary": .string(summary)
            ]
        )

        return toolSuccess(tool: name, data: .object([
            "discussionChannelId": .string(discussionChannelId),
            "concluded": .bool(true),
            "summary": .string(summary)
        ]))
    }
}
