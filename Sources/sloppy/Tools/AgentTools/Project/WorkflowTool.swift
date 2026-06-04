import AnyLanguageModel
import Foundation
import Protocols

struct WorkflowTool: CoreTool {
    let domain = "project"
    let title = "Plan and run project workflow"
    let status = "experimental"
    let name = "project.workflow"
    let description = "Create, start, link, and inspect project-scoped visual workflows. Use only when the built-in workflow skill is active."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "operation", description: "Operation: propose, start, link_agent_step, status.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "projectId", description: "Project ID.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "taskId", description: "Optional project task ID.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "workflowId", description: "Workflow definition ID for update/start/status/link operations.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "runId", description: "Workflow run ID for status operations.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "nodeId", description: "Workflow node ID for link_agent_step.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "name", description: "Workflow name for propose.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "rationale", description: "Short rationale for the visual workflow plan.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "lanes", description: "Workflow lanes.", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "nodes", description: "Workflow nodes.", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "edges", description: "Workflow edges.", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "startedBy", description: "Actor starting the workflow run.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "agentId", description: "Agent ID to link to an agent_step node.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "sessionId", description: "Agent session ID to link to an agent_step node.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "delegatedTaskId", description: "Delegated task ID to link to an agent_step node.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "agentStatus", description: "Typed status for linked agent work.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.projectService else {
            return toolFailure(tool: name, code: "not_available", message: "Project service not available.", retryable: false)
        }

        let operation = stringArgument(arguments, "operation", default: "status")
        let projectID = trimmedStringArgument(arguments, "projectId") ?? context.currentProjectID ?? ""
        guard !projectID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`projectId` is required.", retryable: false)
        }

        switch operation {
        case "propose":
            return await propose(arguments: arguments, projectID: projectID, service: svc)
        case "start":
            return await start(arguments: arguments, projectID: projectID, service: svc, context: context)
        case "link_agent_step":
            return await linkAgentStep(arguments: arguments, projectID: projectID, service: svc)
        case "status":
            return await status(arguments: arguments, projectID: projectID, service: svc)
        default:
            return toolFailure(tool: name, code: "invalid_operation", message: "Unsupported workflow operation.", retryable: false)
        }
    }

    private func propose(
        arguments: [String: JSONValue],
        projectID: String,
        service: any ProjectToolService
    ) async -> ToolInvocationResult {
        do {
            let request = try workflowRequest(arguments: arguments)
            let draft = WorkflowDefinition(
                id: trimmedStringArgument(arguments, "workflowId") ?? "draft",
                projectId: projectID,
                name: request.name,
                lanes: request.lanes,
                nodes: request.nodes,
                edges: request.edges,
                enabled: request.enabled
            )
            let issues = service.validateWorkflowDefinition(draft)
            let blockingIssues = issues.filter { $0.severity == "error" }
            guard blockingIssues.isEmpty else {
                return ToolInvocationResult(
                    tool: name,
                    ok: false,
                    data: .object(["validationIssues": .array(blockingIssues.map(issueJSON))]),
                    error: ToolErrorPayload(code: "validation_failed", message: "Workflow graph is invalid.", retryable: false)
                )
            }

            let definition: WorkflowDefinition
            if let workflowID = trimmedStringArgument(arguments, "workflowId") {
                definition = try await service.updateWorkflowDefinition(projectID: projectID, workflowID: workflowID, request: request)
            } else {
                definition = try await service.createWorkflowDefinition(projectID: projectID, request: request)
            }
            return toolSuccess(tool: name, data: responseJSON(projectID: projectID, workflowID: definition.id, runID: nil, issues: issues))
        } catch {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Invalid workflow proposal payload.", retryable: false)
        }
    }

    private func start(
        arguments: [String: JSONValue],
        projectID: String,
        service: any ProjectToolService,
        context: ToolContext
    ) async -> ToolInvocationResult {
        guard let workflowID = trimmedStringArgument(arguments, "workflowId") else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`workflowId` is required.", retryable: false)
        }
        let startedBy = trimmedStringArgument(arguments, "startedBy") ?? "agent:\(context.agentID)"
        let input = arguments["input"]?.asObject ?? [:]
        do {
            let detail = try await service.startWorkflowRun(
                projectID: projectID,
                workflowID: workflowID,
                request: WorkflowRunCreateRequest(
                    taskId: trimmedStringArgument(arguments, "taskId"),
                    startedBy: startedBy,
                    input: input
                )
            )
            return toolSuccess(tool: name, data: responseJSON(projectID: projectID, workflowID: workflowID, runID: detail.run.id, issues: []))
        } catch {
            return toolFailure(tool: name, code: "start_failed", message: "Failed to start workflow run.", retryable: true)
        }
    }

    private func linkAgentStep(
        arguments: [String: JSONValue],
        projectID: String,
        service: any ProjectToolService
    ) async -> ToolInvocationResult {
        guard let workflowID = trimmedStringArgument(arguments, "workflowId"),
              let nodeID = trimmedStringArgument(arguments, "nodeId")
        else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`workflowId` and `nodeId` are required.", retryable: false)
        }

        do {
            let definition = try await service.getWorkflowDefinition(projectID: projectID, workflowID: workflowID)
            var didLink = false
            let nodes = definition.nodes.map { node -> WorkflowNode in
                guard node.id == nodeID, node.type == .agentStep else { return node }
                var next = node
                var config = next.config
                if let agentID = trimmedStringArgument(arguments, "agentId") {
                    config["agentId"] = .string(agentID)
                }
                if let sessionID = trimmedStringArgument(arguments, "sessionId") {
                    config["sessionId"] = .string(sessionID)
                }
                if let delegatedTaskID = trimmedStringArgument(arguments, "delegatedTaskId") {
                    config["delegatedTaskId"] = .string(delegatedTaskID)
                }
                if let agentStatus = trimmedStringArgument(arguments, "agentStatus") {
                    config["agentStatus"] = .string(agentStatus)
                }
                next.config = config
                didLink = true
                return next
            }
            guard didLink else {
                return toolFailure(tool: name, code: "node_not_found", message: "Agent step node was not found.", retryable: false)
            }
            let updated = try await service.updateWorkflowDefinition(
                projectID: projectID,
                workflowID: workflowID,
                request: WorkflowDefinitionUpsertRequest(
                    name: definition.name,
                    lanes: definition.lanes,
                    nodes: nodes,
                    edges: definition.edges,
                    enabled: definition.enabled
                )
            )
            return toolSuccess(tool: name, data: responseJSON(projectID: projectID, workflowID: updated.id, runID: nil, issues: []))
        } catch {
            return toolFailure(tool: name, code: "link_failed", message: "Failed to link agent step.", retryable: true)
        }
    }

    private func status(
        arguments: [String: JSONValue],
        projectID: String,
        service: any ProjectToolService
    ) async -> ToolInvocationResult {
        do {
            if let runID = trimmedStringArgument(arguments, "runId") {
                let detail = try await service.getWorkflowRunDetail(projectID: projectID, runID: runID)
                return toolSuccess(tool: name, data: responseJSON(projectID: projectID, workflowID: detail.run.workflowId, runID: detail.run.id, issues: []))
            }
            if let workflowID = trimmedStringArgument(arguments, "workflowId") {
                _ = try await service.getWorkflowDefinition(projectID: projectID, workflowID: workflowID)
                return toolSuccess(tool: name, data: responseJSON(projectID: projectID, workflowID: workflowID, runID: nil, issues: []))
            }
            let definitions = try await service.listWorkflowDefinitions(projectID: projectID)
            return toolSuccess(tool: name, data: .object([
                "projectId": .string(projectID),
                "workflows": .array(definitions.map { definition in
                    .object([
                        "workflowId": .string(definition.id),
                        "name": .string(definition.name),
                        "definitionUrl": .string(definitionURL(projectID: projectID, workflowID: definition.id))
                    ])
                })
            ]))
        } catch {
            return toolFailure(tool: name, code: "status_failed", message: "Failed to read workflow status.", retryable: true)
        }
    }

    private func workflowRequest(arguments: [String: JSONValue]) throws -> WorkflowDefinitionUpsertRequest {
        WorkflowDefinitionUpsertRequest(
            name: stringArgument(arguments, "name", default: "Agent Workflow"),
            lanes: try workflowLanes(from: arguments["lanes"]),
            nodes: try workflowNodes(from: arguments["nodes"]),
            edges: try workflowEdges(from: arguments["edges"]),
            enabled: arguments["enabled"]?.asBool ?? true
        )
    }

    private func workflowLanes(from value: JSONValue?) throws -> [WorkflowLane] {
        try arrayObjects(value).map { object in
            guard let id = object["id"]?.asString,
                  let title = object["title"]?.asString,
                  let kindRaw = object["kind"]?.asString,
                  let kind = WorkflowLaneKind(rawValue: kindRaw)
            else {
                throw WorkflowToolParseError.invalidPayload
            }
            return WorkflowLane(
                id: id,
                title: title,
                kind: kind,
                actorId: object["actorId"]?.asString,
                teamId: object["teamId"]?.asString
            )
        }
    }

    private func workflowNodes(from value: JSONValue?) throws -> [WorkflowNode] {
        try arrayObjects(value).map { object in
            guard let id = object["id"]?.asString,
                  let typeRaw = object["type"]?.asString,
                  let type = WorkflowNodeType(rawValue: typeRaw),
                  let title = object["title"]?.asString,
                  let laneID = object["laneId"]?.asString
            else {
                throw WorkflowToolParseError.invalidPayload
            }
            return WorkflowNode(
                id: id,
                type: type,
                title: title,
                laneId: laneID,
                config: object["config"]?.asObject ?? [:],
                positionX: object["positionX"]?.asNumber ?? 0,
                positionY: object["positionY"]?.asNumber ?? 0
            )
        }
    }

    private func workflowEdges(from value: JSONValue?) throws -> [WorkflowEdge] {
        try arrayObjects(value).map { object in
            guard let id = object["id"]?.asString,
                  let sourceNodeID = object["sourceNodeId"]?.asString,
                  let targetNodeID = object["targetNodeId"]?.asString
            else {
                throw WorkflowToolParseError.invalidPayload
            }
            return WorkflowEdge(
                id: id,
                sourceNodeId: sourceNodeID,
                targetNodeId: targetNodeID,
                conditionKey: object["conditionKey"]?.asString
            )
        }
    }

    private func arrayObjects(_ value: JSONValue?) throws -> [[String: JSONValue]] {
        guard let values = value?.asArray else { return [] }
        return try values.map { value in
            guard let object = value.asObject else {
                throw WorkflowToolParseError.invalidPayload
            }
            return object
        }
    }

    private func responseJSON(projectID: String, workflowID: String, runID: String?, issues: [WorkflowValidationIssue]) -> JSONValue {
        .object([
            "projectId": .string(projectID),
            "workflowId": .string(workflowID),
            "runId": runID.map(JSONValue.string) ?? .null,
            "definitionUrl": .string(definitionURL(projectID: projectID, workflowID: workflowID)),
            "runUrl": runID.map { .string(runURL(projectID: projectID, runID: $0)) } ?? .null,
            "validationIssues": .array(issues.map(issueJSON))
        ])
    }

    private func issueJSON(_ issue: WorkflowValidationIssue) -> JSONValue {
        .object([
            "severity": .string(issue.severity),
            "message": .string(issue.message),
            "nodeId": issue.nodeId.map(JSONValue.string) ?? .null
        ])
    }

    private func definitionURL(projectID: String, workflowID: String) -> String {
        "/projects/\(projectID)/workflows/\(workflowID)"
    }

    private func runURL(projectID: String, runID: String) -> String {
        "/projects/\(projectID)/workflow-runs/\(runID)"
    }
}

private enum WorkflowToolParseError: Error {
    case invalidPayload
}
