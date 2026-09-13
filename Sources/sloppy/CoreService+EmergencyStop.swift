import Foundation
import Protocols

extension CoreService {
    func registerProjectExecutionSession(sessionID: String, projectID: String, taskID: String, agentID: String, generation: Int? = nil) {
        projectExecutionSessions[sessionID] = (projectID, taskID, agentID, generation ?? projectStopGenerations[projectID, default: 0])
    }

    /// Stops project task executions without dispatching queued work during startup.
    public func emergencyStopProject(projectID: String) async throws -> ProjectEmergencyStopResponse {
        guard let id = normalizedProjectID(projectID) else { throw ProjectError.invalidProjectID }
        guard var project = await store.project(id: id) else { throw ProjectError.notFound }
        projectStopGenerations[id, default: 0] += 1
        for cancel in projectPlanningCancellations[id]?.values ?? [:].values { cancel() }
        project.automaticTaskPickupEnabled = false
        project.updatedAt = Date()
        await store.saveProject(project)
        await waitForStartup(dispatchReadyTasks: false)

        project = await store.project(id: id) ?? project
        let reason = "Project emergency stop requested by user."
        let taskIDs = Set(project.tasks.map(\.id))
        let workers = await runtime.workerSnapshots().filter {
            taskIDs.contains($0.taskId) && ($0.status == .queued || $0.status == .running || $0.status == .waitingInput)
        }
        let sessions = projectExecutionSessions.filter { $0.value.projectID == id }
        let executingIDs = Set(workers.map(\.taskId)).union(sessions.values.map(\.taskID))
        let tasksToStop = project.tasks.filter {
            $0.status != ProjectTaskStatus.cancelled.rawValue && $0.status != ProjectTaskStatus.done.rawValue
                && (executingIDs.contains($0.id) || $0.status == ProjectTaskStatus.inProgress.rawValue
                    || $0.status == ProjectTaskStatus.waitingInput.rawValue)
        }
        var warnings: [String] = []
        let localNodeID = try? nodeConfigStore.load().identity.nodeId
        var cancelledTasks: [(previous: ProjectTask, current: ProjectTask)] = []
        for task in tasksToStop {
            if let nodeID = task.executionNodeId, nodeID != localNodeID {
                warnings.append("Task \(task.id): stop on remote node \(nodeID) is not confirmed.")
                continue
            }
            guard let index = project.tasks.firstIndex(where: { $0.id == task.id }) else { continue }
            var cancelled = task
            cancelled.status = ProjectTaskStatus.cancelled.rawValue
            cancelled.claimedActorId = nil
            cancelled.claimedAgentId = nil
            cancelled.updatedAt = Date()
            cancelled.description += "\n\nCancelled: " + reason
            if cancelled.externalMetadata != nil {
                cancelled.externalMetadata?.origin = "sloppy"
                cancelled.externalMetadata?.syncState = "pending"
            }
            project.tasks[index] = cancelled
            cancelledTasks.append((task, cancelled))
        }
        project.updatedAt = Date()
        // Persist cancellation before worker events arrive, without waiting on external task sync.
        await store.saveProject(project)

        var interrupted = 0
        for (sessionID, execution) in sessions {
            do {
                let response = try await sessionOrchestrator.controlSession(
                    agentID: execution.agentID, sessionID: sessionID,
                    request: AgentSessionControlRequest(action: .interruptTree, requestedBy: "user", reason: reason, interruptPendingInput: true)
                )
                for childID in Set(response.appendedEvents.map(\.sessionId)) {
                    await toolExecution.cleanupSessionProcesses(childID)
                }
                interrupted += 1
            } catch {
                warnings.append("Session \(sessionID): \(error.localizedDescription)")
            }
            // Cleanup remains best effort even when writing the control event fails.
            await toolExecution.cleanupSessionProcesses(sessionID)
        }
        var stopped = 0
        for worker in workers {
            if await runtime.cancelWorker(workerId: worker.workerId, reason: reason) { stopped += 1 }
        }
        for (previous, current) in cancelledTasks {
            await kanbanEventService.push(KanbanEvent(type: .taskUpdated, projectId: id, task: current))
            await recordSystemStatusChange(projectID: id, taskID: current.id, from: previous.status,
                                           to: current.status, source: "emergency_stop")
            _ = await finishLatestTaskRun(projectID: id, taskID: current.id, outcome: .reclaimed,
                                         summary: reason, metadata: ["source": "emergency_stop"])
        }
        guard let saved = await store.project(id: id) else { throw ProjectError.notFound }
        return ProjectEmergencyStopResponse(project: saved, stoppedWorkerCount: stopped,
                                            interruptedSessionCount: interrupted, warnings: warnings)
    }
}
