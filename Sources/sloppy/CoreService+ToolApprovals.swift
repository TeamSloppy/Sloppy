import Foundation
import PluginSDK
import Protocols

// MARK: - Tool Approvals

extension CoreService: ToolApprovalBridge {
    public func listPendingToolApprovals() async -> [ToolApprovalRecord] {
        await toolApprovalService.listPending()
    }

    public func approveToolApproval(id: String, decidedBy: String?) async -> ToolApprovalRecord? {
        guard let record = await toolApprovalService.approve(id: id, decidedBy: decidedBy) else {
            return nil
        }
        _ = await channelDelivery.updateToolApproval(record)
        return record
    }

    public func rejectToolApproval(id: String, decidedBy: String?) async -> ToolApprovalRecord? {
        guard let record = await toolApprovalService.reject(id: id, decidedBy: decidedBy) else {
            return nil
        }
        _ = await channelDelivery.updateToolApproval(record)
        return record
    }

    public func resolveToolApproval(id: String, approved: Bool, decidedBy: String?) async -> ToolApprovalRecord? {
        if approved {
            return await approveToolApproval(id: id, decidedBy: decidedBy)
        }
        return await rejectToolApproval(id: id, decidedBy: decidedBy)
    }

    func requestToolApprovalIfNeeded(
        agentID: String,
        sessionID: String?,
        channelID: String?,
        topicID: String?,
        request: ToolInvocationRequest,
        requireApproval: Bool
    ) async -> ToolApprovalWaitResult? {
        guard requireApproval, requiresHumanApproval(toolID: request.tool, arguments: request.arguments) else {
            return nil
        }

        let record = await toolApprovalService.createPending(
            agentId: agentID,
            sessionId: sessionID,
            channelId: channelID,
            topicId: topicID,
            request: request
        )
        _ = await channelDelivery.presentToolApproval(record)
        let result = await toolApprovalService.waitForDecision(id: record.id)
        if case .timedOut(let timedOut) = result {
            _ = await channelDelivery.updateToolApproval(timedOut)
        }
        return result
    }

    func toolApprovalDeniedResult(tool: String, approval: ToolApprovalWaitResult) -> ToolInvocationResult? {
        switch approval {
        case .approved:
            return nil
        case .rejected(let record):
            return ToolInvocationResult(
                tool: tool,
                ok: false,
                data: .object([
                    "approvalId": .string(record.id),
                    "status": .string(record.status.rawValue)
                ]),
                error: ToolErrorPayload(
                    code: "tool_approval_rejected",
                    message: "Tool call was rejected by a human approver.",
                    retryable: false
                )
            )
        case .timedOut(let record):
            return ToolInvocationResult(
                tool: tool,
                ok: false,
                data: .object([
                    "approvalId": .string(record.id),
                    "status": .string(ToolApprovalStatus.timedOut.rawValue)
                ]),
                error: ToolErrorPayload(
                    code: "tool_approval_timeout",
                    message: "Tool approval timed out before a human approved it.",
                    retryable: false
                )
            )
        }
    }

    func requiresHumanApproval(toolID rawToolID: String, arguments: [String: JSONValue]) -> Bool {
        let toolID = rawToolID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !toolID.isEmpty else { return false }

        let exactRisky: Set<String> = [
            "files.write",
            "files.edit",
            "runtime.exec",
            "project.create",
            "project.update",
            "project.delete",
            "project.task_create",
            "project.task_update",
            "project.task_cancel",
            "project.task_clarification_create",
            "project.escalate_to_user",
            "project.meta_memory_set",
            "memory.save",
            "messages.send",
            "sessions.spawn",
            "agents.delegate_task",
            "agent.documents.set_user_markdown",
            "agent.documents.set_memory_markdown",
            "branches.spawn",
            "workers.spawn",
            "workers.route",
            "actor.discuss_with_actor",
            "actor.conclude_discussion",
            "skills.install",
            "skills.uninstall",
            "cron",
            "mcp.call_tool",
            "mcp.save_server",
            "mcp.remove_server",
            "mcp.install_server",
            "mcp.uninstall_server"
        ]
        if exactRisky.contains(toolID) {
            return true
        }

        if toolID == "runtime.process" {
            let action = arguments["action"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return action == nil || action == "start" || action == "stop"
        }

        if toolID.hasPrefix("mcp.") {
            let safeTools: Set<String> = [
                "mcp.list_servers",
                "mcp.list_tools",
                "mcp.list_resources",
                "mcp.read_resource",
                "mcp.list_prompts",
                "mcp.get_prompt"
            ]
            return !safeTools.contains(toolID)
        }

        return false
    }
}
