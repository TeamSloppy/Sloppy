import AnyLanguageModel
import Foundation
import Protocols

struct ProjectTaskUpdateTool: CoreTool {
    let domain = "project"
    let title = "Update project task"
    let status = "fully_functional"
    let name = "project.task_update"
    let description = "Update an existing task in the current channel project. Accepts taskId or reference plus partial fields."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "taskId", description: "Task ID to update", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "reference", description: "Task reference (alternative to taskId)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "title", description: "New title", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "description", description: "New description", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "priority", description: "New priority", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "status", description: "New status", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "actorId", description: "New assigned actor ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "teamId", description: "New assigned team ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
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
        let rawReference = arguments["taskId"]?.asString ?? arguments["reference"]?.asString ?? ""

        guard let normalizedReference = normalizeTaskRef(rawReference) else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`taskId` (or `reference`) is required.", retryable: false)
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
            let task = try findTask(reference: normalizedReference, in: project)
            let updatedProject = try await svc.updateTask(
                projectID: project.id,
                taskID: task.id,
                request: ProjectTaskUpdateRequest(
                    title: arguments["title"]?.asString,
                    description: arguments["description"]?.asString,
                    priority: arguments["priority"]?.asString,
                    status: arguments["status"]?.asString,
                    actorId: arguments["actorId"]?.asString,
                    teamId: arguments["teamId"]?.asString
                )
            )
            let updatedTask = updatedProject.tasks.first(where: { $0.id == task.id }) ?? task
            return toolSuccess(tool: name, data: .object([
                "projectId": .string(updatedProject.id),
                "taskId": .string(updatedTask.id),
                "status": .string(updatedTask.status),
                "task": taskJSONValue(updatedTask)
            ]))
        } catch CoreService.ProjectError.notFound {
            return toolFailure(tool: name, code: "task_not_found", message: "Task `\(normalizedReference)` was not found.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "update_failed", message: "Failed to update task.", retryable: true)
        }
    }
}
