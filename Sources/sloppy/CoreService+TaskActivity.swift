import Foundation
import Protocols

// MARK: - Task Activity

extension CoreService {
    public func listTaskActivities(projectID: String, taskID: String) async -> [TaskActivity] {
        let url = taskActivitiesFileURL(projectID: projectID, taskID: taskID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TaskActivity].self, from: data)) ?? []
    }

    public func recordTaskActivity(
        projectID: String,
        taskID: String,
        field: TaskActivityField,
        oldValue: String?,
        newValue: String?,
        actorId: String
    ) async {
        var activities = await listTaskActivities(projectID: projectID, taskID: taskID)
        let activity = TaskActivity(
            id: UUID().uuidString,
            taskId: taskID,
            field: field,
            oldValue: oldValue,
            newValue: newValue,
            actorId: actorId
        )
        activities.append(activity)
        saveTaskActivities(activities, projectID: projectID, taskID: taskID)
    }

    func taskActivitiesFileURL(projectID: String, taskID: String) -> URL {
        projectMetaDirectoryURL(projectID: projectID)
            .appendingPathComponent("task-activities-\(taskID).json")
    }

    func saveTaskActivities(_ activities: [TaskActivity], projectID: String, taskID: String) {
        ensureProjectWorkspaceDirectory(projectID: projectID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(activities) else { return }
        let url = taskActivitiesFileURL(projectID: projectID, taskID: taskID)
        try? data.write(to: url, options: .atomic)
    }

    func recordSystemStatusChange(
        projectID: String,
        taskID: String,
        from oldStatus: String,
        to newStatus: String,
        source: String
    ) async {
        guard oldStatus != newStatus else { return }
        await recordTaskActivity(
            projectID: projectID, taskID: taskID,
            field: .status, oldValue: oldStatus, newValue: newStatus, actorId: source
        )
    }

    func recordTaskFieldChanges(
        projectID: String,
        taskID: String,
        oldTask: ProjectTask,
        newTask: ProjectTask,
        changedBy: String
    ) async {
        if oldTask.status != newTask.status {
            await recordTaskActivity(
                projectID: projectID, taskID: taskID,
                field: .status, oldValue: oldTask.status, newValue: newTask.status, actorId: changedBy
            )
        }
        if oldTask.priority != newTask.priority {
            await recordTaskActivity(
                projectID: projectID, taskID: taskID,
                field: .priority, oldValue: oldTask.priority, newValue: newTask.priority, actorId: changedBy
            )
        }
        let oldAssignee = oldTask.actorId ?? oldTask.teamId ?? ""
        let newAssignee = newTask.actorId ?? newTask.teamId ?? ""
        if oldAssignee != newAssignee {
            await recordTaskActivity(
                projectID: projectID, taskID: taskID,
                field: .assignee,
                oldValue: oldAssignee.isEmpty ? nil : oldAssignee,
                newValue: newAssignee.isEmpty ? nil : newAssignee,
                actorId: changedBy
            )
        }
        if oldTask.title != newTask.title {
            await recordTaskActivity(
                projectID: projectID, taskID: taskID,
                field: .title, oldValue: oldTask.title, newValue: newTask.title, actorId: changedBy
            )
        }
        if oldTask.description != newTask.description {
            await recordTaskActivity(
                projectID: projectID, taskID: taskID,
                field: .description, oldValue: oldTask.description, newValue: newTask.description, actorId: changedBy
            )
        }
        if oldTask.selectedModel != newTask.selectedModel {
            await recordTaskActivity(
                projectID: projectID, taskID: taskID,
                field: .selectedModel,
                oldValue: oldTask.selectedModel,
                newValue: newTask.selectedModel,
                actorId: changedBy
            )
        }
    }

}
