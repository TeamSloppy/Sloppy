import Foundation
import Protocols

extension CoreService {
    public enum AutomationError: Error {
        case invalidPayload
        case automationNotFound
        case workflowNotFound
        case runNotFound
        case projectNotFound
        case storageFailure
        case disabled
    }

    public func listAutomationDefinitions(projectID: String) async throws -> [AutomationDefinition] {
        _ = try await getProject(id: projectID)
        return try automationDefinitionStore.list(projectID: projectID)
    }

    public func getAutomationDefinition(projectID: String, automationID: String) async throws -> AutomationDefinition {
        _ = try await getProject(id: projectID)
        do {
            return try automationDefinitionStore.get(projectID: projectID, automationID: automationID)
        } catch AutomationDefinitionFileStore.StoreError.notFound {
            throw AutomationError.automationNotFound
        } catch AutomationDefinitionFileStore.StoreError.invalidPayload {
            throw AutomationError.invalidPayload
        } catch {
            throw AutomationError.storageFailure
        }
    }

    public func createAutomationDefinition(projectID: String, request: AutomationDefinitionUpsertRequest) async throws -> AutomationDefinition {
        _ = try await getProject(id: projectID)
        _ = try await getWorkflowDefinition(projectID: projectID, workflowID: request.workflowId)
        do {
            return try automationDefinitionStore.create(projectID: projectID, request: request)
        } catch AutomationDefinitionFileStore.StoreError.invalidPayload {
            throw AutomationError.invalidPayload
        } catch {
            throw AutomationError.storageFailure
        }
    }

    public func updateAutomationDefinition(projectID: String, automationID: String, request: AutomationDefinitionUpsertRequest) async throws -> AutomationDefinition {
        _ = try await getProject(id: projectID)
        _ = try await getWorkflowDefinition(projectID: projectID, workflowID: request.workflowId)
        do {
            return try automationDefinitionStore.update(projectID: projectID, automationID: automationID, request: request)
        } catch AutomationDefinitionFileStore.StoreError.notFound {
            throw AutomationError.automationNotFound
        } catch AutomationDefinitionFileStore.StoreError.invalidPayload {
            throw AutomationError.invalidPayload
        } catch {
            throw AutomationError.storageFailure
        }
    }

    public func deleteAutomationDefinition(projectID: String, automationID: String) async throws {
        _ = try await getProject(id: projectID)
        do {
            try automationDefinitionStore.delete(projectID: projectID, automationID: automationID)
        } catch AutomationDefinitionFileStore.StoreError.notFound {
            throw AutomationError.automationNotFound
        } catch AutomationDefinitionFileStore.StoreError.invalidPayload {
            throw AutomationError.invalidPayload
        } catch {
            throw AutomationError.storageFailure
        }
    }

    public func startAutomationRun(
        projectID: String,
        automationID: String,
        request: AutomationManualRunRequest
    ) async throws -> AutomationRunDetail {
        let payload = AutomationTriggerPayload(
            source: .manual,
            startedBy: request.actorId,
            data: request.input,
            workflowInput: request.input
        )
        return try await triggerAutomation(projectID: projectID, automationID: automationID, payload: payload)
    }

    public func triggerAutomation(
        projectID: String,
        automationID: String,
        payload: AutomationTriggerPayload
    ) async throws -> AutomationRunDetail {
        let automation = try await getAutomationDefinition(projectID: projectID, automationID: automationID)
        guard automation.enabled else {
            throw AutomationError.disabled
        }

        let resolver = AutomationTaskResolver()
        let taskResolution = try await resolver.resolve(
            mode: automation.taskMode,
            projectID: projectID,
            repositoryFullName: automation.repositoryFullName,
            payload: payload,
            service: self
        )

        let workflowDetail = try await startWorkflowRun(
            projectID: projectID,
            workflowID: automation.workflowId,
            request: WorkflowRunCreateRequest(
                taskId: taskResolution.taskId,
                startedBy: payload.startedBy,
                input: mergedWorkflowInput(payload: payload, taskId: taskResolution.taskId)
            )
        )

        let now = Date()
        let run = AutomationRun(
            id: "autorun_\(UUID().uuidString.lowercased())",
            automationId: automation.id,
            projectId: projectID,
            workflowId: automation.workflowId,
            workflowRunId: workflowDetail.run.id,
            repositoryFullName: automation.repositoryFullName,
            triggerType: payload.source,
            triggerEventId: payload.triggerEventId,
            status: .completed,
            taskId: taskResolution.taskId,
            summary: taskResolution.created ? "Created task and started workflow." : "Started workflow.",
            startedAt: now,
            finishedAt: now
        )
        await store.saveAutomationRun(run)
        return AutomationRunDetail(run: run, workflowRun: workflowDetail)
    }

    public func listAutomationRuns(projectID: String) async throws -> [AutomationRun] {
        _ = try await getProject(id: projectID)
        return await store.listAutomationRuns(projectId: projectID)
    }

    public func getAutomationRunDetail(projectID: String, runID: String) async throws -> AutomationRunDetail {
        guard let run = await store.getAutomationRun(id: runID), run.projectId == projectID else {
            throw AutomationError.runNotFound
        }
        let workflowRun = await workflowRunDetail(for: run.workflowRunId)
        return AutomationRunDetail(run: run, workflowRun: workflowRun)
    }

    private func workflowRunDetail(for runID: String?) async -> WorkflowRunDetail? {
        guard let runID, let run = await store.getWorkflowRun(id: runID) else {
            return nil
        }
        return WorkflowRunDetail(
            run: run,
            steps: await store.listWorkflowRunSteps(runId: run.id),
            pendingActions: await store.listWorkflowPendingActions(runId: run.id)
        )
    }

    private func mergedWorkflowInput(payload: AutomationTriggerPayload, taskId: String?) -> [String: JSONValue] {
        var input = payload.workflowInput
        input["source"] = .string(payload.source.rawValue)
        if let triggerEventId = payload.triggerEventId {
            input["triggerEventId"] = .string(triggerEventId)
        }
        if let taskId {
            input["taskId"] = .string(taskId)
        }
        return input
    }
}
