import Foundation
import PluginSDK
import Protocols

// MARK: - Tool Approvals

extension CoreService: ToolApprovalBridge {
    public func listPendingToolApprovals() async -> [ToolApprovalRecord] {
        await toolApprovalService.listPending()
    }

    public func approveToolApproval(id: String, decidedBy: String?) async -> ToolApprovalRecord? {
        await approveToolApproval(id: id, decidedBy: decidedBy, scope: .once)
    }

    public func approveToolApproval(
        id: String,
        decidedBy: String?,
        scope: ToolApprovalDecisionScope
    ) async -> ToolApprovalRecord? {
        guard let record = await toolApprovalService.approve(id: id, decidedBy: decidedBy) else {
            return nil
        }
        if scope == .session {
            rememberToolApprovalSessionAllowance(record)
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
        if isToolApprovalAllowedForSession(
            agentID: agentID,
            sessionID: sessionID,
            channelID: channelID,
            toolID: request.tool
        ) {
            return nil
        }

        let displaySessionID = toolApprovalDisplaySessionID(agentID: agentID, sessionID: sessionID)
        let record = await toolApprovalService.createPending(
            agentId: agentID,
            sessionId: sessionID,
            displaySessionId: displaySessionID,
            channelId: channelID,
            topicId: topicID,
            request: request,
            approvalKind: .riskyTool
        )
        await appendToolApprovalPausedStatusIfNeeded(
            agentID: agentID,
            sessionID: sessionID,
            displaySessionID: displaySessionID,
            record: record
        )
        if let waitingSessionID = displaySessionID ?? sessionID {
            await markTaskWaitingInputForAgentSession(
                agentID: agentID,
                sessionID: waitingSessionID,
                reason: "Tool approval required for \(request.tool).",
                source: "agent"
            )
        }
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

    func requestMissingAccessApproval(
        agentID: String,
        sessionID: String?,
        channelID: String?,
        topicID: String?,
        request: ToolInvocationRequest,
        grants: [ToolApprovalGrant]
    ) async -> ToolApprovalWaitResult {
        let reason = request.reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? request.reason
            : missingAccessApprovalReason(tool: request.tool, grants: grants)
        let approvalRequest = ToolInvocationRequest(
            tool: request.tool,
            arguments: request.arguments,
            reason: reason,
            argumentDiagnostics: request.argumentDiagnostics
        )
        let displaySessionID = toolApprovalDisplaySessionID(agentID: agentID, sessionID: sessionID)
        let record = await toolApprovalService.createPending(
            agentId: agentID,
            sessionId: sessionID,
            displaySessionId: displaySessionID,
            channelId: channelID,
            topicId: topicID,
            request: approvalRequest,
            approvalKind: .missingAccess,
            grants: grants
        )
        await appendToolApprovalPausedStatusIfNeeded(
            agentID: agentID,
            sessionID: sessionID,
            displaySessionID: displaySessionID,
            record: record
        )
        if let waitingSessionID = displaySessionID ?? sessionID {
            await markTaskWaitingInputForAgentSession(
                agentID: agentID,
                sessionID: waitingSessionID,
                reason: "Access approval required for \(request.tool).",
                source: "agent"
            )
        }
        _ = await channelDelivery.presentToolApproval(record)
        let result = await toolApprovalService.waitForDecision(id: record.id)
        if case .timedOut(let timedOut) = result {
            _ = await channelDelivery.updateToolApproval(timedOut)
        }
        return result
    }

    func applyApprovalGrants(
        _ grants: [ToolApprovalGrant],
        to policy: AgentToolsPolicy,
        matchingToolID: String? = nil
    ) -> AgentToolsPolicy {
        var updated = policy
        let requestedToolID = matchingToolID.map(normalizedToolApprovalToolID)
        for grant in grants {
            let toolID = normalizedToolApprovalToolID(grant.tool)
            if let requestedToolID, !requestedToolID.isEmpty, toolID != requestedToolID {
                continue
            }
            switch grant.kind {
            case .tool:
                if !toolID.isEmpty {
                    updated.tools[toolID] = true
                }
            case .directory:
                guard let resource = normalizedApprovalResource(grant.resource), !resource.isEmpty else {
                    continue
                }
                if grant.operation == "exec" {
                    appendUniqueRoot(resource, to: &updated.guardrails.allowedExecRoots)
                } else {
                    appendUniqueRoot(resource, to: &updated.guardrails.allowedWriteRoots)
                }
            }
        }
        return updated
    }

    private func rememberToolApprovalSessionAllowance(_ record: ToolApprovalRecord) {
        guard let scopeID = toolApprovalSessionScopeID(sessionID: record.sessionId, channelID: record.channelId) else {
            return
        }
        let key = toolApprovalSessionAllowanceKey(agentID: record.agentId, scopeID: scopeID)
        var allowedGrants = toolApprovalSessionAllowances[key] ?? []
        let grants = record.grants.isEmpty
            ? [ToolApprovalGrant(kind: .tool, tool: normalizedToolApprovalToolID(record.tool))]
            : record.grants.map(normalizedApprovalGrant)
        for grant in grants {
            allowedGrants.insert(grant)
        }
        toolApprovalSessionAllowances[key] = allowedGrants
    }

    func isToolApprovalAllowedForSession(
        agentID: String,
        sessionID: String?,
        channelID: String?,
        toolID: String
    ) -> Bool {
        guard let scopeID = toolApprovalSessionScopeID(sessionID: sessionID, channelID: channelID) else {
            return false
        }
        let key = toolApprovalSessionAllowanceKey(agentID: agentID, scopeID: scopeID)
        let allowedGrants = toolApprovalSessionAllowances[key] ?? []
        let normalizedTool = normalizedToolApprovalToolID(toolID)
        return allowedGrants.contains { grant in
            grant.kind == .tool && normalizedToolApprovalToolID(grant.tool) == normalizedTool
        }
    }

    func setSessionToolApprovalBypass(sessionID: String, enabled: Bool) {
        guard let sessionID = normalizedSessionID(sessionID) else {
            return
        }
        if enabled {
            sessionToolApprovalBypass.insert(sessionID)
        } else {
            sessionToolApprovalBypass.remove(sessionID)
        }
    }

    func sessionApprovalGrants(
        agentID: String,
        sessionID: String?,
        channelID: String?
    ) -> [ToolApprovalGrant] {
        guard let scopeID = toolApprovalSessionScopeID(sessionID: sessionID, channelID: channelID) else {
            return []
        }
        let key = toolApprovalSessionAllowanceKey(agentID: agentID, scopeID: scopeID)
        return Array(toolApprovalSessionAllowances[key] ?? [])
    }

    private func toolApprovalSessionScopeID(sessionID: String?, channelID: String?) -> String? {
        if let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty {
            return "session:\(sessionID)"
        }
        if let channelID = channelID?.trimmingCharacters(in: .whitespacesAndNewlines), !channelID.isEmpty {
            return "channel:\(channelID)"
        }
        return nil
    }

    private func toolApprovalSessionAllowanceKey(agentID: String, scopeID: String) -> String {
        "\(agentID)\n\(scopeID)"
    }

    private func normalizedToolApprovalToolID(_ toolID: String) -> String {
        toolID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedApprovalGrant(_ grant: ToolApprovalGrant) -> ToolApprovalGrant {
        ToolApprovalGrant(
            kind: grant.kind,
            tool: normalizedToolApprovalToolID(grant.tool),
            operation: grant.operation?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            resource: normalizedApprovalResource(grant.resource)
        )
    }

    private func normalizedApprovalResource(_ resource: String?) -> String? {
        guard let trimmed = resource?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private func appendUniqueRoot(_ root: String, to roots: inout [String]) {
        guard !roots.contains(root) else {
            return
        }
        roots.append(root)
    }

    private func missingAccessApprovalReason(tool: String, grants: [ToolApprovalGrant]) -> String {
        let resources = grants.compactMap(\.resource)
        if let first = resources.first {
            return "Allow \(tool) to access \(first)."
        }
        return "Allow access to \(tool)."
    }

    private func toolApprovalDisplaySessionID(agentID: String, sessionID: String?) -> String? {
        guard let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty,
              let detail = try? getAgentSession(agentID: agentID, sessionID: sessionID),
              let parentSessionID = detail.summary.parentSessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !parentSessionID.isEmpty
        else {
            return nil
        }
        return parentSessionID
    }

    private func appendToolApprovalPausedStatusIfNeeded(
        agentID: String,
        sessionID: String?,
        displaySessionID: String?,
        record: ToolApprovalRecord
    ) async {
        await appendToolApprovalPausedStatus(agentID: agentID, sessionID: sessionID, record: record)
        let sourceSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let displaySessionID,
              displaySessionID != sourceSessionID
        else {
            return
        }
        await appendToolApprovalPausedStatus(agentID: agentID, sessionID: displaySessionID, record: record)
    }

    private func appendToolApprovalPausedStatus(
        agentID: String,
        sessionID: String?,
        record: ToolApprovalRecord
    ) async {
        guard let sessionID else {
            return
        }
        let details = record.reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? record.reason!
            : "Tool: \(record.tool)"
        let event = AgentSessionEvent(
            agentId: agentID,
            sessionId: sessionID,
            type: .runStatus,
            runStatus: AgentRunStatusEvent(
                stage: .paused,
                label: "Tool approval required",
                details: details
            )
        )
        guard let summary = try? sessionStore.appendEvents(agentID: agentID, sessionID: sessionID, events: [event]) else {
            return
        }
        publishLiveSessionEvents(agentID: agentID, sessionID: sessionID, summary: summary, events: [event])
    }
}
