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
        "self_improvement.proposal_submit",
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

    struct SelfImprovementProposalSubmitRequest: Sendable, Equatable {
        var action: SelfImprovementProposalAction
        var confidence: Double?
        var durability: Double?
        var affectedSubsystem: String?
        var title: String?
        var description: String?
        var evidence: [SelfImprovementProposalEvidence]
        var testsVerification: String?
        var failureClassification: SelfImprovementFailureClassification?
        var existingTaskID: String?
        var failureReview: Bool

        init(arguments: [String: JSONValue]) {
            let rawAction = arguments["action"]?.asString?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            self.action = rawAction.flatMap(SelfImprovementProposalAction.init(rawValue:)) ?? .nothing
            self.confidence = arguments["confidence"]?.asNumber
            self.durability = arguments["durability"]?.asNumber
            self.affectedSubsystem = arguments["affectedSubsystem"]?.asString
                ?? arguments["affected_subsystem"]?.asString
            self.title = arguments["title"]?.asString
            self.description = arguments["description"]?.asString
            self.evidence = (arguments["evidence"]?.asArray ?? [])
                .compactMap(SelfImprovementProposalEvidence.init(value:))
            self.testsVerification = arguments["testsVerification"]?.asString
                ?? arguments["tests_verification"]?.asString
            let rawClassification = arguments["failureClassification"]?.asString
                ?? arguments["failure_classification"]?.asString
            self.failureClassification = rawClassification.flatMap(CoreService.normalizedFailureClassification)
            self.existingTaskID = arguments["existingTaskID"]?.asString
                ?? arguments["existingTaskId"]?.asString
                ?? arguments["existing_task_id"]?.asString
            self.failureReview = arguments["failureReview"]?.asBool
                ?? arguments["failure_review"]?.asBool
                ?? false
        }
    }

    struct SelfImprovementProposalEvidence: Sendable, Equatable {
        var summary: String
        var source: String?

        init?(value: JSONValue) {
            if let text = value.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                self.summary = text
                self.source = nil
                return
            }
            guard let object = value.asObject else { return nil }
            let summary = object["summary"]?.asString?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? object["description"]?.asString?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            guard !summary.isEmpty else { return nil }
            self.summary = summary
            self.source = object["source"]?.asString?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var markdownLine: String {
            if let source, !source.isEmpty {
                return "- \(summary) (`\(source)`)"
            }
            return "- \(summary)"
        }
    }

    enum SelfImprovementProposalAction: String, Sendable {
        case nothing
        case create
        case update
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

        let projectID: String
        do {
            let detail = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            projectID = detail.summary.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            logger.warning(
                "self_improvement.proposal.enqueue_failed",
                metadata: [
                    "agent_id": .string(normalizedAgentID),
                    "session_id": .string(normalizedSessionID),
                    "reason": .string(reason),
                    "error": .string("session_unavailable"),
                ]
            )
            return
        }
        guard !projectID.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            _ = await self.enqueueSelfImprovementProposalReview(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                projectID: projectID,
                reason: reason,
                reviewContext: reviewContext
            )
            await self.runSelfImprovementProposalReviewQueue()
        }
    }

    @discardableResult
    private func enqueueSelfImprovementProposalReview(
        agentID: String,
        sessionID: String,
        projectID: String,
        reason: String,
        reviewContext: String? = nil
    ) async -> SelfImprovementProposalReviewJob {
        await store.upsertSelfImprovementProposalReviewJob(
            agentId: agentID,
            sessionId: sessionID,
            projectId: projectID,
            reason: reason,
            reviewContext: reviewContext,
            nextRunAt: Date()
        )
    }

    func enqueueSelfImprovementProposalReviewForTests(
        agentID: String,
        sessionID: String,
        projectID: String,
        reason: String,
        reviewContext: String? = nil
    ) async -> SelfImprovementProposalReviewJob {
        await enqueueSelfImprovementProposalReview(
            agentID: agentID,
            sessionID: sessionID,
            projectID: projectID,
            reason: reason,
            reviewContext: reviewContext
        )
    }

    func listSelfImprovementProposalReviewJobsForTests() async -> [SelfImprovementProposalReviewJob] {
        await store.listSelfImprovementProposalReviewJobs(statuses: nil)
    }

    func forceSelfImprovementProposalReviewJobDueForTests(_ id: String) async {
        let jobs = await store.listSelfImprovementProposalReviewJobs(statuses: nil)
        guard var job = jobs.first(where: { $0.id == id }) else { return }
        job.status = "pending"
        job.nextRunAt = Date()
        job.updatedAt = Date()
        await store.saveSelfImprovementProposalReviewJob(job)
    }

    func runSelfImprovementProposalReviewQueueForTests() async {
        await runSelfImprovementProposalReviewQueue()
    }

    private func runSelfImprovementProposalReviewQueue() async {
        guard !selfImprovementProposalReviewQueueRunning else { return }
        selfImprovementProposalReviewQueueRunning = true
        defer { selfImprovementProposalReviewQueueRunning = false }

        while var job = await store.claimNextSelfImprovementProposalReviewJob(now: Date()) {
            let result = await runScheduledSelfImprovementProposalReview(job: job)
            let now = Date()
            job.attempts += 1
            job.updatedAt = now
            switch result {
            case .success:
                job.status = "succeeded"
                job.lastError = nil
            case .failure(let error):
                job.lastError = error
                job.status = job.attempts >= 3 ? "failed" : "pending"
                job.nextRunAt = now.addingTimeInterval(TimeInterval(60 * max(1, job.attempts)))
                await appendSelfImprovementReviewSummary(
                    agentID: job.agentId,
                    sessionID: job.sessionId,
                    review: AgentSelfImprovementReviewEvent(
                        category: "proposal",
                        jobId: job.id,
                        summary: "Self-improvement review failed: \(error)",
                        actions: ["proposal review failed: \(error)"],
                        reason: job.reason
                    )
                )
                logger.warning(
                    "self_improvement.proposal.queue_failed",
                    metadata: [
                        "actor_id": .string("system:self-improvement"),
                        "job_id": .string(job.id),
                        "agent_id": .string(job.agentId),
                        "session_id": .string(job.sessionId),
                        "reason": .string(job.reason),
                        "error": .string(error),
                    ]
                )
            }
            await store.saveSelfImprovementProposalReviewJob(job)
        }
    }

    private enum SelfImprovementProposalReviewRunResult {
        case success
        case failure(String)
    }

    private func runScheduledSelfImprovementProposalReview(job: SelfImprovementProposalReviewJob) async -> SelfImprovementProposalReviewRunResult {
        logger.info(
            "self_improvement.proposal.background_started",
            metadata: [
                "job_id": .string(job.id),
                "agent_id": .string(job.agentId),
                "session_id": .string(job.sessionId),
                "reason": .string(job.reason),
            ]
        )
        let result = await runSelfImprovementProposalReview(
            agentID: job.agentId,
            sessionID: job.sessionId,
            reason: job.reason,
            reviewContext: job.reviewContext,
            jobID: job.id
        )
        logger.info(
            "self_improvement.proposal.background_completed",
            metadata: [
                "job_id": .string(job.id),
                "agent_id": .string(job.agentId),
                "session_id": .string(job.sessionId),
                "reason": .string(job.reason),
            ]
        )
        if let error = result {
            return .failure(error)
        }
        return .success
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
        _ = await runSelfImprovementProposalReview(
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
        reviewContext: String? = nil,
        jobID: String? = nil
    ) async -> String? {
        guard let normalizedAgentID = normalizedAgentID(agentID) else { return "invalid_agent_id" }
        guard let normalizedSessionID = normalizedSessionID(sessionID) else { return "invalid_session_id" }

        let lockKey = selfImprovementProposalReviewLockKey(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        guard !selfImprovementProposalReviewLocks.contains(lockKey) else {
            logger.info(
                "self_improvement.proposal.skipped_overlap",
                metadata: [
                    "agent_id": .string(normalizedAgentID),
                    "session_id": .string(normalizedSessionID),
                ]
            )
            return "overlapping_review"
        }
        selfImprovementProposalReviewLocks.insert(lockKey)
        defer { selfImprovementProposalReviewLocks.remove(lockKey) }

        do {
            _ = try getAgent(id: normalizedAgentID)
        } catch {
            logger.warning("self_improvement.proposal.agent_unavailable", metadata: ["agent_id": .string(normalizedAgentID)])
            return "agent_unavailable"
        }

        let detail: AgentSessionDetail
        do {
            detail = try sessionStore.loadSession(agentID: normalizedAgentID, sessionID: normalizedSessionID)
        } catch {
            logger.warning("self_improvement.proposal.session_unavailable", metadata: ["error": .string(error.localizedDescription)])
            return "session_unavailable"
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
            return "project_unavailable"
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
            return "agent_config_unavailable"
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
            var effectiveRequest = request
            if request.tool == "self_improvement.proposal_submit",
               reviewContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                effectiveRequest.arguments["failureReview"] = .bool(true)
            }
            let result = await self.invokeSelfImprovementProposalTool(
                agentID: normalizedAgentID,
                sessionID: normalizedSessionID,
                projectID: project.id,
                request: effectiveRequest
            )
            await actionRecorder.record(result)
            return result
        }

        let userPrompt = """
        Run the self-improvement proposal review now. If there is no durable, reusable improvement proposal, reply exactly: Nothing to propose.
        If there is a proposal, submit one structured intent with `self_improvement.proposal_submit`. Do not address the end user.
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

        if let review = await actionRecorder.review(reason: reason, jobID: jobID) {
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
        return nil
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
        if request.tool == "self_improvement.proposal_submit" {
            return await handleSelfImprovementProposalSubmit(
                agentID: agentID,
                sessionID: sessionID,
                projectID: projectID,
                arguments: request.arguments
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
            guard toolID != "self_improvement.proposal_submit" else { continue }
            policy.tools[toolID] = true
        }
        let effectiveRequest = request
        return await toolExecution.invoke(
            agentID: agentID,
            sessionID: sessionID,
            request: effectiveRequest,
            policy: policy,
            currentProjectID: projectID,
            currentDirectoryURL: currentDirectoryURL
        )
    }

    private func handleSelfImprovementProposalSubmit(
        agentID: String,
        sessionID: String,
        projectID: String,
        arguments: [String: JSONValue]
    ) async -> ToolInvocationResult {
        let request = SelfImprovementProposalSubmitRequest(arguments: arguments)
        switch request.action {
        case .nothing:
            return ToolInvocationResult(
                tool: "self_improvement.proposal_submit",
                ok: true,
                data: .object(["action": .string("nothing")])
            )
        case .create:
            return await createSelfImprovementProposalTask(
                projectID: projectID,
                request: request
            )
        case .update:
            return await updateSelfImprovementProposalTask(
                projectID: projectID,
                request: request
            )
        }
    }

    private func createSelfImprovementProposalTask(
        projectID: String,
        request: SelfImprovementProposalSubmitRequest
    ) async -> ToolInvocationResult {
        if let qualityResult = Self.selfImprovementProposalQualityResult(request) {
            return qualityResult
        }
        if let validationFailure = Self.selfImprovementProposalValidationFailure(request) {
            return validationFailure
        }

        let subsystem = Self.normalizedProposalSubsystem(request.affectedSubsystem)
        let description = request.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            let updated = try await createProjectTask(
                projectID: projectID,
                request: ProjectTaskCreateRequest(
                    title: request.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Self-improvement proposal",
                    description: description,
                    priority: "medium",
                    status: ProjectTaskStatus.pendingApproval.rawValue,
                    kind: .planning,
                    tags: Self.normalizedProposalTags(subsystem: subsystem),
                    changedBy: "system:self-improvement"
                )
            )
            let created = updated.tasks.sorted { $0.createdAt > $1.createdAt }.first
            return ToolInvocationResult(
                tool: "self_improvement.proposal_submit",
                ok: true,
                data: .object([
                    "action": .string("create"),
                    "projectId": .string(updated.id),
                    "taskId": .string(created?.id ?? ""),
                    "title": .string(created?.title ?? request.title ?? ""),
                    "status": .string(created?.status ?? ""),
                ])
            )
        } catch {
            return ToolInvocationResult(
                tool: "self_improvement.proposal_submit",
                ok: false,
                error: ToolErrorPayload(
                    code: "proposal_create_failed",
                    message: "Failed to create self-improvement proposal task.",
                    retryable: true
                )
            )
        }
    }

    private func updateSelfImprovementProposalTask(
        projectID: String,
        request: SelfImprovementProposalSubmitRequest
    ) async -> ToolInvocationResult {
        if let qualityResult = Self.selfImprovementProposalQualityResult(request) {
            return qualityResult
        }
        if let validationFailure = Self.selfImprovementProposalValidationFailure(request) {
            return validationFailure
        }
        guard let taskID = request.existingTaskID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !taskID.isEmpty,
              let project = await store.project(id: projectID),
              let task = project.tasks.first(where: { $0.id == taskID && Self.activeSelfImprovementProposalStatusesForReview.contains($0.status) }),
              !task.isArchived,
              task.tags.contains("self-improvement"),
              task.tags.contains("proposal")
        else {
            return ToolInvocationResult(
                tool: "self_improvement.proposal_submit",
                ok: false,
                error: ToolErrorPayload(
                    code: "proposal_task_not_active",
                    message: "`update` requires an active existing self-improvement proposal task id.",
                    retryable: false
                )
            )
        }

        let updatedDescription = Self.descriptionByAppendingProposalEvidence(
            task.description,
            evidence: request.evidence,
            testsVerification: request.testsVerification
        )
        do {
            let updated = try await updateProjectTask(
                projectID: projectID,
                taskID: task.id,
                request: ProjectTaskUpdateRequest(
                    description: updatedDescription,
                    changedBy: "system:self-improvement"
                )
            )
            let updatedTask = updated.tasks.first(where: { $0.id == task.id }) ?? task
            return ToolInvocationResult(
                tool: "self_improvement.proposal_submit",
                ok: true,
                data: .object([
                    "action": .string("update"),
                    "projectId": .string(updated.id),
                    "taskId": .string(updatedTask.id),
                    "title": .string(updatedTask.title),
                    "status": .string(updatedTask.status),
                    "task": taskJSONValue(updatedTask),
                ])
            )
        } catch {
            return ToolInvocationResult(
                tool: "self_improvement.proposal_submit",
                ok: false,
                error: ToolErrorPayload(
                    code: "proposal_update_failed",
                    message: "Failed to update self-improvement proposal task.",
                    retryable: true
                )
            )
        }
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

        Allowed tools only: `visor.status`, `project.current`, `project.task_list`, `self_improvement.proposal_submit`.
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

        Before submitting a proposal, compare with existing proposal tasks. If an active task already covers the same issue, submit `action: "update"` with `existingTaskID` and added evidence instead of creating a duplicate.
        Submit at most one proposal intent per review.

        Proposal submit requirements:
        - tool: `self_improvement.proposal_submit`
        - `action`: `nothing`, `create`, or `update`
        - `confidence`: at least 0.7 for `create` or `update`
        - `durability`: at least 0.7 for `create` or `update`
        - `affectedSubsystem`: one affected subsystem tag such as `skills`, `runtime`, `tools`, `memory`, `dashboard`, `prompts`, or `mcp`
        - `evidence`: at least one typed evidence item
        - `testsVerification`: required verification commands or focused test names
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

    private static let requiredSelfImprovementProposalHeadings = [
        "Goal",
        "Context",
        "Observed Issue",
        "Evidence",
        "Suggested Change",
        "Risk",
        "Affected Subsystem",
        "Definition of Done",
        "Tests / Verification",
    ]

    private static let activeSelfImprovementProposalStatusesForReview: Set<String> = [
        ProjectTaskStatus.pendingApproval.rawValue,
        ProjectTaskStatus.backlog.rawValue,
        ProjectTaskStatus.ready.rawValue,
        ProjectTaskStatus.inProgress.rawValue,
        ProjectTaskStatus.waitingInput.rawValue,
        ProjectTaskStatus.needsReview.rawValue,
    ]

    private static func selfImprovementProposalQualityResult(
        _ request: SelfImprovementProposalSubmitRequest
    ) -> ToolInvocationResult? {
        if (request.confidence ?? 0) < 0.7 || (request.durability ?? 0) < 0.7 {
            return ToolInvocationResult(
                tool: "self_improvement.proposal_submit",
                ok: true,
                data: .object([
                    "action": .string("nothing"),
                    "reason": .string("confidence_or_durability_below_threshold"),
                ])
            )
        }
        return nil
    }

    private static func selfImprovementProposalValidationFailure(
        _ request: SelfImprovementProposalSubmitRequest
    ) -> ToolInvocationResult? {
        guard request.confidence != nil,
              request.durability != nil,
              let subsystem = request.affectedSubsystem?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subsystem.isEmpty,
              let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              let description = request.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty,
              let tests = request.testsVerification?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tests.isEmpty
        else {
            return proposalSubmitFailure(
                code: "proposal_required_fields_missing",
                message: "`create` and `update` require confidence, durability, affectedSubsystem, title, description, and testsVerification."
            )
        }

        guard !request.evidence.isEmpty else {
            return proposalSubmitFailure(
                code: "proposal_evidence_required",
                message: "`create` and `update` require at least one evidence item."
            )
        }

        let missingHeadings = requiredSelfImprovementProposalHeadings.filter { heading in
            !proposalDescriptionContainsHeading(heading, in: description)
        }
        guard missingHeadings.isEmpty else {
            return proposalSubmitFailure(
                code: "proposal_headings_missing",
                message: "Proposal description is missing required headings: \(missingHeadings.joined(separator: ", "))."
            )
        }

        if request.failureReview {
            guard let classification = request.failureClassification ?? failureClassification(in: description),
                  classification != .ignore
            else {
                return proposalSubmitFailure(
                    code: "failure_classification_required",
                    message: "Failure review proposal tasks must include a valid failureClassification."
                )
            }
        }
        return nil
    }

    private static func proposalSubmitFailure(code: String, message: String) -> ToolInvocationResult {
        ToolInvocationResult(
            tool: "self_improvement.proposal_submit",
            ok: false,
            error: ToolErrorPayload(code: code, message: message, retryable: false)
        )
    }

    private static func normalizedProposalSubsystem(_ raw: String?) -> String {
        let trimmed = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return trimmed?.isEmpty == false ? trimmed! : "general"
    }

    private static func normalizedProposalTags(subsystem: String) -> [String] {
        Array(Set(["self-improvement", "proposal", subsystem]))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private static func proposalDescriptionContainsHeading(_ heading: String, in description: String) -> Bool {
        let target = "## \(heading)".lowercased()
        return description
            .split(separator: "\n", omittingEmptySubsequences: false)
            .contains { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
            }
    }

    private static func descriptionByAppendingProposalEvidence(
        _ description: String,
        evidence: [SelfImprovementProposalEvidence],
        testsVerification: String?
    ) -> String {
        var section = """
        ## Additional Evidence
        \(evidence.map(\.markdownLine).joined(separator: "\n"))
        """
        if let tests = testsVerification?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tests.isEmpty {
            section += """

            Verification:
            \(tests)
            """
        }
        return description.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + section
    }

    private static func normalizedFailureClassification(_ raw: String) -> SelfImprovementFailureClassification? {
        let normalized = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "-*: `"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return SelfImprovementFailureClassification(rawValue: normalized)
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
        case "project.task_create", "self_improvement.proposal_submit":
            guard result.data?.asObject?["action"]?.asString != "update" else {
                let taskID = payload["taskId"]?.asString ?? ""
                let title = payload["title"]?.asString ?? ""
                if !taskID.isEmpty {
                    updatedTasks.append((id: taskID, title: title))
                }
                return
            }
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

    func review(reason: String, jobID: String? = nil) -> AgentSelfImprovementReviewEvent? {
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
            category: "proposal",
            jobId: jobID,
            summary: "Self-improvement review: \(actions.joined(separator: ", "))",
            actions: actions,
            reason: reason
        )
    }
}
