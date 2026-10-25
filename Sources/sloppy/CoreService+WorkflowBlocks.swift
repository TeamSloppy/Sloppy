import Foundation
import Protocols

extension CoreService {
    func executeWorkflowTaskNode(context: WorkflowRunner.Context) -> ToolInvocationResult {
        guard context.taskId != nil, let task = context.input["task"]?.asObject else {
            return .init(tool: "workflow.project_task", ok: false, error: .init(code: "workflow_task_required", message: "Select a project task when starting this workflow.", retryable: false))
        }
        return .init(tool: "workflow.project_task", ok: true, data: .object(task))
    }

    func executeWorkflowNotify(node: WorkflowNode, context: WorkflowRunner.Context, input: [String: JSONValue]) async -> ToolInvocationResult {
        func failure(_ code: String, _ message: String) -> ToolInvocationResult {
            .init(tool: "workflow.notify", ok: false, error: .init(code: code, message: message, retryable: false))
        }
        guard let channel = node.config["channelId"]?.asString, let raw = node.config["message"]?.asString,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return failure("workflow_notify_invalid", "Notify requires channelId and message.") }
        do {
            let project = try await getProject(id: context.projectId)
            guard project.channels.contains(where: { $0.channelId == channel }) else { return failure("workflow_notify_invalid", "Notify channel must belong to the workflow project.") }
            let content = resolveWorkflowTemplateString(raw, input: input)
            let delivered = await deliverToChannelPlugin(channelId: channel, userId: "workflow", content: content)
            guard delivered else { return failure("workflow_notify_failed", "The channel plugin did not confirm delivery.") }
            return .init(tool: "workflow.notify", ok: true, data: .object(["channelId": .string(channel), "delivered": .bool(true)]))
        } catch { return failure("workflow_notify_failed", String(describing: error)) }
    }
}
