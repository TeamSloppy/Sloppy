import AnyLanguageModel
import Foundation
import Protocols

struct ProjectTaskCreateTool: CoreTool {
    let domain = "project"
    let title = "Create project task"
    let status = "fully_functional"
    let name = "project.task_create"
    let description = "Create a new task in the project associated with the current channel."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "title", description: "Task title", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "description", description: "Task description", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "priority", description: "Task priority: low, medium, high", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "status", description: "Initial task status", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "actorId", description: "Assigned actor ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "teamId", description: "Assigned team ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "projectId", description: "Project ID (use instead of channelId when known)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "channelId", description: "Channel ID (defaults to current session)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "topicId", description: "Optional topic scoping", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.projectService else {
            return toolFailure(tool: name, code: "not_available", message: "Project service not available.", retryable: false)
        }
        let channelId = arguments["channelId"]?.asString ?? context.sessionID
        let topicId = arguments["topicId"]?.asString
        let title = arguments["title"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`title` is required.", retryable: false)
        }

        let project: ProjectRecord
        if let pid = arguments["projectId"]?.asString, !pid.isEmpty {
            do {
                project = try await svc.getProject(id: pid)
            } catch {
                return toolFailure(tool: name, code: "project_not_found", message: "Project not found.", retryable: false)
            }
        } else {
            guard let found = await svc.findProjectForChannel(channelId: channelId, topicId: topicId) else {
                return toolFailure(tool: name, code: "project_not_found", message: "No project found for this channel.", retryable: false)
            }
            project = found
        }

        do {
            let updated = try await svc.createTask(
                projectID: project.id,
                request: ProjectTaskCreateRequest(
                    title: title,
                    description: arguments["description"]?.asString,
                    priority: arguments["priority"]?.asString ?? "medium",
                    status: arguments["status"]?.asString ?? ProjectTaskStatus.pendingApproval.rawValue,
                    actorId: arguments["actorId"]?.asString,
                    teamId: arguments["teamId"]?.asString
                )
            )
            let created = updated.tasks.last
            return toolSuccess(tool: name, data: .object([
                "projectId": .string(updated.id),
                "taskId": .string(created?.id ?? ""),
                "title": .string(created?.title ?? title),
                "status": .string(created?.status ?? "")
            ]))
        } catch {
            return toolFailure(tool: name, code: "create_failed", message: "Failed to create task.", retryable: true)
        }
    }
}
