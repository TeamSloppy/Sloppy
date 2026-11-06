import Foundation
import AgentRuntime
import PluginSDK
import Protocols

/// Internal authority carried from the durable loop, never accepted from an HTTP payload.
struct NativeToolExecutionContext: Sendable {
    var delegatedAuthority: RunRequestSettings.ToolAuthority? = nil
    var delegatedToolScope: [String]? = nil
    var metadata: AgentRunMetadata
    var definition: ModelStepToolDefinition
    var beforeEffect: AgentLoopToolExecutor.BeforeEffect
    var finalizer: (@Sendable (ToolInvocationRequest) async -> AgentLoopToolOutcome)? = nil
    var routeSelector: (@Sendable (ToolInvocationRequest) async -> AgentLoopToolOutcome)? = nil
    var proactiveReporter: (@Sendable (ToolInvocationRequest) async -> ToolInvocationResult)? = nil
    var recordLateResult: (@Sendable (ToolInvocationResult) async throws -> Void)? = nil
    /// A remaining run deadline may narrow the tool's configured hard timeout.
    var remainingDeadlineMilliseconds: Int? = nil
    var effectNow: (@Sendable () async -> ContinuousClock.Instant)? = nil

    func approvalBinding(policy: AgentToolsPolicy, workingDirectory: String?, extraRoots: [String]) throws -> ToolApprovalBinding {
        var restrictions = policy
        restrictions.approvalGrants = []
        var declared = definition
        declared.parameters = Self.canonicalApprovalSchema(declared.parameters)
        let authority: JSONValue = .object([
            "policy": try JSONValueCoder.encode(restrictions), "definition": try JSONValueCoder.encode(declared),
            "workingDirectory": workingDirectory.map(JSONValue.string) ?? .null,
            "extraRoots": .array(extraRoots.sorted().map(JSONValue.string)),
            "delegatedAuthority": try JSONValueCoder.encode(delegatedAuthority),
            "toolScope": try JSONValueCoder.encode(delegatedToolScope)
        ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return .init(invocation: metadata, authorityDigest: ContentDigest.sha256(try encoder.encode(authority)),
            requiredGrants: policy.approvalGrants, authority: authority)
    }

    /// JSON Schema's required set has no ordering semantics; generated schemas may reorder it.
    private static func canonicalApprovalSchema(_ schema: JSONValue) -> JSONValue {
        guard var object = schema.asObject else { return schema }
        if let required = object["required"]?.asArray, required.allSatisfy({ $0.asString != nil }) {
            object["required"] = .array(required.sorted { ($0.asString ?? "") < ($1.asString ?? "") })
        }
        for key in ["properties", "$defs", "definitions", "patternProperties"] {
            if let children = object[key]?.asObject { object[key] = .object(children.mapValues(canonicalApprovalSchema)) }
        }
        for key in ["items", "additionalProperties", "not", "if", "then", "else"] {
            if let child = object[key] { object[key] = canonicalApprovalSchema(child) }
        }
        for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
            if let children = object[key]?.asArray { object[key] = .array(children.map(canonicalApprovalSchema)) }
        }
        return .object(object)
    }

    func matches(_ request: ToolInvocationRequest, events: [AgentSessionEvent]) -> Bool {
        guard definition.toolId == request.tool, let callID = metadata.callEventId,
              let event = events.first(where: { $0.id == callID && !$0.isHistorical }),
              let saved = event.runtimeMetadata, saved.executionPhase == .requested,
              event.toolCall?.tool == request.tool, event.toolCall?.arguments == request.arguments else { return false }
        return saved.runId == metadata.runId && saved.userTurnId == metadata.userTurnId &&
            saved.derivedSource == metadata.derivedSource &&
            saved.stepId == metadata.stepId && saved.attemptId == metadata.attemptId &&
            saved.generation == metadata.generation && saved.sourceOrder == metadata.sourceOrder &&
            saved.providerCallId == metadata.providerCallId && saved.callEventId == callID
    }

    func validateArguments(_ request: ToolInvocationRequest) throws {
        guard request.tool == definition.toolId else {
            throw ModelStepFailure(category: .protocolViolation, code: "tool_identity_changed",
                message: "A pre-hook cannot change the declared tool identity.")
        }
        let raw = String(decoding: try JSONEncoder().encode(request.arguments), as: UTF8.self)
        _ = try ToolArgumentValidator.arguments(raw, schema: definition.parameters)
    }

    /// Approval may add a grant, but cannot revive a request prepared under revoked restrictions.
    static func authorityMatches(_ initial: AgentToolsPolicy, _ current: AgentToolsPolicy) -> Bool {
        var before = initial
        var after = current
        before.approvalGrants = []
        after.approvalGrants = []
        return before == after && initial.approvalGrants.allSatisfy { current.approvalGrants.contains($0) }
    }
}

extension CoreService {
    func nativeWorkerAuthority(agentID: String, sessionID: String) async throws -> (toolScope: [String], authority: RunRequestSettings.ToolAuthority)? {
        guard !peerConversationSessions.contains(sessionID) else { return nil }
        let detail = try sessionStore.loadSession(agentID: agentID, sessionID: sessionID)
        let scope: Set<String>?
        if detail.summary.kind == .longChat {
            scope = await runtime.channelToolScope(channelId: sessionChannelID(agentID: agentID, sessionID: sessionID))
        } else { scope = sessionSubagentToolAllowList[sessionID] }
        guard let scope else { return nil }
        let policy = try await toolsAuthorization.policy(agentID: agentID)
        let context = await toolContextForSession(sessionID: sessionID, sessionTitle: detail.summary.title,
            projectID: detail.summary.projectId, taskID: detail.summary.taskId)
        return (scope.sorted(), .init(policy: policy, workingDirectory: context.workingDirectory, extraRoots: context.extraRoots))
    }

    func invokeNativeTool(agentID: String, sessionID: String, request: ToolInvocationRequest,
                          context: NativeToolExecutionContext, chatMode: AgentChatMode? = nil) async -> AgentLoopToolOutcome {
        await invokeSessionTool(agentID: agentID, sessionID: sessionID, request: request,
            recordSessionEvents: false, requireApproval: false, chatMode: chatMode, nativeContext: context,
            derivedSource: context.metadata.derivedSource)
    }

    /// Runs inside the owned effect task, after approval and immediately before actual dispatch.
    func executeNativeEffect(
        agentID: String, sessionID: String, request: ToolInvocationRequest,
        context: NativeToolExecutionContext, initialPolicy: AgentToolsPolicy,
        requiresWorkerScope: Bool, chatMode: AgentChatMode?,
        operation: @escaping @Sendable () async -> ToolInvocationResult
    ) async -> AgentLoopToolOutcome {
        do {
            try Task.checkCancellation()
            let current = try await toolsAuthorization.policy(agentID: agentID)
            if let source = context.metadata.derivedSource,
               !nativeDerivedWorkSourceIsCurrent(source, ignoringDerivedRunID: context.metadata.runId) { throw CancellationError() }
            guard NativeToolExecutionContext.authorityMatches(initialPolicy, current) else {
                throw ModelStepFailure(category: .unavailable, code: "tool_forbidden",
                    message: "The tool policy changed while this invocation was being prepared. Prepare a new request under the current policy.")
            }
            if requiresWorkerScope {
                guard let (_, currentTask) = longChatParent(of: sessionID), !currentTask.status.isTerminal,
                      currentTask.attempts.last?.sessionId == sessionID else {
                    throw ModelStepFailure(category: .unavailable, code: "tool_forbidden", message: "The worker stopped before the effect started.")
                }
            }
            if let scope = sessionSubagentToolAllowList[sessionID], !scope.contains(request.tool) {
                throw ModelStepFailure(category: .unavailable, code: "tool_forbidden", message: "The tool is outside the current delegated scope.")
            }
            try Task.checkCancellation()
            try await context.beforeEffect()
            try Task.checkCancellation()
        } catch {
            return .init(result: .init(tool: request.tool, ok: false, error: .init(
                code: error is CancellationError ? "not_executed_cancelled" : ((error as? ModelStepFailure)?.code ?? "effect_start_failed"),
                message: error.localizedDescription, retryable: false)))
        }
        if request.tool == SessionCompleteTool.toolName, let finalizer = context.finalizer {
            return await finalizer(request)
        }
        if request.tool == "planning.select_route", let routeSelector = context.routeSelector {
            return await routeSelector(request)
        }
        if request.tool == "heartbeat.report", let reporter = context.proactiveReporter {
            return .init(result: await reporter(request))
        }
        if LongChatCoordinatorPolicy.managementTools.contains(request.tool) {
            return .init(result: await invokeLongChatTool(agentID: agentID, sessionID: sessionID, request: request))
        }
        if request.tool == "planning.request_input" {
            return .init(result: await handleAgentPlanInputTool(agentID: agentID, sessionID: sessionID, request: request, chatMode: chatMode))
        }
        if request.tool == "planning.progress_update" {
            return .init(result: await handleAgentBuildProgressTool(agentID: agentID, sessionID: sessionID, request: request, chatMode: chatMode))
        }
        return .init(result: await operation())
    }
}
