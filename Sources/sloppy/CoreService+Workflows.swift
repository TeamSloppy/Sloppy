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
        await restoreWorkflowExecutionsIfNeeded()
        guard !workflowIsStopping else { throw CancellationError() }
        _ = try await getProject(id: projectID)
        let definition = try await getWorkflowDefinition(projectID: projectID, workflowID: workflowID)
        guard definition.enabled else {
            throw WorkflowError.invalidPayload
        }
        let issues = validateWorkflowDefinition(definition).filter { $0.severity == "error" }
        guard issues.isEmpty else {
            throw WorkflowError.validationFailed(issues)
        }
        let run = WorkflowRun(id: "run_\(UUID().uuidString.lowercased())", workflowId: definition.id,
                              workflowVersion: definition.version, projectId: projectID, taskId: request.taskId,
                              status: .queued, startedBy: request.startedBy)
        let journal = WorkflowExecutionJournal(state: .init(definition: definition, originalInput: request.input, run: run),
                                               files: workflowExecutionFiles, store: store)
        activeWorkflowRuns.insert(run.id)
        workflowJournals[run.id] = journal
        var ownsExecution = true
        defer { if ownsExecution { releaseWorkflowExecution(run.id) } }
        try await journal.flush()
        if request.background == true {
            releaseWorkflowExecution(run.id)
            ownsExecution = false
            scheduleWorkflowRecovery(run.id)
            return WorkflowRunDetail(run: run)
        }
        _ = await WorkflowRunner().start(
            definition: definition,
            context: .init(projectId: projectID, taskId: request.taskId, startedBy: request.startedBy, input: request.input, runId: run.id),
            persistence: await journal.persistence,
            updateTask: workflowTaskUpdater(),
            executeTool: { [weak self] node, context, input in
                await self?.executeWorkflowToolNode(node: node, context: context, input: input)
            }
        )
        if await journal.suspended { throw CancellationError() }
        guard await !journal.failed else { throw WorkflowError.storageFailure }
        return try await finishWaitingWorkflowAgent(journal: journal)
    }

    public func listWorkflowRuns(projectID: String) async -> [WorkflowRun] {
        await restoreWorkflowExecutionsIfNeeded()
        return await store.listWorkflowRuns(projectId: projectID)
    }

    public func getWorkflowRunDetail(projectID: String, runID: String) async throws -> WorkflowRunDetail {
        await restoreWorkflowExecutionsIfNeeded()
        guard let run = await store.getWorkflowRun(id: runID), run.projectId == projectID else {
            throw WorkflowError.runNotFound
        }
        return await workflowRunDetail(run: run)
    }

    public func listWorkflowPendingActions(projectID: String) async -> [WorkflowPendingAction] {
        await restoreWorkflowExecutionsIfNeeded()
        return await store.listWorkflowPendingActions(projectId: projectID, includeResolved: false)
    }

    public func resolveWorkflowPendingAction(projectID: String, actionID: String, request: WorkflowActionResolveRequest) async throws -> WorkflowRunDetail {
        await restoreWorkflowExecutionsIfNeeded()
        guard !workflowIsStopping else { throw CancellationError() }
        let actions = await store.listWorkflowPendingActions(projectId: projectID, includeResolved: true)
        guard let action = actions.first(where: { $0.id == actionID }) else { throw WorkflowError.actionNotFound }
        guard let run = await store.getWorkflowRun(id: action.workflowRunId), run.projectId == projectID else { throw WorkflowError.runNotFound }
        let journal = try await workflowJournal(run: run)
        let state = await journal.snapshot()
        guard let savedAction = state.actions.first(where: { $0.id == actionID }) else { throw WorkflowError.actionNotFound }
        if savedAction.resolvedAt != nil { return await workflowRunDetail(run: state.run) }
        guard savedAction.decisions.contains(request.decision) else { throw WorkflowError.invalidPayload }
        if state.definition.nodes.first(where: { $0.id == action.nodeId })?.type == .humanInput,
           request.comment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { throw WorkflowError.invalidPayload }
        guard activeWorkflowRuns.insert(run.id).inserted else { throw WorkflowError.invalidPayload }
        workflowJournals[run.id] = journal
        var ownsExecution = true
        defer { if ownsExecution { releaseWorkflowExecution(run.id) } }
        let output: [String: JSONValue] = [
            "decision": .string(request.decision.rawValue),
            "comment": request.comment.map(JSONValue.string) ?? .null,
            "resolvedBy": .string(request.resolvedBy)
        ]
        try await journal.resolve(actionID: actionID, output: output)
        if request.background == true {
            let resolved = await journal.snapshot()
            releaseWorkflowExecution(run.id)
            ownsExecution = false
            scheduleWorkflowRecovery(run.id)
            return WorkflowRunDetail(run: resolved.run, steps: resolved.steps, pendingActions: resolved.actions)
        }
        return try await continueWorkflow(journal: journal, nodeID: action.nodeId, output: output)
    }

    var workflowExecutionFiles: WorkflowExecutionFileStore {
        .init(root: workspaceRootURL.appendingPathComponent("workflow-runs", isDirectory: true))
    }

    func workflowJournal(run: WorkflowRun) async throws -> WorkflowExecutionJournal {
        if let state = try workflowExecutionFiles.load(run.id) {
            return WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
        }
        // Legacy runs can only be upgraded while their exact graph version still exists.
        let definition = try await getWorkflowDefinition(projectID: run.projectId, workflowID: run.workflowId)
        guard definition.version == run.workflowVersion else { throw WorkflowError.validationFailed([
            .init(severity: "error", message: "The original workflow version is unavailable; this run cannot safely resume.")
        ]) }
        let steps = await store.listWorkflowRunSteps(runId: run.id)
        let state = WorkflowExecutionState(definition: definition, originalInput: steps.first?.input["input"]?.asObject ?? [:],
                                           run: run, steps: steps, actions: await store.listWorkflowPendingActions(runId: run.id))
        let journal = WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
        try await journal.flush()
        return journal
    }

    func continueWorkflow(journal: WorkflowExecutionJournal, nodeID: String, output: [String: JSONValue]) async throws -> WorkflowRunDetail {
        let state = await journal.snapshot()
        _ = await WorkflowRunner().resume(
            definition: state.definition, run: state.run, resolvedNodeID: nodeID, output: output,
            persistence: await journal.persistence, updateTask: workflowTaskUpdater(),
            executeTool: { [weak self] node, context, input in
                await self?.executeWorkflowToolNode(node: node, context: context, input: input)
            }, originalInput: state.originalInput, previousSteps: state.steps,
            resolvedStepID: state.steps.last(where: { $0.nodeId == nodeID })?.id
        )
        if await journal.suspended { throw CancellationError() }
        guard await !journal.failed else { throw WorkflowError.storageFailure }
        return try await finishWaitingWorkflowAgent(journal: journal)
    }

    func workflowTaskUpdater() -> @Sendable (String, String, String) async throws -> Void {
        { [weak self] projectId, taskId, status in
            guard let self else { throw WorkflowError.storageFailure }
            _ = try await self.updateProjectTask(projectID: projectId, taskID: taskId,
                request: ProjectTaskUpdateRequest(status: status, changedBy: "user"))
        }
    }

    func workflowRunDetail(run: WorkflowRun) async -> WorkflowRunDetail {
        if let state = try? workflowExecutionFiles.load(run.id) {
            return WorkflowRunDetail(run: state.run, steps: state.steps, pendingActions: state.actions)
        }
        return WorkflowRunDetail(
            run: run,
            steps: await store.listWorkflowRunSteps(runId: run.id),
            pendingActions: await store.listWorkflowPendingActions(runId: run.id)
        )
    }

    func executeWorkflowToolNode(
        node: WorkflowNode,
        context: WorkflowRunner.Context,
        input: [String: JSONValue]
    ) async -> ToolInvocationResult? {
        if node.type == .agentStep {
            return await executeWorkflowAgentNode(node: node, context: context, input: input)
        }
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
        if let agentID = workflowAgentID(startedBy: context.startedBy),
           let sessionID = workflowSessionID(node: node, context: context) {
            return await invokeToolFromRuntime(
                agentID: agentID,
                sessionID: sessionID,
                request: request,
                recordSessionEvents: true,
                requireApproval: false,
                chatMode: nil
            )
        }
        return await invokeStandaloneWorkflowTool(request: request, context: context)
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
            let resolvedCommand = resolveWorkflowTemplateString(command, input: input)
            return ToolInvocationRequest(
                tool: "runtime.exec",
                arguments: [
                    "command": .string("bash"),
                    "arguments": .array([.string("-lc"), .string(resolvedCommand)]),
                    "cwd": node.config["cwd"] ?? input["cwd"] ?? .null
                ],
                reason: "Workflow node \(node.id): \(node.title)"
            )

        case "code":
            let language = (stringValue(node.config["language"]) ?? "javascript").lowercased()
            guard language == "javascript" || language == "python" else {
                return workflowInvalidToolRequest(tool: "runtime.exec", message: "Code blocks currently support javascript and python only.")
            }
            let source = stringValue(node.config["source"]).map { resolveWorkflowTemplateString($0, input: input) }
            let filePath = stringValue(node.config["filePath"]).map { resolveWorkflowTemplateString($0, input: input) }
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
                    "url": .string(resolveWorkflowTemplateString(url, input: input)),
                    "method": .string((stringValue(node.config["method"]) ?? "GET").uppercased()),
                    "headers": resolveWorkflowTemplateValue(node.config["headers"] ?? .object([:]), input: input),
                    "body": resolveWorkflowTemplateValue(node.config["body"] ?? .null, input: input)
                ],
                reason: "Workflow node \(node.id): \(node.title)"
            )

        case "tool":
            guard let toolName = stringValue(node.config["toolName"]) else {
                return workflowInvalidToolRequest(tool: "project.workflow", message: "`toolName` is required for tool workflow block.")
            }
            return ToolInvocationRequest(
                tool: toolName,
                arguments: workflowArguments(from: resolveWorkflowTemplateValue(node.config["arguments"] ?? .object([:]), input: input)),
                reason: "Workflow node \(node.id): \(node.title)"
            )

        case "sub_workflow":
            return workflowInvalidToolRequest(
                tool: "project.workflow",
                message: "Sub-workflow completion tracking is not implemented; a start receipt cannot complete this step."
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

    private func invokeStandaloneWorkflowTool(
        request: ToolInvocationRequest,
        context: WorkflowRunner.Context
    ) async -> ToolInvocationResult {
        let agentID = workflowAgentID(startedBy: context.startedBy) ?? "workflow"
        let sessionID = workflowSessionID(context: context)
        return await toolExecution.invoke(
            agentID: agentID,
            sessionID: sessionID,
            request: request,
            policy: AgentToolsPolicy(),
            currentProjectID: context.projectId
        )
    }

    private func workflowSessionID(context: WorkflowRunner.Context) -> String {
        if let sessionID = stringValue(context.input["sessionId"]) {
            return sessionID
        }
        if let runID = context.runId?.trimmingCharacters(in: .whitespacesAndNewlines), !runID.isEmpty {
            return "workflow-\(runID)"
        }
        return "workflow-\(context.projectId)"
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

func resolveWorkflowTemplateValue(_ value: JSONValue, input: [String: JSONValue]) -> JSONValue {
    switch value {
    case .string(let raw):
        return .string(resolveWorkflowTemplateString(raw, input: input))
    case .array(let values):
        return .array(values.map { resolveWorkflowTemplateValue($0, input: input) })
    case .object(let object):
        return .object(object.mapValues { resolveWorkflowTemplateValue($0, input: input) })
    case .number, .bool, .null:
        return value
    }
}

func resolveWorkflowTemplateString(_ raw: String, input: [String: JSONValue]) -> String {
    var result = ""
    var cursor = raw.startIndex
    while let start = raw[cursor...].range(of: "{{") {
        result += raw[cursor..<start.lowerBound]
        let afterStart = start.upperBound
        guard let end = raw[afterStart...].range(of: "}}") else {
            result += raw[start.lowerBound...]
            return result
        }
        let path = raw[afterStart..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = workflowTemplateValue(path: path, input: input) {
            result += workflowTemplateString(value)
        } else {
            result += raw[start.lowerBound..<end.upperBound]
        }
        cursor = end.upperBound
    }
    result += raw[cursor...]
    return result
}

private func workflowTemplateValue(path: String, input: [String: JSONValue]) -> JSONValue? {
    let parts = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
    guard let first = parts.first, var value = input[first] else {
        return nil
    }
    for part in parts.dropFirst() {
        guard case .object(let object) = value, let next = object[part] else {
            return nil
        }
        value = next
    }
    return value
}

private func workflowTemplateString(_ value: JSONValue) -> String {
    switch value {
    case .string(let raw):
        return raw
    case .number(let number):
        return number.rounded() == number ? String(Int(number)) : String(number)
    case .bool(let bool):
        return bool ? "true" : "false"
    case .null:
        return "null"
    case .array, .object:
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
