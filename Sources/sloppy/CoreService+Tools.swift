import Foundation
import Logging
import Protocols
import Tracing

// MARK: - Tool Invocation

extension CoreService {
    public func invokeTool(
        agentID: String,
        sessionID: String,
        request: ToolInvocationRequest
    ) async throws -> ToolInvocationResult {
        let result = await invokeToolFromRuntime(agentID: agentID, sessionID: sessionID, request: request)
        if result.ok || result.error?.code != "tool_forbidden" {
            return result
        }
        throw ToolInvocationError.forbidden(result.error ?? .init(code: "tool_forbidden", message: "Forbidden", retryable: false))
    }

    /// Internal runtime path used by auto tool-calling loop.
    public func invokeToolFromRuntime(
        agentID: String,
        sessionID: String,
        request: ToolInvocationRequest,
        recordSessionEvents: Bool = true
    ) async -> ToolInvocationResult {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            return .init(
                tool: request.tool,
                ok: false,
                error: .init(code: "invalid_agent_id", message: "Invalid agent id.", retryable: false)
            )
        }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else {
            return .init(
                tool: request.tool,
                ok: false,
                error: .init(code: "invalid_session_id", message: "Invalid session id.", retryable: false)
            )
        }
        guard !request.tool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .init(
                tool: request.tool,
                ok: false,
                error: .init(code: "invalid_tool", message: "Tool id is required.", retryable: false)
            )
        }

        let sessionDetail: AgentSessionDetail
        do {
            _ = try getAgent(id: normalizedAgentID)
            sessionDetail = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        } catch let error as AgentStorageError {
            if case .notFound = error {
                return .init(
                    tool: request.tool,
                    ok: false,
                    error: .init(code: "agent_not_found", message: "Agent not found.", retryable: false)
                )
            }
            return .init(
                tool: request.tool,
                ok: false,
                error: .init(code: "invalid_agent_id", message: "Invalid agent id.", retryable: false)
            )
        } catch {
            return .init(
                tool: request.tool,
                ok: false,
                error: .init(code: "session_not_found", message: "Session not found.", retryable: false)
            )
        }

        let authorization: ToolAuthorizationDecision
        do {
            authorization = try await toolsAuthorization.authorize(agentID: normalizedAgentID, toolID: request.tool)
        } catch {
            return .init(
                tool: request.tool,
                ok: false,
                error: .init(code: "authorization_failed", message: "Failed to authorize tool call.", retryable: true)
            )
        }

        let toolCallEvent = AgentSessionEvent(
            agentId: normalizedAgentID,
            sessionId: normalizedSessionID,
            type: .toolCall,
            toolCall: AgentToolCallEvent(
                tool: request.tool,
                arguments: request.arguments,
                reason: request.reason
            )
        )

        if recordSessionEvents {
            do {
                let summary = try sessionStore.appendEvents(
                    agentID: normalizedAgentID,
                    sessionID: normalizedSessionID,
                    events: [toolCallEvent]
                )
                publishLiveSessionEvents(
                    agentID: normalizedAgentID,
                    sessionID: normalizedSessionID,
                    summary: summary,
                    events: [toolCallEvent]
                )
            } catch {
                return .init(
                    tool: request.tool,
                    ok: false,
                    error: .init(code: "session_write_failed", message: "Failed to persist tool call event.", retryable: true)
                )
            }
        }

        let result: ToolInvocationResult
        if authorization.allowed {
            var effectivePolicy = authorization.policy
            if let extraRoots = sessionExtraRoots[normalizedSessionID], !extraRoots.isEmpty {
                effectivePolicy.guardrails.allowedExecRoots += extraRoots
                effectivePolicy.guardrails.allowedWriteRoots += extraRoots
            }
            result = await withSpan("tool.invoke", ofKind: .internal) { span in
                span.attributes["agent_id"] = "\(normalizedAgentID)"
                span.attributes["session_id"] = "\(normalizedSessionID)"
                span.attributes["tool_id"] = "\(request.tool)"
                return await toolExecution.invoke(
                    agentID: normalizedAgentID,
                    sessionID: normalizedSessionID,
                    request: request,
                    policy: effectivePolicy
                )
            }
        } else {
            result = .init(
                tool: request.tool,
                ok: false,
                error: authorization.error ?? .init(code: "tool_forbidden", message: "Tool is forbidden.", retryable: false)
            )
        }

        let toolResultEvent = AgentSessionEvent(
            agentId: normalizedAgentID,
            sessionId: normalizedSessionID,
            type: .toolResult,
            toolResult: AgentToolResultEvent(
                tool: request.tool,
                ok: result.ok,
                data: result.data,
                error: result.error,
                durationMs: result.durationMs
            )
        )

        if recordSessionEvents {
            do {
                let summary = try sessionStore.appendEvents(
                    agentID: normalizedAgentID,
                    sessionID: normalizedSessionID,
                    events: [toolResultEvent]
                )
                publishLiveSessionEvents(
                    agentID: normalizedAgentID,
                    sessionID: normalizedSessionID,
                    summary: summary,
                    events: [toolResultEvent]
                )
            } catch {
                return .init(
                    tool: request.tool,
                    ok: false,
                    error: .init(code: "session_write_failed", message: "Failed to persist tool result event.", retryable: true)
                )
            }
        }

        await persistToolInvocationAnalytics(
            agentId: normalizedAgentID,
            sessionId: normalizedSessionID,
            sessionTitle: sessionDetail.summary.title,
            toolId: request.tool,
            ok: result.ok,
            durationMs: result.durationMs
        )

        return result
    }

    func persistToolInvocationAnalytics(
        agentId: String,
        sessionId: String,
        sessionTitle: String,
        toolId: String,
        ok: Bool,
        durationMs: Int
    ) async {
        let trimmedTitle = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskId: String?
        if trimmedTitle.hasPrefix("task-") {
            let raw = String(trimmedTitle.dropFirst("task-".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            taskId = raw.isEmpty ? nil : raw
        } else {
            taskId = nil
        }

        let projectId: String?
        if let taskId {
            let projects = await store.listProjects()
            projectId = projects.first(where: { $0.tasks.contains(where: { $0.id == taskId }) })?.id
        } else {
            projectId = nil
        }

        await store.persistToolInvocation(
            id: UUID().uuidString,
            projectId: projectId,
            taskId: taskId,
            agentId: agentId,
            sessionId: sessionId,
            tool: toolId,
            ok: ok,
            durationMs: durationMs,
            traceId: nil,
            createdAt: Date()
        )
    }

    /// Persists config to file and updates in-memory snapshot.
    public func toolCatalog() async -> [AgentToolCatalogEntry] {
        await ToolCatalog.entries(mcpRegistry: mcpRegistry)
    }

    /// Returns agent tools policy from `/agents/<agentID>/tools/tools.json`.
    public func getAgentToolsPolicy(agentID: String) async throws -> AgentToolsPolicy {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentToolsError.invalidAgentID
        }
        _ = try getAgent(id: normalizedAgentID)
        do {
            return try await toolsAuthorization.policy(agentID: normalizedAgentID)
        } catch {
            throw mapAgentToolsError(error)
        }
    }

    /// Updates agent tools policy.
    public func updateAgentToolsPolicy(agentID: String, request: AgentToolsUpdateRequest) async throws -> AgentToolsPolicy {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentToolsError.invalidAgentID
        }
        _ = try getAgent(id: normalizedAgentID)
        do {
            return try await toolsAuthorization.updatePolicy(agentID: normalizedAgentID, request: request)
        } catch {
            throw mapAgentToolsError(error)
        }
    }

    func configureToolExecutionServices() {
        toolExecution.projectService = self
        toolExecution.configService = self
        toolExecution.skillsService = self
        toolExecution.applyAgentMarkdown = { [weak self] agentID, field, markdown in
            guard let self else {
                throw AgentConfigError.storageFailure
            }
            try await self.applyAgentMarkdownFromTool(agentID: agentID, field: field, markdown: markdown)
        }
    }

}
