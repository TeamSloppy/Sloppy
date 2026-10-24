import Foundation
import Protocols

extension CoreService {
    func executeWorkflowAgentNode(
        node: WorkflowNode, context: WorkflowRunner.Context, input: [String: JSONValue]
    ) async -> ToolInvocationResult {
        let config = node.config
        func value(_ key: String) -> String? {
            let text = config[key]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
        func failure(_ code: String, _ message: String, data: [String: JSONValue] = [:]) -> ToolInvocationResult {
            ToolInvocationResult(tool: "workflow.agent", ok: false, data: .object(data),
                                 error: ToolErrorPayload(code: code, message: message, retryable: false))
        }
        guard let agentID = value("agentId"), let prompt = value("prompt") else {
            return failure("workflow_agent_invalid", "Agent step requires agentId and a nonempty prompt.")
        }
        let blockKind = value("blockKind") ?? value("block_kind") ?? "agent"
        guard ["agent", "agent_step", "ai_transform"].contains(blockKind), value("sessionId") == nil else {
            return failure("workflow_agent_unsupported", "This step requires a supported agent block and a new session; existing-session continuation is not implemented.")
        }
        guard let mode = AgentChatMode(rawValue: value("mode") ?? "auto") else {
            return failure("workflow_agent_invalid", "Invalid agent chat mode.")
        }
        let effort = value("reasoningEffort").flatMap(ReasoningEffort.init(rawValue:))
        if value("reasoningEffort") != nil && effort == nil {
            return failure("workflow_agent_invalid", "Invalid reasoningEffort.")
        }
        var output: [String: JSONValue] = ["agentId": .string(agentID)]
        do {
            try Task.checkCancellation()
            let session = try await createAgentSession(agentID: agentID, request: AgentSessionCreateRequest(
                title: "Workflow: \(node.title)", separateChat: true,
                projectId: context.projectId, taskId: context.taskId
            ))
            output["sessionId"] = .string(session.id)
            if let runID = context.runId, let stepID = context.stepId {
                await store.saveWorkflowRunStep(WorkflowRunStep(
                    id: stepID, runId: runID, nodeId: node.id, status: .running,
                    input: input, output: output, startedAt: context.stepStartedAt ?? Date()
                ))
            }
            let encodedInput = try JSONEncoder().encode(input)
            let content = resolveWorkflowTemplateString(prompt, input: input)
                + "\n\n[Workflow input]\n" + String(decoding: encodedInput, as: UTF8.self)
            let response = try await postAgentSessionMessage(
                agentID: agentID, sessionID: session.id,
                request: AgentSessionPostMessageRequest(
                    userId: "workflow", content: content, reasoningEffort: effort,
                    selectedModel: value("model"), mode: mode
                )
            )
            try Task.checkCancellation()
            return Self.workflowAgentResult(response: response, output: output)
        } catch {
            return failure(Task.isCancelled ? "workflow_agent_cancelled" : "workflow_agent_failed",
                           "Agent step failed: \(error)", data: output)
        }
    }

    static func workflowAgentResult(response: AgentSessionMessageResponse, output: [String: JSONValue]) -> ToolInvocationResult {
        let status = response.appendedEvents.compactMap(\.runStatus).last
        let outcome = status?.executionOutcome
        var data = output
        data["agentOutcome"] = outcome.map { .string($0.state.rawValue) } ?? .null
        data["model"] = status?.selectedModel.map(JSONValue.string) ?? .null
        if let text = response.appendedEvents.compactMap(\.message).last(where: { $0.role == .assistant }) {
            data["text"] = .string(text.segments.filter { $0.kind == .text }.compactMap(\.text).joined(separator: "\n"))
        }
        guard status?.stage == .done, outcome?.state == .completed else {
            data["agentStage"] = status.map { .string($0.stage.rawValue) } ?? .null
            return ToolInvocationResult(
                tool: "workflow.agent", ok: false, data: .object(data),
                error: ToolErrorPayload(code: outcome?.code ?? "workflow_agent_incomplete",
                                        message: status?.details ?? "Agent did not report a completed execution outcome.",
                                        retryable: outcome?.retryable ?? false)
            )
        }
        return ToolInvocationResult(tool: "workflow.agent", ok: true, data: .object(data))
    }
}
