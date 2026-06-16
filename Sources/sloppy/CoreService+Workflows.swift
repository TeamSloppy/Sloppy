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
            },
            executeTool: { [weak self] node, context, input in
                await self?.executeWorkflowToolNode(node: node, context: context, input: input)
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
            },
            executeTool: { [weak self] node, context, input in
                await self?.executeWorkflowToolNode(node: node, context: context, input: input)
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

    private func executeWorkflowToolNode(
        node: WorkflowNode,
        context: WorkflowRunner.Context,
        input: [String: JSONValue]
    ) async -> ToolInvocationResult? {
        guard let request = workflowToolInvocationRequest(node: node, context: context, input: input) else {
            return nil
        }
        if let workflowError = stringValue(request.arguments["__workflow_error"]) {
            return ToolInvocationResult(
                tool: request.tool,
                ok: false,
                error: ToolErrorPayload(code: "workflow_block_invalid", message: workflowError, retryable: false)
            )
        }
        guard let agentID = workflowAgentID(startedBy: context.startedBy),
              let sessionID = workflowSessionID(node: node, context: context)
        else {
            return ToolInvocationResult(
                tool: request.tool,
                ok: false,
                error: ToolErrorPayload(
                    code: "workflow_tool_context_missing",
                    message: "Workflow executable block requires an agent run with sessionId.",
                    retryable: false
                )
            )
        }
        return await invokeToolFromRuntime(
            agentID: agentID,
            sessionID: sessionID,
            request: request,
            recordSessionEvents: true,
            requireApproval: false,
            chatMode: nil
        )
    }

    private func workflowToolInvocationRequest(
        node: WorkflowNode,
        context: WorkflowRunner.Context,
        input: [String: JSONValue]
    ) -> ToolInvocationRequest? {
        let blockKind = stringValue(node.config["blockKind"]) ?? stringValue(node.config["block_kind"]) ?? node.type.rawValue
        switch blockKind {
        case "bash":
            guard let command = stringValue(node.config["command"]) else {
                return workflowInvalidToolRequest(tool: "runtime.exec", message: "`command` is required for bash workflow block.")
            }
            return ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: [
                    "command": .string("bash"),
                    "arguments": .array([.string("-lc"), .string(command)]),
                    "cwd": node.config["cwd"] ?? input["cwd"] ?? .null
                ],
                reason: "Workflow node \(node.id): \(node.title)"
            )

        case "code":
            let language = (stringValue(node.config["language"]) ?? "javascript").lowercased()
            let source = stringValue(node.config["source"])
            let filePath = stringValue(node.config["filePath"])
            let command: String
            let arguments: [JSONValue]
            if let filePath {
                command = language == "python" ? "python3" : "node"
                arguments = [.string(filePath)]
            } else if let source {
                command = language == "python" ? "python3" : "node"
                arguments = [.string(language == "python" ? "-c" : "-e"), .string(source)]
            } else {
                return workflowInvalidToolRequest(tool: "runtime.exec", message: "`source` or `filePath` is required for code workflow block.")
            }
            return ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: [
                    "command": .string(command),
                    "arguments": .array(arguments),
                    "cwd": node.config["cwd"] ?? input["cwd"] ?? .null
                ],
                reason: "Workflow node \(node.id): \(node.title)"
            )

        case "web_request":
            guard let url = stringValue(node.config["url"]) else {
                return workflowInvalidToolRequest(tool: "web.request", message: "`url` is required for web request workflow block.")
            }
            return ToolInvocationRequest(
                tool: "web.request",
                arguments: [
                    "url": .string(url),
                    "method": .string((stringValue(node.config["method"]) ?? "GET").uppercased()),
                    "headers": node.config["headers"] ?? .object([:]),
                    "body": node.config["body"] ?? .null
                ],
                reason: "Workflow node \(node.id): \(node.title)"
            )

        case "tool":
            guard let toolName = stringValue(node.config["toolName"]) else {
                return workflowInvalidToolRequest(tool: "project.workflow", message: "`toolName` is required for tool workflow block.")
            }
            return ToolInvocationRequest(
                tool: toolName,
                arguments: workflowArguments(from: node.config["arguments"]),
                reason: "Workflow node \(node.id): \(node.title)"
            )

        case "sub_workflow":
            guard let workflowID = stringValue(node.config["workflowId"]) else {
                return workflowInvalidToolRequest(tool: "project.workflow", message: "`workflowId` is required for sub-workflow block.")
            }
            return ToolInvocationRequest(
                tool: "project.workflow",
                arguments: [
                    "operation": .string("start"),
                    "projectId": .string(context.projectId),
                    "workflowId": .string(workflowID),
                    "taskId": context.taskId.map(JSONValue.string) ?? .null
                ],
                reason: "Workflow node \(node.id): \(node.title)"
            )

        default:
            return nil
        }
    }

    private func workflowInvalidToolRequest(tool: String, message: String) -> ToolInvocationRequest {
        ToolInvocationRequest(
            tool: tool,
            arguments: ["__workflow_error": .string(message)],
            reason: message
        )
    }

    private func workflowAgentID(startedBy: String) -> String? {
        let trimmed = startedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("agent:") else {
            return nil
        }
        let id = String(trimmed.dropFirst("agent:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private func workflowSessionID(node: WorkflowNode, context: WorkflowRunner.Context) -> String? {
        let sessionID = stringValue(node.config["sessionId"]) ?? stringValue(context.input["sessionId"])
        return sessionID
    }

    private func workflowArguments(from value: JSONValue?) -> [String: JSONValue] {
        if let object = value?.asObject {
            return object
        }
        guard let raw = stringValue(value),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = decoded.asObject
        else {
            return [:]
        }
        return object
    }

    private func stringValue(_ value: JSONValue?) -> String? {
        guard case .string(let raw)? = value else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
