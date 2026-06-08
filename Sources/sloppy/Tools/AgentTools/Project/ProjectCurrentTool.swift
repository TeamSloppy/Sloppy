import AnyLanguageModel
import Foundation
import PluginSDK
import Protocols

struct ProjectCurrentTool: CoreTool {
    let domain = "project"
    let title = "Get current project"
    let status = "fully_functional"
    let name = "project.current"
    let description = "Return the project associated with the current session/channel. Use this before creating or updating tasks when you are unsure which project is current."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "channelId", description: "Channel ID (defaults to current session)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "topicId", description: "Optional topic scoping", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.projectService else {
            return toolFailure(tool: name, code: "not_available", message: "Project service not available.", retryable: false)
        }

        let requestedChannelId = trimmedStringArgument(arguments, "channelId")
        let channelId = requestedChannelId ?? context.sessionID
        let topicId = trimmedStringArgument(arguments, "topicId")
        let channelProject = await svc.findProjectForChannel(channelId: channelId, topicId: topicId)
        let scopedProject = await currentProjectFromSessionScope(
            context: context,
            service: svc,
            allowFallback: requestedChannelId == nil || requestedChannelId == context.sessionID
        )
        guard let project = channelProject ?? scopedProject else {
            return toolFailure(tool: name, code: "project_not_found", message: "No project found for this channel.", retryable: false)
        }

        let scoped = ChannelGatewayScope.parse(channelId)
        let effectiveChannelId = ChannelGatewayScope.scopedChannelId(
            baseChannelId: scoped.baseChannelId,
            topicKey: scoped.topicKey ?? topicId
        )
        let matchedChannel = project.channels.first { $0.channelId == effectiveChannelId }
            ?? project.channels.first { binding in
                ChannelGatewayScope.sessionMatchesBinding(sessionChannelId: effectiveChannelId, bindingChannelId: binding.channelId)
            }

        return toolSuccess(tool: name, data: projectCurrentJSONValue(
            project,
            requestedChannelId: channelId,
            effectiveChannelId: effectiveChannelId,
            matchedChannel: matchedChannel,
            topicId: topicId
        ))
    }
}

private func currentProjectFromSessionScope(
    context: ToolContext,
    service: any ProjectToolService,
    allowFallback: Bool
) async -> ProjectRecord? {
    guard allowFallback else {
        return nil
    }
    guard let projectID = context.currentProjectID else {
        return nil
    }
    return try? await service.getProject(id: projectID)
}

private func projectCurrentJSONValue(
    _ project: ProjectRecord,
    requestedChannelId: String,
    effectiveChannelId: String,
    matchedChannel: ProjectChannel?,
    topicId: String?
) -> JSONValue {
    .object([
        "projectId": .string(project.id),
        "projectName": .string(project.name),
        "description": .string(project.description),
        "icon": project.icon.map { .string($0) } ?? .null,
        "isFavorite": .bool(project.isFavorite),
        "channelId": .string(requestedChannelId),
        "effectiveChannelId": .string(effectiveChannelId),
        "matchedChannelId": matchedChannel.map { .string($0.channelId) } ?? .null,
        "matchedChannelTitle": matchedChannel.map { .string($0.title) } ?? .null,
        "topicId": topicId.map { .string($0) } ?? .null,
        "taskCount": .number(Double(project.tasks.count)),
        "actors": .array(project.actors.map { .string($0) }),
        "teams": .array(project.teams.map { .string($0) }),
        "models": .array(project.models.map { .string($0) }),
        "repoPath": project.repoPath.map { .string($0) } ?? .null,
        "taskLoopMode": .string(project.taskLoopMode.rawValue),
        "autopilotSettings": autopilotSettingsJSONValue(project.autopilotSettings),
        "taskSyncSettings": .object([
            "linkedProjects": .array(project.taskSyncSettings.linkedProjects.map(taskSyncLinkedProjectJSONValue))
        ]),
        "taskSyncLinkedProjects": .array(project.taskSyncSettings.linkedProjects.map(taskSyncLinkedProjectJSONValue)),
        "channels": .array(project.channels.map { ch in
            .object([
                "id": .string(ch.id),
                "channelId": .string(ch.channelId),
                "title": .string(ch.title)
            ])
        }),
        "createdAt": .string(ISO8601DateFormatter().string(from: project.createdAt)),
        "updatedAt": .string(ISO8601DateFormatter().string(from: project.updatedAt))
    ])
}

private func taskSyncLinkedProjectJSONValue(_ linkedProject: ProjectTaskSyncLinkedProject) -> JSONValue {
    .object([
        "title": .string(linkedProject.title),
        "projectURL": .string(linkedProject.projectURL),
        "projectNodeId": linkedProject.projectNodeId.map { .string($0) } ?? .null,
        "tag": .string(linkedProject.tag),
        "statusOptions": .array(linkedProject.statusOptions.map { .string($0) })
    ])
}

private func autopilotSettingsJSONValue(_ settings: ProjectAutopilotSettings) -> JSONValue {
    .object([
        "enabled": .bool(settings.enabled),
        "mode": .string(settings.mode.rawValue),
        "defaultAgentId": settings.defaultAgentId.map { .string($0) } ?? .null,
        "reviewerAgentId": settings.reviewerAgentId.map { .string($0) } ?? .null,
        "includedTags": .array(settings.includedTags.map { .string($0) }),
        "ignoredTags": .array(settings.ignoredTags.map { .string($0) }),
        "trustedAuthors": .array(settings.trustedAuthors.map { .string($0) }),
        "maxParallelTasks": .number(Double(settings.maxParallelTasks)),
        "canUseWeb": .bool(settings.canUseWeb),
        "canEditFiles": .bool(settings.canEditFiles),
        "canRunCommands": .bool(settings.canRunCommands),
        "canStartLocalhost": .bool(settings.canStartLocalhost),
        "canCommit": .bool(settings.canCommit),
        "canPush": .bool(settings.canPush)
    ])
}
