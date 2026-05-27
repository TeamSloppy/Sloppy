import Foundation
import AgentRuntime
import Protocols

// MARK: - Self-improvement proposal review

extension CoreService {
    static let selfImprovementProposalToolIterationThreshold = 10
    static let selfImprovementRepeatedClarificationThreshold = 2

    static let selfImprovementProposalToolAllowlist: Set<String> = [
        "visor.status",
        "project.current",
        "project.task_list",
        "project.task_create",
        "project.task_update",
    ]

    enum SelfImprovementFailureClassification: String, CaseIterable, Sendable {
        case promptIssue = "prompt issue"
        case runtimeBug = "runtime bug"
        case missingTool = "missing tool"
        case policyIssue = "policy issue"
        case userEnvironmentSetup = "user/environment setup"
        case ignore
    }

    struct SelfImprovementFailureSignal: Sendable, Equatable {
        var kind: String
        var tool: String?
        var code: String?
        var message: String?
    }

    func maybeScheduleSelfImprovementProposalReviewAfterTurn(
        agentID: String,
        sessionID: String,
        response: AgentSessionMessageResponse,
        userID: String
    ) {
        let uid = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard uid != "system_task_worker",
              uid != "memory_checkpoint",
              uid != "self_improvement",
              uid != "onboarding"
        else { return }

        guard response.summary.projectId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        let detail: AgentSessionDetail
        do {
            detail = try sessionStore.loadSession(agentID: agentID, sessionID: sessionID)
        } catch {
            return
        }

        let turnEvents = Self.latestUserTurnEvents(from: detail, userID: userID)
        let failureSignals = Self.selfImprovementFailureSignals(
            turnEvents: turnEvents,
            responseEvents: response.appendedEvents
        )
        if !failureSignals.isEmpty {
            scheduleSelfImprovementProposalReview(
                agentID: agentID,
                sessionID: sessionID,
                reason: "failure_review:\(Self.compactFailureReason(from: failureSignals))",
                reviewContext: Self.formattedFailureReviewContext(from: failureSignals)
            )
            return
        }

        guard response.appendedEvents.contains(where: { event in
            event.type == .runStatus && event.runStatus?.stage == .done
        }) else { return }

        let toolResultCount = detail.events.filter { $0.type == .toolResult }.count
        let bucket = toolResultCount / Self.selfImprovementProposalToolIterationThreshold
        guard bucket > 0 else { return }

        let lockKey = selfImprovementProposalReviewLockKey(agentID: agentID, sessionID: sessionID)
        let previousBucket = selfImprovementProposalReviewToolBuckets[lockKey] ?? 0
        guard bucket > previousBucket else { return }
        selfImprovementProposalReviewToolBuckets[lockKey] = bucket

        scheduleSelfImprovementProposalReview(
            agentID: agentID,
            sessionID: sessionID,
            reason: "tool_iteration_threshold:\(toolResultCount)",
            reviewContext: nil
        )
    }

    func scheduleSelfImprovementProposalReview(
        agentID: String,
        sessionID: String,
        reason: String,
        reviewContext: String? = nil
    ) {
        guard let normalizedAgentID = normalizedAgentID(agentID),
              let normalizedSessionID = normalizedSessionID(sessionID)
        else {
            logger.warning(
                "self_improvement.proposal.background_failed",
                metadata: [
                    "agent_id": .string(agentID),
                    "session_id": .string(sessionID),
                    "reason": .string(reason),
                    "error": .string("invalid_identifier"),
                ]
            )
            return
        }

        logger.info(
            "self_improvement.proposal.background_scheduled",
            metadata: [
                "agent_id": .string(normalizedAgentID),
                "session_id": .string(normalizedSessionID),
                "reason": .string(reason),
            ]
        )

        Task { [weak self] in
            guard let self else { return }
            await self.runScheduledSelfImprovementProposalReview(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                reason: reason,
                reviewContext: reviewContext
            )
        }
    }

    private func runScheduledSelfImprovementProposalReview(
        agentID: String,
        sessionID: String,
        reason: String,
        reviewContext: String?
    ) async {
        logger.info(
            "self_improvement.proposal.background_started",
            metadata: [
                "agent_id": .string(agentID),
                "session_id": .string(sessionID),
                "reason": .string(reason),
            ]
        )
        await runSelfImprovementProposalReview(
            agentID: agentID,
            sessionID: sessionID,
            reason: reason,
            reviewContext: reviewContext
        )
        logger.info(
            "self_improvement.proposal.background_completed",
            metadata: [
                "agent_id": .string(agentID),
                "session_id": .string(sessionID),
                "reason": .string(reason),
            ]
        )
    }

    func runSelfImprovementProposalReview(
        agentID: String,
        sessionID: String,
        reason: String,
        reviewContext: String? = nil
    ) async {
        guard let normalizedAgentID = normalizedAgentID(agentID) else { return }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else { return }

        let lockKey = selfImprovementProposalReviewLockKey(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        guard !selfImprovementProposalReviewLocks.contains(lockKey) else {
            logger.info(
                "self_improvement.proposal.skipped_overlap",
                metadata: [
                    "agent_id": .string(normalizedAgentID),
                    "session_id": .string(normalizedSessionID),
                ]
            )
            return
        }
        selfImprovementProposalReviewLocks.insert(lockKey)
        defer { selfImprovementProposalReviewLocks.remove(lockKey) }

        do {
            _ = try getAgent(id: normalizedAgentID)
        } catch {
            logger.warning("self_improvement.proposal.agent_unavailable", metadata: ["agent_id": .string(normalizedAgentID)])
            return
        }

        let detail: AgentSessionDetail
        do {
            detail = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        } catch {
            logger.warning("self_improvement.proposal.session_unavailable", metadata: ["error": .string(error.localizedDescription)])
            return
        }

        guard let projectID = detail.summary.projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectID.isEmpty,
              let project = try? await getProject(id: projectID)
        else {
            logger.info(
                "self_improvement.proposal.skipped_no_project",
                metadata: [
                    "agent_id": .string(normalizedAgentID),
                    "session_id": .string(normalizedSessionID),
                ]
            )
            return
        }

        let models = availableAgentModels()
        let config: AgentConfigDetail
        do {
            config = try agentCatalogStore.getAgentConfig(
                agentID: normalizedAgentID,
                availableModels: models,
                persistedModelAllowed: makePersistedModelAllowance()
            )
        } catch {
            logger.warning("self_improvement.proposal.no_agent_config", metadata: ["agent_id": .string(normalizedAgentID)])
            return
        }

        let selectedModel = config.selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelForRequest = (selectedModel?.isEmpty == false) ? selectedModel : nil
        let transcript = Self.formattedCheckpointTranscript(from: detail, maxUTF16Scalars: 80_000)
        let existingProposals = Self.formattedExistingSelfImprovementProposals(project)
        let bootstrap = Self.selfImprovementProposalBootstrap(
            agentID: normalizedAgentID,
            sessionID: normalizedSessionID,
            reason: reason,
            project: project,
            existingProposals: existingProposals,
            transcript: transcript,
            reviewContext: reviewContext
        )

        let uuid = UUID().uuidString.lowercased()
        let ephemeralChannelId = "agent:\(normalizedAgentID):session:\(normalizedSessionID):proposal-review:\(uuid)"
        let actionRecorder = SelfImprovementProposalActionRecorder()

        await runtime.setChannelBootstrap(channelId: ephemeralChannelId, content: bootstrap)

        let toolInvoker: @Sendable (ToolInvocationRequest) async -> ToolInvocationResult = { request in
            guard Self.selfImprovementProposalToolAllowlist.contains(request.tool) else {
                return ToolInvocationResult(
                    tool: request.tool,
                    ok: false,
                    error: ToolErrorPayload(
                        code: "proposal_tool_not_allowed",
                        message: "This tool is not available during self-improvement proposal review. Create or update reviewable project tasks only.",
                        retryable: false
                    )
                )
            }
            if request.tool == "project.task_create",
               reviewContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
               !Self.proposalDescriptionHasRequiredFailureClassification(request.arguments["description"]?.asString) {
                return ToolInvocationResult(
                    tool: request.tool,
                    ok: false,
                    error: ToolErrorPayload(
                        code: "failure_classification_required",
                        message: "Failure review proposal tasks must include `## Failure Classification` with exactly one allowed classification.",
                        retryable: false
                    )
                )
            }
            let result = await self.invokeSelfImprovementProposalTool(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                projectID: project.id,
                request: request
            )
            await actionRecorder.record(result)
            return result
        }

        let userPrompt = """
        Run the self-improvement proposal review now. If there is no durable, reusable improvement proposal, reply exactly: Nothing to propose.
        If there is a proposal, create or update one project task using only the allowed project tools. Do not address the end user.
        """

        _ = await runtime.postMessage(
            channelId: ephemeralChannelId,
            request: ChannelMessageRequest(
                userId: "self_improvement",
                content: userPrompt,
                model: modelForRequest,
                reasoningEffort: nil
            ),
            onResponseChunk: { _ in true },
            toolInvoker: toolInvoker,
            observationHandler: nil,
            nativeLoopConfig: NativeAgentLoopConfig(maxToolRounds: 16)
        )

        await runtime.discardEphemeralCheckpointChannel(channelId: ephemeralChannelId)

        if let review = await actionRecorder.review(reason: reason) {
            await appendSelfImprovementReviewSummary(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                review: review
            )
        }

        logger.info(
            "self_improvement.proposal.completed",
            metadata: [
                "agent_id": .string(normalizedAgentID),
                "session_id": .string(normalizedSessionID),
                "reason": .string(reason),
            ]
        )
    }

    func invokeSelfImprovementProposalTool(
        agentID: String,
        sessionID: String,
        projectID: String,
        request: ToolInvocationRequest
    ) async -> ToolInvocationResult {
        guard Self.selfImprovementProposalToolAllowlist.contains(request.tool) else {
            return ToolInvocationResult(
                tool: request.tool,
                ok: false,
                error: ToolErrorPayload(
                    code: "proposal_tool_not_allowed",
                    message: "This tool is not available during self-improvement proposal review. Create or update reviewable project tasks only.",
                    retryable: false
                )
            )
        }
        let sessionDetail = try? sessionStore.loadSession(agentID: agentID, sessionID: sessionID)
        let sessionContext = await toolContextForSession(
            sessionID: sessionID,
            sessionTitle: sessionDetail?.summary.title ?? "",
            projectID: projectID
        )
        let currentDirectoryURL = sessionContext.workingDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        var policy = AgentToolsPolicy(defaultPolicy: .deny)
        for toolID in Self.selfImprovementProposalToolAllowlist {
            policy.tools[toolID] = true
        }
        var effectiveRequest = request
        if request.tool == "project.task_create" {
            effectiveRequest.arguments = Self.normalizedProposalTaskCreateArguments(
                request.arguments,
                projectID: projectID
            )
        }
        return await toolExecution.invoke(
            agentID: agentID,
            sessionID: sessionID,
            request: effectiveRequest,
            policy: policy,
            currentProjectID: projectID,
            currentDirectoryURL: currentDirectoryURL
        )
    }

    func appendSelfImprovementReviewSummary(
        agentID: String,
        sessionID: String,
        review: AgentSelfImprovementReviewEvent
    ) async {
        let event = AgentSessionEvent(
            agentId: agentID,
            sessionId: sessionID,
            type: .selfImprovementReview,
            selfImprovementReview: review
        )
        do {
            let summary = try sessionStore.appendEvents(agentID: agentID, sessionID: sessionID, events: [event])
            publishLiveSessionEvents(agentID: agentID, sessionID: sessionID, summary: summary, events: [event])
        } catch {
            logger.warning(
                "self_improvement.summary_append_failed",
                metadata: [
                    "agent_id": .string(agentID),
                    "session_id": .string(sessionID),
                    "error": .string(error.localizedDescription),
                ]
            )
        }
    }

    func appendMemoryCheckpointReviewSummary(
        agentID: String,
        sessionID: String,
        review: AgentSelfImprovementReviewEvent
    ) async {
        await appendSelfImprovementReviewSummary(agentID: agentID, sessionID: sessionID, review: review)
    }

    private func selfImprovementProposalReviewLockKey(agentID: String, sessionID: String) -> String {
        "\(agentID.lowercased())::\(sessionID.lowercased())"
    }

    static func selfImprovementProposalBootstrap(
        agentID: String,
        sessionID: String,
        reason: String,
        project: ProjectRecord,
        existingProposals: String,
        transcript: String,
        reviewContext: String? = nil
    ) -> String {
        let failureInstructions: String
        if let reviewContext,
           !reviewContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failureInstructions = """

            Failure/tool runtime review focus:
            \(reviewContext)

            If you create a proposal for this review, the description must also include:
              - `## Failure Classification`
              - exactly one of: \(SelfImprovementFailureClassification.allCases.map(\.rawValue).joined(separator: ", "))

            Use `user/environment setup` or `ignore` only when a project task is still useful; otherwise reply exactly: Nothing to propose.
            Do not save these failure signals as durable memory.
            """
        } else {
            failureInstructions = ""
        }

        return """
        Internal self-improvement proposal review (not visible in the user chat). Reason: \(reason).

        Agent: \(agentID)
        Session: \(sessionID)
        Project: `\(project.id)` - \(project.name)

        Allowed tools only: `visor.status`, `project.current`, `project.task_list`, `project.task_create`, `project.task_update`.
        Forbidden: shell/runtime.exec, browser/web, files.*, MCP install/remove/config tools, skill install/uninstall/update tools, repo/source-control mutation, project delete, task delete.

        Goal:
        Create a reviewable project task only when the completed conversation shows a durable improvement to Sloppy skills, core instructions, tool usage guidance, or runtime behavior.

        Do not create tasks for:
        - ordinary product implementation follow-ups;
        - transient user/environment setup;
        - one-off facts better suited to memory checkpoint;
        - vague low-confidence guesses;
        - duplicates of existing self-improvement proposal tasks.

        If there is no strong proposal, reply exactly: Nothing to propose.

        Before creating a proposal, compare with existing proposal tasks. If an active task already covers the same issue, use `project.task_update` to add missing evidence instead of creating a duplicate.
        Create at most one proposal task per review.

        New proposal task requirements:
        - tool: `project.task_create`
        - `projectId`: `\(project.id)`
        - `status`: `pending_approval`
        - `kind`: `planning`
        - `changedBy`: `system:self-improvement`
        - `tags`: include `self-improvement`, `proposal`, and one affected subsystem tag such as `skills`, `runtime`, `tools`, `memory`, `dashboard`, `prompts`, or `mcp`
        - description must include these headings:
          - `## Goal`
          - `## Context`
          - `## Observed Issue`
          - `## Evidence`
          - `## Suggested Change`
          - `## Risk`
          - `## Affected Subsystem`
          - `## Definition of Done`
          - `## Tests / Verification`

        Existing self-improvement proposal tasks:
        \(existingProposals)
        \(failureInstructions)

        Recent session transcript (ground truth):
        \(transcript)
        """
    }

    static func normalizedProposalTaskCreateArguments(
        _ arguments: [String: JSONValue],
        projectID: String
    ) -> [String: JSONValue] {
        var normalized = arguments
        normalized["projectId"] = .string(projectID)
        normalized["status"] = .string(ProjectTaskStatus.pendingApproval.rawValue)
        normalized["kind"] = .string(ProjectTaskKind.planning.rawValue)
        normalized["changedBy"] = .string("system:self-improvement")

        let existingTags = arguments["tags"]?.asArray?.compactMap(\.asString) ?? []
        let requiredTags = ["self-improvement", "proposal"]
        let mergedTags = Array(Set(existingTags + requiredTags))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
        normalized["tags"] = .array(mergedTags.map { .string($0) })
        return normalized
    }

    static func formattedExistingSelfImprovementProposals(_ project: ProjectRecord) -> String {
        let activeStatuses = Set([
            ProjectTaskStatus.pendingApproval.rawValue,
            ProjectTaskStatus.backlog.rawValue,
            ProjectTaskStatus.ready.rawValue,
            ProjectTaskStatus.inProgress.rawValue,
            ProjectTaskStatus.needsReview.rawValue,
        ])
        let proposals = project.tasks
            .filter { task in
                activeStatuses.contains(task.status) &&
                    task.tags.contains("self-improvement") &&
                    task.tags.contains("proposal")
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
        guard !proposals.isEmpty else {
            return "(none)"
        }
        return proposals.map { task in
            let description = task.description
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let compactDescription = description.count > 500
                ? String(description.prefix(500)) + "..."
                : description
            return "- `\(task.id)` [\(task.status)] \(task.title) tags=\(task.tags.joined(separator: ",")) :: \(compactDescription)"
        }.joined(separator: "\n")
    }

    static func latestUserTurnEvents(from detail: AgentSessionDetail, userID: String) -> [AgentSessionEvent] {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let startIndex = detail.events.lastIndex(where: { event in
            guard event.type == .message,
                  event.message?.role == .user
            else {
                return false
            }
            let eventUserID = event.message?.userId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return normalizedUserID.isEmpty || eventUserID == normalizedUserID
        }) else {
            return detail.events
        }
        return Array(detail.events[startIndex...])
    }

    static func selfImprovementFailureSignals(
        turnEvents: [AgentSessionEvent],
        responseEvents: [AgentSessionEvent]
    ) -> [SelfImprovementFailureSignal] {
        var signals: [SelfImprovementFailureSignal] = []
        var seen: Set<String> = []

        func append(_ signal: SelfImprovementFailureSignal) {
            let key = [
                signal.kind,
                signal.tool ?? "",
                signal.code ?? "",
                signal.message ?? "",
            ].joined(separator: "\u{1F}")
            guard !seen.contains(key) else { return }
            seen.insert(key)
            signals.append(signal)
        }

        for event in turnEvents where event.type == .toolResult {
            guard let result = event.toolResult else { continue }
            let code = result.error?.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = result.error?.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let timedOut = result.data?.asObject?["timedOut"]?.asBool == true

            if timedOut {
                append(SelfImprovementFailureSignal(
                    kind: "tool_timeout",
                    tool: result.tool,
                    code: code?.isEmpty == false ? code : "tool_timeout",
                    message: message
                ))
            }

            if !result.ok {
                let normalizedCode = code?.lowercased()
                let kind: String
                switch normalizedCode {
                case "tool_timeout":
                    kind = "tool_timeout"
                case "unknown_tool":
                    kind = "unknown_tool"
                case "tool_forbidden":
                    kind = "tool_forbidden"
                case "tool_loop_detected":
                    kind = "tool_loop_detected"
                case "tool_budget_exhausted":
                    kind = "turn_limit"
                default:
                    kind = "tool_error"
                }
                append(SelfImprovementFailureSignal(
                    kind: kind,
                    tool: result.tool,
                    code: code,
                    message: message
                ))
            }
        }

        if responseEvents.contains(where: { event in
            guard event.type == .runStatus,
                  let status = event.runStatus,
                  status.stage == .interrupted
            else {
                return false
            }
            return status.label == "Incomplete" &&
                status.details == "Agent reached the tool turn limit before producing a final answer."
        }) {
            append(SelfImprovementFailureSignal(
                kind: "turn_limit",
                tool: nil,
                code: "tool_budget_exhausted",
                message: "Agent reached the tool turn limit before producing a final answer."
            ))
        }

        let clarificationToolNames: Set<String> = [
            "project.task_clarification_create",
            "planning.request_input",
        ]
        let clarificationCount = turnEvents.reduce(into: 0) { count, event in
            guard event.type == .toolResult,
                  let result = event.toolResult,
                  result.ok,
                  clarificationToolNames.contains(result.tool)
            else {
                return
            }
            count += 1
        }
        if clarificationCount >= selfImprovementRepeatedClarificationThreshold {
            append(SelfImprovementFailureSignal(
                kind: "repeated_clarification",
                tool: nil,
                code: "repeated_clarification",
                message: "\(clarificationCount) clarification requests were created in one completed turn."
            ))
        }

        return signals
    }

    static func compactFailureReason(from signals: [SelfImprovementFailureSignal]) -> String {
        let kinds = Array(Set(signals.map(\.kind))).sorted()
        return kinds.isEmpty ? "none" : kinds.joined(separator: ",")
    }

    static func formattedFailureReviewContext(from signals: [SelfImprovementFailureSignal]) -> String {
        guard !signals.isEmpty else {
            return "(none)"
        }
        return signals.map { signal in
            var parts = ["kind=\(signal.kind)"]
            if let tool = signal.tool?.trimmingCharacters(in: .whitespacesAndNewlines),
               !tool.isEmpty {
                parts.append("tool=\(tool)")
            }
            if let code = signal.code?.trimmingCharacters(in: .whitespacesAndNewlines),
               !code.isEmpty {
                parts.append("code=\(code)")
            }
            if let message = signal.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                parts.append("message=\(truncatedFailureSignalMessage(message, maxUTF16Scalars: 240))")
            }
            return "- \(parts.joined(separator: "; "))"
        }.joined(separator: "\n")
    }

    private static func truncatedFailureSignalMessage(_ text: String, maxUTF16Scalars: Int) -> String {
        guard text.unicodeScalars.count > maxUTF16Scalars else {
            return text
        }
        let idx = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: maxUTF16Scalars)
        return String(text.unicodeScalars[..<idx]) + "..."
    }

    static func proposalDescriptionHasRequiredFailureClassification(_ description: String?) -> Bool {
        guard let classification = failureClassification(in: description) else {
            return false
        }
        return SelfImprovementFailureClassification.allCases.contains(classification)
    }

    static func failureClassification(in description: String?) -> SelfImprovementFailureClassification? {
        guard let description else { return nil }
        let lines = description.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "## failure classification"
        }) else {
            return nil
        }

        for line in lines.dropFirst(headingIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                return nil
            }
            let normalized = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*: `"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let classification = SelfImprovementFailureClassification(rawValue: normalized) {
                return classification
            }
        }
        return nil
    }
}

actor SelfImprovementProposalActionRecorder {
    private var createdTasks: [(id: String, title: String)] = []
    private var updatedTasks: [(id: String, title: String)] = []

    func record(_ result: ToolInvocationResult) {
        guard result.ok else { return }
        guard let payload = result.data?.asObject else { return }
        switch result.tool {
        case "project.task_create":
            let taskID = payload["taskId"]?.asString ?? ""
            let title = payload["title"]?.asString ?? ""
            if !taskID.isEmpty {
                createdTasks.append((id: taskID, title: title))
            }
        case "project.task_update":
            let taskID = payload["taskId"]?.asString ?? ""
            let title = payload["task"]?.asObject?["title"]?.asString ?? ""
            if !taskID.isEmpty {
                updatedTasks.append((id: taskID, title: title))
            }
        default:
            break
        }
    }

    func review(reason: String) -> AgentSelfImprovementReviewEvent? {
        var actions: [String] = []
        actions.append(contentsOf: createdTasks.map { task in
            task.title.isEmpty
                ? "proposal task \(task.id) created"
                : "proposal task \(task.id) created: \(task.title)"
        })
        actions.append(contentsOf: updatedTasks.map { task in
            task.title.isEmpty
                ? "proposal task \(task.id) updated"
                : "proposal task \(task.id) updated: \(task.title)"
        })
        guard !actions.isEmpty else { return nil }
        return AgentSelfImprovementReviewEvent(
            summary: "Self-improvement review: \(actions.joined(separator: ", "))",
            actions: actions,
            reason: reason
        )
    }
}
