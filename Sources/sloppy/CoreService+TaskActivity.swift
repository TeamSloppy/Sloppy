import Foundation
import Protocols

// MARK: - Task Activity

extension CoreService {
    public func listTaskLogs(projectID: String, taskID: String) async throws -> [TaskLogEntry] {
        guard let project = await store.project(id: projectID),
              let task = project.tasks.first(where: { $0.id == taskID })
        else {
            throw ProjectError.notFound
        }

        var entries: [TaskLogEntry] = [
            TaskLogEntry(
                id: "created-\(task.id)",
                taskId: task.id,
                kind: "created",
                title: "Task created",
                message: task.title,
                actorId: task.originType.map { $0.rawValue } ?? "user",
                createdAt: task.createdAt
            )
        ]

        let activities = await listTaskActivities(projectID: projectID, taskID: taskID)
        entries.append(contentsOf: activities.map { activity in
            TaskLogEntry(
                id: "activity-\(activity.id)",
                taskId: activity.taskId,
                kind: "activity",
                title: "Task \(activity.field.rawValue) changed",
                field: activity.field.rawValue,
                oldValue: activity.oldValue,
                newValue: activity.newValue,
                actorId: activity.actorId,
                createdAt: activity.createdAt
            )
        })

        entries.append(contentsOf: listTaskLifecycleLogEntries(projectID: projectID, taskID: taskID))

        let runs = await listTaskRuns(projectID: projectID, taskID: taskID)
        entries.append(contentsOf: runs.map { run in
            TaskLogEntry(
                id: "run-\(run.id)",
                taskId: run.taskId,
                kind: "run",
                title: "Task run \(run.outcome.rawValue)",
                message: run.summary ?? run.failureReason,
                actorId: run.actorId,
                agentId: run.agentId,
                channelId: run.channelId,
                workerId: run.workerId,
                createdAt: run.startedAt
            )
        })

        let heartbeats = await listTaskWorkerHeartbeats(projectID: projectID, taskID: taskID)
        entries.append(contentsOf: heartbeats.map { heartbeat in
            TaskLogEntry(
                id: "heartbeat-\(heartbeat.id)",
                taskId: heartbeat.taskId,
                kind: "worker_heartbeat",
                title: "Worker heartbeat",
                message: heartbeat.message,
                agentId: heartbeat.agentId,
                workerId: heartbeat.workerId,
                createdAt: heartbeat.updatedAt
            )
        })

        let invocations = await store.listToolInvocations(projectId: projectID, taskId: taskID, limit: 200)
        entries.append(contentsOf: invocations.map { invocation in
            TaskLogEntry(
                id: "tool-\(invocation.id)",
                taskId: invocation.taskId ?? taskID,
                kind: "tool_invocation",
                title: invocation.ok ? "Tool call completed" : "Tool call failed",
                message: invocation.sessionId,
                agentId: invocation.agentId,
                tool: invocation.tool,
                ok: invocation.ok,
                durationMs: invocation.durationMs,
                createdAt: invocation.createdAt
            )
        })

        return entries.sorted { left, right in
            if left.createdAt == right.createdAt {
                return left.id < right.id
            }
            return left.createdAt < right.createdAt
        }
    }

    public func listTaskActivities(projectID: String, taskID: String) async -> [TaskActivity] {
        let url = taskActivitiesFileURL(projectID: projectID, taskID: taskID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TaskActivity].self, from: data)) ?? []
    }

    public func listTaskRuns(projectID: String, taskID: String) async -> [ProjectTaskRun] {
        let url = taskRunsFileURL(projectID: projectID, taskID: taskID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([ProjectTaskRun].self, from: data)) ?? [])
            .sorted { left, right in
                if left.startedAt == right.startedAt {
                    return left.id < right.id
                }
                return left.startedAt < right.startedAt
            }
    }

    public func listTaskWorkerHeartbeats(projectID: String, taskID: String) async -> [ProjectTaskWorkerHeartbeat] {
        let url = taskWorkerHeartbeatsFileURL(projectID: projectID, taskID: taskID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([ProjectTaskWorkerHeartbeat].self, from: data)) ?? [])
            .sorted { left, right in
                if left.updatedAt == right.updatedAt {
                    return left.id < right.id
                }
                return left.updatedAt < right.updatedAt
            }
    }

    @discardableResult
    public func recordTaskWorkerHeartbeat(
        projectID: String,
        taskID: String,
        workerID: String?,
        agentID: String?,
        status: ProjectTaskWorkerHeartbeatStatus,
        message: String? = nil,
        metadata: [String: String] = [:],
        updatedAt: Date = Date()
    ) async -> ProjectTaskWorkerHeartbeat {
        var heartbeats = await listTaskWorkerHeartbeats(projectID: projectID, taskID: taskID)
        let normalizedWorkerID = normalizedOptionalTaskRunValue(workerID)
        let normalizedAgentID = normalizedOptionalTaskRunValue(agentID)
        let normalizedMessage = normalizedOptionalTaskRunValue(message)
        if let index = heartbeats.indices.reversed().first(where: { heartbeat in
            heartbeats[heartbeat].workerId == normalizedWorkerID
        }) {
            heartbeats[index].agentId = normalizedAgentID ?? heartbeats[index].agentId
            heartbeats[index].status = status
            heartbeats[index].message = normalizedMessage ?? heartbeats[index].message
            heartbeats[index].metadata = heartbeats[index].metadata.merging(metadata) { _, new in new }
            heartbeats[index].updatedAt = updatedAt
            let heartbeat = heartbeats[index]
            saveTaskWorkerHeartbeats(heartbeats, projectID: projectID, taskID: taskID)
            return heartbeat
        }

        let heartbeat = ProjectTaskWorkerHeartbeat(
            id: UUID().uuidString,
            projectId: projectID,
            taskId: taskID,
            workerId: normalizedWorkerID,
            agentId: normalizedAgentID,
            status: status,
            message: normalizedMessage,
            metadata: metadata,
            updatedAt: updatedAt,
            createdAt: updatedAt
        )
        heartbeats.append(heartbeat)
        saveTaskWorkerHeartbeats(heartbeats, projectID: projectID, taskID: taskID)
        return heartbeat
    }

    @discardableResult
    func startTaskRun(
        projectID: String,
        taskID: String,
        actorID: String?,
        agentID: String?,
        workerID: String?,
        channelID: String?
    ) async -> ProjectTaskRun {
        var runs = await listTaskRuns(projectID: projectID, taskID: taskID)
        let now = Date()
        let run = ProjectTaskRun(
            id: UUID().uuidString,
            projectId: projectID,
            taskId: taskID,
            actorId: normalizedOptionalTaskRunValue(actorID),
            agentId: normalizedOptionalTaskRunValue(agentID),
            workerId: normalizedOptionalTaskRunValue(workerID),
            channelId: normalizedOptionalTaskRunValue(channelID),
            outcome: .running,
            startedAt: now,
            createdAt: now,
            updatedAt: now
        )
        runs.append(run)
        saveTaskRuns(runs, projectID: projectID, taskID: taskID)
        return run
    }

    @discardableResult
    func finishLatestTaskRun(
        projectID: String,
        taskID: String,
        outcome: ProjectTaskRunOutcome,
        summary: String? = nil,
        metadata: [String: String] = [:],
        failureReason: String? = nil,
        actorID: String? = nil,
        agentID: String? = nil,
        workerID: String? = nil,
        channelID: String? = nil
    ) async -> ProjectTaskRun {
        var runs = await listTaskRuns(projectID: projectID, taskID: taskID)
        let now = Date()
        if let index = runs.indices.reversed().first(where: { runs[$0].endedAt == nil }) {
            runs[index].outcome = outcome
            runs[index].summary = normalizedOptionalTaskRunValue(summary) ?? runs[index].summary
            runs[index].metadata = runs[index].metadata.merging(metadata) { _, new in new }
            runs[index].failureReason = normalizedOptionalTaskRunValue(failureReason) ?? runs[index].failureReason
            runs[index].actorId = normalizedOptionalTaskRunValue(actorID) ?? runs[index].actorId
            runs[index].agentId = normalizedOptionalTaskRunValue(agentID) ?? runs[index].agentId
            runs[index].workerId = normalizedOptionalTaskRunValue(workerID) ?? runs[index].workerId
            runs[index].channelId = normalizedOptionalTaskRunValue(channelID) ?? runs[index].channelId
            runs[index].endedAt = now
            runs[index].updatedAt = now
            let run = runs[index]
            saveTaskRuns(runs, projectID: projectID, taskID: taskID)
            return run
        }

        let run = ProjectTaskRun(
            id: UUID().uuidString,
            projectId: projectID,
            taskId: taskID,
            actorId: normalizedOptionalTaskRunValue(actorID),
            agentId: normalizedOptionalTaskRunValue(agentID),
            workerId: normalizedOptionalTaskRunValue(workerID),
            channelId: normalizedOptionalTaskRunValue(channelID),
            outcome: outcome,
            summary: normalizedOptionalTaskRunValue(summary),
            metadata: metadata,
            failureReason: normalizedOptionalTaskRunValue(failureReason),
            startedAt: now,
            endedAt: now,
            createdAt: now,
            updatedAt: now
        )
        runs.append(run)
        saveTaskRuns(runs, projectID: projectID, taskID: taskID)
        return run
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

    func taskRunsFileURL(projectID: String, taskID: String) -> URL {
        projectMetaDirectoryURL(projectID: projectID)
            .appendingPathComponent("task-runs-\(taskID).json")
    }

    func taskWorkerHeartbeatsFileURL(projectID: String, taskID: String) -> URL {
        projectMetaDirectoryURL(projectID: projectID)
            .appendingPathComponent("task-worker-heartbeats-\(taskID).json")
    }

    func saveTaskActivities(_ activities: [TaskActivity], projectID: String, taskID: String) {
        ensureProjectWorkspaceDirectory(projectID: projectID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(activities) else { return }
        let url = taskActivitiesFileURL(projectID: projectID, taskID: taskID)
        try? data.write(to: url, options: .atomic)
    }

    func saveTaskRuns(_ runs: [ProjectTaskRun], projectID: String, taskID: String) {
        ensureProjectWorkspaceDirectory(projectID: projectID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(runs) else { return }
        let url = taskRunsFileURL(projectID: projectID, taskID: taskID)
        try? data.write(to: url, options: .atomic)
    }

    func saveTaskWorkerHeartbeats(_ heartbeats: [ProjectTaskWorkerHeartbeat], projectID: String, taskID: String) {
        ensureProjectWorkspaceDirectory(projectID: projectID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(heartbeats) else { return }
        let url = taskWorkerHeartbeatsFileURL(projectID: projectID, taskID: taskID)
        try? data.write(to: url, options: .atomic)
    }

    func normalizedOptionalTaskRunValue(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func taskRunOutcome(forStatus status: String) -> ProjectTaskRunOutcome? {
        switch ProjectTaskStatus(rawValue: status) {
        case .done:
            return .completed
        case .needsReview:
            return .needsReview
        case .blocked:
            return .blocked
        case .waitingInput:
            return .waitingInput
        case .cancelled:
            return .reclaimed
        case .pendingApproval, .backlog, .ready, .inProgress, .none:
            return nil
        }
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
        await emitTaskStatusNotificationIfNeeded(
            projectID: projectID,
            taskID: taskID,
            status: newStatus,
            source: source
        )
    }

    func appendSystemTaskComment(projectID: String, taskID: String, content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = await addTaskComment(
            projectID: projectID,
            taskID: taskID,
            request: TaskCommentCreateRequest(content: trimmed, authorActorId: "system")
        )
    }

    func appendSystemTaskComment(taskID: String, content: String) async {
        let projects = await store.listProjects()
        guard let project = projects.first(where: { project in
            project.tasks.contains(where: { $0.id == taskID })
        }) else {
            return
        }
        await appendSystemTaskComment(projectID: project.id, taskID: taskID, content: content)
    }

    func emitTaskStatusNotificationIfNeeded(
        projectID: String,
        taskID: String,
        status: String,
        source: String
    ) async {
        guard let taskStatus = ProjectTaskStatus(rawValue: status) else {
            return
        }
        guard let project = await store.project(id: projectID),
              let task = project.tasks.first(where: { $0.id == taskID })
        else {
            return
        }

        let message = "\(task.id): \(task.title)"
        switch taskStatus {
        case .done:
            await notificationService.pushTaskCompleted(
                title: "Task completed",
                message: message,
                taskId: task.id,
                projectId: project.id,
                source: source
            )
        case .waitingInput:
            await notificationService.pushInputRequired(
                title: "Input required",
                message: message,
                taskId: task.id,
                projectId: project.id,
                source: source
            )
        case .needsReview:
            await notificationService.pushInputRequired(
                title: "Task needs review",
                message: message,
                taskId: task.id,
                projectId: project.id,
                source: source
            )
        case .blocked:
            await notificationService.push(DashboardNotification(
                type: .agentError,
                title: "Task blocked",
                message: message,
                metadata: [
                    "taskId": task.id,
                    "projectId": project.id,
                    "source": source
                ]
            ))
        case .pendingApproval, .backlog, .ready, .inProgress, .cancelled:
            break
        }
    }

    func markTaskWaitingInputForAgentSession(
        agentID: String,
        sessionID: String,
        reason: String,
        source: String
    ) async {
        guard let taskID = taskIDForAgentSession(agentID: agentID, sessionID: sessionID) else {
            return
        }
        let projects = await store.listProjects()
        for var project in projects {
            guard let taskIndex = project.tasks.firstIndex(where: { $0.id == taskID }) else {
                continue
            }
            var task = project.tasks[taskIndex]
            let previousStatus = task.status
            guard ProjectTaskStatus(rawValue: previousStatus)?.isTerminal != true,
                  previousStatus != ProjectTaskStatus.waitingInput.rawValue
            else {
                return
            }
            task.status = ProjectTaskStatus.waitingInput.rawValue
            task.updatedAt = Date()
            let note = "Waiting for user input: \(reason)"
            if task.description.isEmpty {
                task.description = note
            } else if !task.description.contains(note) {
                task.description += "\n\n\(note)"
            }
            project.tasks[taskIndex] = task
            project.updatedAt = Date()
            await store.saveProject(project)
            await kanbanEventService.push(KanbanEvent(type: .taskUpdated, projectId: project.id, task: task))
            await recordSystemStatusChange(
                projectID: project.id,
                taskID: task.id,
                from: previousStatus,
                to: task.status,
                source: source
            )
            return
        }
    }

    func taskIDForAgentSession(agentID: String, sessionID: String) -> String? {
        guard let detail = try? sessionStore.loadSession(agentID: agentID, sessionID: sessionID) else {
            return nil
        }
        let prefix = "task-"
        guard detail.summary.title.hasPrefix(prefix) else {
            return nil
        }
        let taskID = String(detail.summary.title.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return taskID.isEmpty ? nil : taskID
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

    func listTaskLifecycleLogEntries(projectID: String, taskID: String) -> [TaskLogEntry] {
        let url = projectTaskLogFileURL(projectID: projectID, taskID: taskID)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return text
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, rawLine in
                parseTaskLifecycleLogLine(String(rawLine), taskID: taskID, fallbackIndex: index)
            }
    }

    func parseTaskLifecycleLogLine(_ line: String, taskID: String, fallbackIndex: Int) -> TaskLogEntry? {
        guard line.hasPrefix("["),
              let close = line.firstIndex(of: "]")
        else {
            return nil
        }

        let timestampText = String(line[line.index(after: line.startIndex)..<close])
        let createdAt = ISO8601DateFormatter().date(from: timestampText) ?? Date()
        let restStart = line.index(after: close)
        let body = line[restStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        let messagePrefix = " message="
        let message: String?
        let fieldsText: String
        if let range = body.range(of: messagePrefix) {
            fieldsText = String(body[..<range.lowerBound])
            message = String(body[range.upperBound...])
        } else {
            fieldsText = body
            message = nil
        }

        var values: [String: String] = [:]
        for token in fieldsText.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0]] = parts[1]
        }
        let stage = values["stage"] ?? "lifecycle"
        return TaskLogEntry(
            id: "lifecycle-\(timestampText)-\(fallbackIndex)",
            taskId: values["task"] ?? taskID,
            kind: "lifecycle",
            title: stage.replacingOccurrences(of: "_", with: " "),
            message: message,
            actorId: values["actor"],
            agentId: values["agent"],
            channelId: values["channel"],
            workerId: values["worker"],
            createdAt: createdAt
        )
    }

}
