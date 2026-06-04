import Foundation
import Protocols

extension CoreService {
    public enum WorkflowError: Error {
        case invalidPayload
        case workflowNotFound
        case runNotFound
        case actionNotFound
        case validationFailed([WorkflowValidationIssue])
        case projectNotFound
        case storageFailure
    }

    public func listWorkflowDefinitions(projectID: String) async throws -> [WorkflowDefinition] {
        _ = try await getProject(id: projectID)
        return try workflowDefinitionStore.list(projectID: projectID)
    }

    public func getWorkflowDefinition(projectID: String, workflowID: String) async throws -> WorkflowDefinition {
        _ = try await getProject(id: projectID)
        do {
            return try workflowDefinitionStore.get(projectID: projectID, workflowID: workflowID)
        } catch WorkflowDefinitionFileStore.StoreError.notFound {
            throw WorkflowError.workflowNotFound
        } catch WorkflowDefinitionFileStore.StoreError.invalidPayload {
            throw WorkflowError.invalidPayload
        } catch {
            throw WorkflowError.storageFailure
        }
    }

    public func createWorkflowDefinition(projectID: String, request: WorkflowDefinitionUpsertRequest) async throws -> WorkflowDefinition {
        _ = try await getProject(id: projectID)
        let definition: WorkflowDefinition
        do {
            definition = try workflowDefinitionStore.create(projectID: projectID, request: request)
        } catch WorkflowDefinitionFileStore.StoreError.invalidPayload {
            throw WorkflowError.invalidPayload
        } catch {
            throw WorkflowError.storageFailure
        }
        let issues = validateWorkflowDefinition(definition).filter { $0.severity == "error" }
        guard issues.isEmpty else {
            try? workflowDefinitionStore.delete(projectID: projectID, workflowID: definition.id)
            throw WorkflowError.validationFailed(issues)
        }
        return definition
    }

    public func updateWorkflowDefinition(projectID: String, workflowID: String, request: WorkflowDefinitionUpsertRequest) async throws -> WorkflowDefinition {
        _ = try await getProject(id: projectID)
        do {
            let updated = try workflowDefinitionStore.update(projectID: projectID, workflowID: workflowID, request: request)
            let issues = validateWorkflowDefinition(updated).filter { $0.severity == "error" }
            guard issues.isEmpty else {
                throw WorkflowError.validationFailed(issues)
            }
            return updated
        } catch let error as WorkflowError {
            throw error
        } catch WorkflowDefinitionFileStore.StoreError.notFound {
            throw WorkflowError.workflowNotFound
        } catch WorkflowDefinitionFileStore.StoreError.invalidPayload {
            throw WorkflowError.invalidPayload
        } catch {
            throw WorkflowError.storageFailure
        }
    }

    public func deleteWorkflowDefinition(projectID: String, workflowID: String) async throws {
        _ = try await getProject(id: projectID)
        do {
            try workflowDefinitionStore.delete(projectID: projectID, workflowID: workflowID)
        } catch WorkflowDefinitionFileStore.StoreError.notFound {
            throw WorkflowError.workflowNotFound
        } catch WorkflowDefinitionFileStore.StoreError.invalidPayload {
            throw WorkflowError.invalidPayload
        } catch {
            throw WorkflowError.storageFailure
        }
    }

    nonisolated public func validateWorkflowDefinition(_ definition: WorkflowDefinition) -> [WorkflowValidationIssue] {
        WorkflowRunner().validate(definition: definition)
    }

    public func startWorkflowRun(projectID: String, workflowID: String, request: WorkflowRunCreateRequest) async throws -> WorkflowRunDetail {
        _ = try await getProject(id: projectID)
        let definition = try await getWorkflowDefinition(projectID: projectID, workflowID: workflowID)
        guard definition.enabled else {
            throw WorkflowError.invalidPayload
        }
        let issues = validateWorkflowDefinition(definition).filter { $0.severity == "error" }
        guard issues.isEmpty else {
            throw WorkflowError.validationFailed(issues)
        }
        let runner = WorkflowRunner()
        let persistence = WorkflowRunner.Persistence(
            saveRun: { [store] run in await store.saveWorkflowRun(run) },
            saveStep: { [store] step in await store.saveWorkflowRunStep(step) },
            saveAction: { [store] action in await store.saveWorkflowPendingAction(action) }
        )
        _ = await runner.start(
            definition: definition,
            context: .init(projectId: projectID, taskId: request.taskId, startedBy: request.startedBy, input: request.input),
            persistence: persistence,
            updateTask: { [weak self] projectId, taskId, status in
                _ = try await self?.updateProjectTask(
                    projectID: projectId,
                    taskID: taskId,
                    request: ProjectTaskUpdateRequest(status: status, changedBy: "user")
                )
            }
        )
        guard let run = (await store.listWorkflowRuns(projectId: projectID)).first(where: { $0.workflowId == workflowID }) else {
            throw WorkflowError.storageFailure
        }
        return await workflowRunDetail(run: run)
    }

    public func listWorkflowRuns(projectID: String) async -> [WorkflowRun] {
        await store.listWorkflowRuns(projectId: projectID)
    }

    public func getWorkflowRunDetail(projectID: String, runID: String) async throws -> WorkflowRunDetail {
        guard let run = await store.getWorkflowRun(id: runID), run.projectId == projectID else {
            throw WorkflowError.runNotFound
        }
        return await workflowRunDetail(run: run)
    }

    public func listWorkflowPendingActions(projectID: String) async -> [WorkflowPendingAction] {
        await store.listWorkflowPendingActions(projectId: projectID, includeResolved: false)
    }

    public func resolveWorkflowPendingAction(projectID: String, actionID: String, request: WorkflowActionResolveRequest) async throws -> WorkflowRunDetail {
        guard let action = await store.resolveWorkflowPendingAction(actionId: actionID, resolvedAt: Date()),
              action.projectId == projectID
        else {
            throw WorkflowError.actionNotFound
        }
        guard let run = await store.getWorkflowRun(id: action.workflowRunId) else {
            throw WorkflowError.runNotFound
        }
        let definition = try await getWorkflowDefinition(projectID: projectID, workflowID: run.workflowId)
        let output: [String: JSONValue] = [
            "decision": .string(request.decision.rawValue),
            "comment": request.comment.map(JSONValue.string) ?? .null,
            "resolvedBy": .string(request.resolvedBy)
        ]
        let runner = WorkflowRunner()
        let persistence = WorkflowRunner.Persistence(
            saveRun: { [store] run in await store.saveWorkflowRun(run) },
            saveStep: { [store] step in await store.saveWorkflowRunStep(step) },
            saveAction: { [store] action in await store.saveWorkflowPendingAction(action) }
        )
        _ = await runner.resume(
            definition: definition,
            run: run,
            resolvedNodeID: action.nodeId,
            output: output,
            persistence: persistence,
            updateTask: { [weak self] projectId, taskId, status in
                _ = try await self?.updateProjectTask(
                    projectID: projectId,
                    taskID: taskId,
                    request: ProjectTaskUpdateRequest(status: status, changedBy: "user")
                )
            }
        )
        guard let updatedRun = await store.getWorkflowRun(id: run.id) else {
            throw WorkflowError.runNotFound
        }
        return await workflowRunDetail(run: updatedRun)
    }

    private func workflowRunDetail(run: WorkflowRun) async -> WorkflowRunDetail {
        WorkflowRunDetail(
            run: run,
            steps: await store.listWorkflowRunSteps(runId: run.id),
            pendingActions: await store.listWorkflowPendingActions(runId: run.id)
        )
    }
}
