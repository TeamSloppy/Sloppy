import Foundation
import Protocols
import Logging

// MARK: - Task Clarifications

extension CoreService {
    public func listTaskClarifications(projectID: String, taskID: String) async throws -> [TaskClarificationRecord] {
        guard let normalizedProject = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard let normalizedTask = normalizedEntityID(taskID) else {
            throw ProjectError.invalidTaskID
        }
        guard let project = await store.project(id: normalizedProject) else {
            throw ProjectError.notFound
        }
        let normalizedTaskLowercased = normalizedTask.lowercased()
        guard project.tasks.contains(where: { $0.id.lowercased() == normalizedTaskLowercased }) else {
            throw ProjectError.notFound
        }
        return await store.listClarifications(projectId: normalizedProject, taskId: normalizedTask)
    }

    public func createTaskClarification(
        projectID: String,
        taskID: String,
        request: TaskClarificationCreateRequest
    ) async throws -> TaskClarificationRecord {
        guard let normalizedProject = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard let normalizedTask = normalizedEntityID(taskID) else {
            throw ProjectError.invalidTaskID
        }
        guard var project = await store.project(id: normalizedProject) else {
            throw ProjectError.notFound
        }
        let normalizedTaskLowercased = normalizedTask.lowercased()
        guard let taskIndex = project.tasks.firstIndex(where: { $0.id.lowercased() == normalizedTaskLowercased }) else {
            throw ProjectError.notFound
        }

        let task = project.tasks[taskIndex]
        let effectiveLoopMode = task.loopModeOverride ?? project.taskLoopMode
        let targetType: ClarificationTargetType
        switch effectiveLoopMode {
        case .human:
            if task.originType == .channel, let _ = task.originChannelId {
                targetType = .channel
            } else {
                targetType = .human
            }
        case .agent:
            targetType = .actor
        }

        let now = Date()
        let record = TaskClarificationRecord(
            id: UUID().uuidString,
            projectId: normalizedProject,
            taskId: project.tasks[taskIndex].id,
            status: .pending,
            targetType: targetType,
            targetActorId: nil,
            targetChannelId: (targetType == .channel) ? task.originChannelId : nil,
            questionText: request.questionText.trimmingCharacters(in: .whitespacesAndNewlines),
            options: request.options,
            allowNote: request.allowNote ?? true,
            createdByAgentId: request.createdByAgentId,
            createdAt: now
        )
        await store.saveClarification(record)

        project.tasks[taskIndex].status = ProjectTaskStatus.waitingInput.rawValue
        project.tasks[taskIndex].updatedAt = now
        project.updatedAt = now
        await store.saveProject(project)

        return record
    }

    public func answerTaskClarification(
        projectID: String,
        taskID: String,
        clarificationID: String,
        request: TaskClarificationAnswerRequest
    ) async throws -> TaskClarificationRecord {
        guard let normalizedProject = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard let normalizedTask = normalizedEntityID(taskID) else {
            throw ProjectError.invalidTaskID
        }
        guard var record = await store.clarification(id: clarificationID) else {
            throw ProjectError.notFound
        }
        guard record.projectId == normalizedProject else {
            throw ProjectError.notFound
        }
        let normalizedTaskLowercased = normalizedTask.lowercased()
        guard record.taskId.lowercased() == normalizedTaskLowercased else {
            throw ProjectError.notFound
        }
        guard record.status == .pending else {
            throw ProjectError.invalidPayload
        }

        let now = Date()
        record.status = .answered
        record.selectedOptionIds = request.selectedOptionIds
        record.note = request.note
        record.answeredAt = now
        await store.saveClarification(record)

        guard var project = await store.project(id: normalizedProject) else {
            return record
        }
        if let taskIndex = project.tasks.firstIndex(where: { $0.id.lowercased() == normalizedTaskLowercased }) {
            let hasPending = await store.listClarifications(projectId: normalizedProject, taskId: project.tasks[taskIndex].id)
                .contains(where: { $0.status == .pending })
            if !hasPending {
                project.tasks[taskIndex].status = ProjectTaskStatus.ready.rawValue
                project.tasks[taskIndex].updatedAt = now
                project.updatedAt = now
                await store.saveProject(project)
            }
        }

        return record
    }

    /// Returns currently active runtime config snapshot.
}
