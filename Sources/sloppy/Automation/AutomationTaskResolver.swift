import Foundation
import Protocols

struct AutomationTaskResolution: Sendable, Equatable {
    var taskId: String?
    var created: Bool

    init(taskId: String? = nil, created: Bool = false) {
        self.taskId = taskId
        self.created = created
    }
}

struct AutomationTaskResolver {
    func resolve(
        mode: AutomationTaskMode,
        projectID: String,
        repositoryFullName: String,
        payload: AutomationTriggerPayload,
        service: CoreService
    ) async throws -> AutomationTaskResolution {
        switch mode {
        case .none:
            return AutomationTaskResolution()
        case .createTask:
            return try await createTask(
                projectID: projectID,
                repositoryFullName: repositoryFullName,
                payload: payload,
                service: service
            )
        case .attachToExistingIfMatch:
            return await attachTask(
                projectID: projectID,
                repositoryFullName: repositoryFullName,
                payload: payload,
                service: service
            )
        case .createOrAttach:
            let attached = await attachTask(
                projectID: projectID,
                repositoryFullName: repositoryFullName,
                payload: payload,
                service: service
            )
            if attached.taskId != nil {
                return attached
            }
            return try await createTask(
                projectID: projectID,
                repositoryFullName: repositoryFullName,
                payload: payload,
                service: service
            )
        }
    }

    private func attachTask(
        projectID: String,
        repositoryFullName: String,
        payload: AutomationTriggerPayload,
        service: CoreService
    ) async -> AutomationTaskResolution {
        guard let project = await service.store.project(id: projectID),
              let matchKey = taskMatchKey(repositoryFullName: repositoryFullName, payload: payload)
        else {
            return AutomationTaskResolution()
        }
        let taskID = project.tasks.first(where: { task in
            task.title.localizedCaseInsensitiveContains(matchKey) ||
                task.description.localizedCaseInsensitiveContains(matchKey)
        })?.id
        return AutomationTaskResolution(taskId: taskID, created: false)
    }

    private func createTask(
        projectID: String,
        repositoryFullName: String,
        payload: AutomationTriggerPayload,
        service: CoreService
    ) async throws -> AutomationTaskResolution {
        let title = taskTitle(repositoryFullName: repositoryFullName, payload: payload)
        let description = taskDescription(repositoryFullName: repositoryFullName, payload: payload)
        let updatedProject = try await service.createProjectTask(
            projectID: projectID,
            request: ProjectTaskCreateRequest(
                title: title,
                description: description,
                priority: "medium",
                status: ProjectTaskStatus.backlog.rawValue,
                changedBy: payload.startedBy
            )
        )
        return AutomationTaskResolution(taskId: updatedProject.tasks.last?.id, created: true)
    }

    private func taskTitle(repositoryFullName: String, payload: AutomationTriggerPayload) -> String {
        if let title = payload.workflowInput["title"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let pr = pullRequestNumber(payload: payload) {
            let prTitle = payload.data["pullRequest"]?.asObject?["title"]?.asString ?? "GitHub automation"
            return "\(repositoryFullName)#\(pr) \(prTitle)"
        }
        return "Automation task for \(repositoryFullName)"
    }

    private func taskDescription(repositoryFullName: String, payload: AutomationTriggerPayload) -> String {
        var lines: [String] = [
            "Automation source: \(payload.source.rawValue)",
            "Repository: \(repositoryFullName)"
        ]
        if let matchKey = taskMatchKey(repositoryFullName: repositoryFullName, payload: payload) {
            lines.append("Match key: \(matchKey)")
        }
        if let action = payload.data["action"]?.asString, !action.isEmpty {
            lines.append("Action: \(action)")
        }
        if let url = payload.data["pullRequest"]?.asObject?["url"]?.asString, !url.isEmpty {
            lines.append("URL: \(url)")
        }
        return lines.joined(separator: "\n")
    }

    private func taskMatchKey(repositoryFullName: String, payload: AutomationTriggerPayload) -> String? {
        guard let pr = pullRequestNumber(payload: payload) else {
            return nil
        }
        return "\(repositoryFullName)#\(pr)"
    }

    private func pullRequestNumber(payload: AutomationTriggerPayload) -> Int? {
        payload.data["pullRequest"]?.asObject?["number"]?.asInt
    }
}
