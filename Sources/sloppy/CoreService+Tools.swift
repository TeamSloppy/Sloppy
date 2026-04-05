import Foundation
import Logging
import Protocols

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

        do {
            _ = try getAgent(id: normalizedAgentID)
            _ = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
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
            result = await toolExecution.invoke(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                request: request,
                policy: effectivePolicy
            )
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

        return result
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
    }

}
