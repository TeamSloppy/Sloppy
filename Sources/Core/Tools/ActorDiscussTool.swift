import AnyLanguageModel
import Foundation
import Logging
import Protocols

struct ActorDiscussTool: CoreTool {
    let domain = "actor"
    let title = "Discuss with actor"
    let status = "fully_functional"
    let name = "actor.discuss_with_actor"
    let description = "Initiate a scoped discussion with another actor via a temporary channel."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "actorId", description: "Target actor ID", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "message", description: "Opening message to the actor", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "topic", description: "Discussion topic", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "taskId", description: "Optional related task ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.projectService else {
            return toolFailure(tool: name, code: "not_available", message: "Project service not available.", retryable: false)
        }
        let targetActorId = arguments["actorId"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let topic = arguments["topic"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = arguments["message"]?.asString ?? ""
        let taskId = arguments["taskId"]?.asString

        guard !targetActorId.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`actorId` is required.", retryable: false)
        }
        guard !message.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`message` is required.", retryable: false)
        }

        let board = try? await svc.actorBoard()
        guard let targetNode = board?.nodes.first(where: { $0.id == targetActorId }) else {
            return toolFailure(tool: name, code: "actor_not_found", message: "Target actor '\(targetActorId)' not found on board.", retryable: false)
        }

        let hasLink = board?.links.contains(where: { link in
            (link.communicationType == .discussion || link.communicationType == .chat) &&
            (link.sourceActorId == targetActorId || link.targetActorId == targetActorId)
        }) ?? false

        guard hasLink else {
            return toolFailure(tool: name, code: "no_discussion_link", message: "No discussion or chat link to actor '\(targetActorId)'.", retryable: false)
        }

        let discussionChannelId = "discussion:\(UUID().uuidString.prefix(8))"
        let prompt = """
            [actor_discussion_v1]
            You are \(targetNode.displayName) (role: \(targetNode.role ?? "unspecified")).
            Another actor wants to discuss: \(topic.isEmpty ? "(no topic)" : topic)
            \(taskId.map { "Related task: \($0)" } ?? "")

            Their message:
            \(message)

            Respond concisely. Focus on your area of expertise.
            """

        let decision = await context.runtime.postMessage(
            channelId: discussionChannelId,
            request: ChannelMessageRequest(userId: "actor", content: prompt)
        )

        let snapshot = await context.runtime.channelState(channelId: discussionChannelId)
        let response = snapshot?.messages.last(where: { $0.userId == "system" })?.content
            ?? "Discussion initiated with \(targetNode.displayName)."

        await context.runtime.eventBus.publish(
            EventEnvelope(
                messageType: .actorDiscussionStarted,
                channelId: discussionChannelId,
                payload: .object([
                    "targetActorId": .string(targetActorId),
                    "topic": .string(topic),
                    "message": .string(message)
                ])
            )
        )

        context.logger.info(
            "actor.discussion.started",
            metadata: [
                "target_actor_id": .string(targetActorId),
                "discussion_channel": .string(discussionChannelId),
                "topic": .string(topic),
                "route_action": .string(decision.action.rawValue)
            ]
        )

        return toolSuccess(tool: name, data: .object([
            "discussionChannelId": .string(discussionChannelId),
            "targetActorId": .string(targetActorId),
            "targetActorName": .string(targetNode.displayName),
            "response": .string(response)
        ]))
    }
}
