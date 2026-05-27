import AnyLanguageModel
import Foundation
import Logging
import Testing
@testable import PluginSDK
@testable import Protocols
@testable import sloppy

private struct SelfImprovementProposalToolCallModel: LanguageModel {
    typealias UnavailableReason = Never

    let arguments: GeneratedContent

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard type == String.self else {
            fatalError("SelfImprovementProposalToolCallModel only supports String responses")
        }

        var entries: [Transcript.Entry] = []
        if let delegate = session.toolExecutionDelegate {
            let toolCall = Transcript.ToolCall(
                id: "proposal-call-1",
                toolName: "project.task_create",
                arguments: arguments
            )
            await delegate.didGenerateToolCalls([toolCall], in: session)
            let decision = await delegate.toolCallDecision(for: toolCall, in: session)
            if case .provideOutput(let segments) = decision {
                let output = Transcript.ToolOutput(id: toolCall.id, toolName: toolCall.toolName, segments: segments)
                await delegate.didExecuteToolCall(toolCall, output: output, in: session)
                entries.append(.toolCalls(Transcript.ToolCalls([toolCall])))
                entries.append(.toolOutput(output))
            }
        }

        let text = "Proposal review completed."
        return LanguageModelSession.Response(
            content: text as! Content,
            rawContent: GeneratedContent(text),
            transcriptEntries: ArraySlice(entries)
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                guard let response = try? await respond(
                    within: session,
                    to: prompt,
                    generating: type,
                    includeSchemaInPrompt: includeSchemaInPrompt,
                    options: options
                ) else {
                    continuation.finish()
                    return
                }
                continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                continuation.finish()
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

private actor SelfImprovementProposalModelProvider: ModelProvider {
    nonisolated let id: String = "self-improvement-proposal"
    nonisolated let supportedModels: [String] = ["mock:proposal"]

    let arguments: GeneratedContent

    init(arguments: GeneratedContent) {
        self.arguments = arguments
    }

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        SelfImprovementProposalToolCallModel(arguments: arguments)
    }
}

private struct SelfImprovementFailureSignalToolCallModel: LanguageModel {
    typealias UnavailableReason = Never

    let toolName: String

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard type == String.self else {
            fatalError("SelfImprovementFailureSignalToolCallModel only supports String responses")
        }

        var entries: [Transcript.Entry] = []
        if let delegate = session.toolExecutionDelegate {
            let toolCall = Transcript.ToolCall(
                id: "failure-call-1",
                toolName: toolName,
                arguments: GeneratedContent(properties: [:])
            )
            await delegate.didGenerateToolCalls([toolCall], in: session)
            let decision = await delegate.toolCallDecision(for: toolCall, in: session)
            if case .provideOutput(let segments) = decision {
                let output = Transcript.ToolOutput(id: toolCall.id, toolName: toolCall.toolName, segments: segments)
                await delegate.didExecuteToolCall(toolCall, output: output, in: session)
                entries.append(.toolCalls(Transcript.ToolCalls([toolCall])))
                entries.append(.toolOutput(output))
            }
        }

        let text = "Completed after observing the tool failure."
        return LanguageModelSession.Response(
            content: text as! Content,
            rawContent: GeneratedContent(text),
            transcriptEntries: ArraySlice(entries)
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                guard let response = try? await respond(
                    within: session,
                    to: prompt,
                    generating: type,
                    includeSchemaInPrompt: includeSchemaInPrompt,
                    options: options
                ) else {
                    continuation.finish()
                    return
                }
                continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                continuation.finish()
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

private actor SelfImprovementFailureReviewSequenceProvider: ModelProvider {
    nonisolated let id: String = "self-improvement-failure-review"
    nonisolated let supportedModels: [String] = ["mock:failure-review"]

    private let proposalArguments: GeneratedContent
    private var createCount = 0

    init(proposalArguments: GeneratedContent) {
        self.proposalArguments = proposalArguments
    }

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        createCount += 1
        if createCount == 1 {
            return SelfImprovementFailureSignalToolCallModel(toolName: "missing.runtime_tool")
        }
        return SelfImprovementProposalToolCallModel(arguments: proposalArguments)
    }
}

@Test
func selfImprovementProposalAllowlistExcludesDirectMutationTools() async throws {
    #expect(CoreService.selfImprovementProposalToolAllowlist.contains("project.task_create"))
    #expect(CoreService.selfImprovementProposalToolAllowlist.contains("project.task_update"))
    #expect(!CoreService.selfImprovementProposalToolAllowlist.contains("runtime.exec"))
    #expect(!CoreService.selfImprovementProposalToolAllowlist.contains("files.write"))
    #expect(!CoreService.selfImprovementProposalToolAllowlist.contains("web.search"))
    #expect(!CoreService.selfImprovementProposalToolAllowlist.contains("mcp.install"))
    #expect(!CoreService.selfImprovementProposalToolAllowlist.contains("agent.skills.install"))

    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let agentID = "proposal-deny-\(UUID().uuidString.lowercased())"
    let projectID = "proposal-deny-project-\(UUID().uuidString.lowercased())"
    _ = try await service.createAgent(AgentCreateRequest(id: agentID, displayName: "Proposal Deny", role: "Testing"))
    _ = try await service.createProject(ProjectCreateRequest(id: projectID, name: "Proposal Deny Project"))
    let session = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Proposal Deny", projectId: projectID)
    )

    let denied = await service.invokeSelfImprovementProposalTool(
        agentID: agentID,
        sessionID: session.id,
        projectID: projectID,
        request: ToolInvocationRequest(
            tool: "files.write",
            arguments: ["path": .string("SKILL.md"), "content": .string("mutation")]
        )
    )

    #expect(denied.ok == false)
    #expect(denied.error?.code == "proposal_tool_not_allowed")
}

@Test
func selfImprovementProposalReviewCreatesTaggedProjectTaskWithEvidence() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let agentID = "proposal-review-\(UUID().uuidString.lowercased())"
    let projectID = "proposal-review-project-\(UUID().uuidString.lowercased())"
    _ = try await service.createAgent(AgentCreateRequest(id: agentID, displayName: "Proposal Review", role: "Testing"))
    _ = try await service.createProject(ProjectCreateRequest(id: projectID, name: "Proposal Review Project"))
    let session = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Proposal Review", projectId: projectID)
    )

    let description = """
    ## Goal
    Improve the Build mode OCR workflow.

    ## Context
    The completed session showed the agent asking for pasted screenshot text even though local OCR was available.

    ## Observed Issue
    The agent delayed useful work by treating image text extraction as unavailable.

    ## Evidence
    Session `\(session.id)` included a user correction about OCR being possible in Build mode.

    ## Suggested Change
    Add mode guidance to attempt available OCR tools before asking the user to paste screenshot text.

    ## Risk
    Low; guidance affects workflow selection only.

    ## Affected Subsystem
    skills

    ## Definition of Done
    Build mode guidance covers OCR-capable screenshot handling.

    ## Tests / Verification
    Add a prompt/snapshot test for image-text workflow guidance.
    """

    let provider = SelfImprovementProposalModelProvider(arguments: GeneratedContent(properties: [
        "projectId": projectID,
        "title": "Self-improvement proposal: Build mode OCR workflow",
        "description": description,
        "priority": "medium",
        "status": ProjectTaskStatus.pendingApproval.rawValue,
        "kind": ProjectTaskKind.planning.rawValue,
        "tags": GeneratedContent(elements: ["skills"] as [any ConvertibleToGeneratedContent])
    ]))
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:proposal")

    await service.runSelfImprovementProposalReview(
        agentID: agentID,
        sessionID: session.id,
        reason: "test"
    )

    let project = try await service.getProject(id: projectID)
    let task = try #require(project.tasks.first { $0.title == "Self-improvement proposal: Build mode OCR workflow" })
    #expect(task.status == ProjectTaskStatus.pendingApproval.rawValue)
    #expect(task.kind == .planning)
    #expect(task.tags.contains("self-improvement"))
    #expect(task.tags.contains("proposal"))
    #expect(task.tags.contains("skills"))
    #expect(task.description.contains("## Observed Issue"))
    #expect(task.description.contains("## Evidence"))
    #expect(task.description.contains("## Suggested Change"))
    #expect(task.description.contains("## Risk"))
    #expect(task.description.contains("## Affected Subsystem"))

    let logs = try await service.listTaskLogs(projectID: projectID, taskID: task.id)
    #expect(logs.contains { $0.kind == "lifecycle" && $0.actorId == "system:self-improvement" })

    let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
    let review = try #require(detail.events.last(where: { $0.type == .selfImprovementReview })?.selfImprovementReview)
    #expect(review.summary.contains("proposal task \(task.id) created"))
    #expect(review.reason == "test")
}

@Test
func selfImprovementFailureReviewTriggersProposalWithClassification() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let agentID = "failure-review-\(UUID().uuidString.lowercased())"
    let projectID = "failure-review-project-\(UUID().uuidString.lowercased())"
    _ = try await service.createAgent(AgentCreateRequest(id: agentID, displayName: "Failure Review", role: "Testing"))
    _ = try await service.createProject(ProjectCreateRequest(id: projectID, name: "Failure Review Project"))
    let session = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Failure Review", projectId: projectID)
    )

    let description = """
    ## Goal
    Make missing runtime tool calls reviewable.

    ## Context
    A completed session attempted to call a tool that was not registered.

    ## Observed Issue
    The agent selected an unavailable tool instead of using the available tool catalog.

    ## Evidence
    Session `\(session.id)` recorded `unknown_tool` for `missing.runtime_tool`.

    ## Suggested Change
    Add prompt or runtime guidance that steers agents to inspect the tool catalog before invoking uncertain tool names.

    ## Risk
    Low; this only affects tool-selection guidance.

    ## Affected Subsystem
    tools

    ## Failure Classification
    missing tool

    ## Definition of Done
    Failure reviews create a classified proposal task for unknown tool failures.

    ## Tests / Verification
    Cover unknown-tool failure review scheduling with a focused service test.
    """

    let provider = SelfImprovementFailureReviewSequenceProvider(
        proposalArguments: GeneratedContent(properties: [
            "projectId": projectID,
            "title": "Self-improvement proposal: Unknown tool failure review",
            "description": description,
            "priority": "medium",
            "status": ProjectTaskStatus.pendingApproval.rawValue,
            "kind": ProjectTaskKind.planning.rawValue,
            "tags": GeneratedContent(elements: ["tools"] as [any ConvertibleToGeneratedContent])
        ])
    )
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:failure-review")

    let response = try await service.postAgentSessionMessage(
        agentID: agentID,
        sessionID: session.id,
        request: AgentSessionPostMessageRequest(userId: "dashboard", content: "Try the missing tool.")
    )
    #expect(response.appendedEvents.contains { $0.runStatus?.stage == .done })

    let created = await waitForSelfImprovementProposalCondition(timeoutNanoseconds: 5_000_000_000) {
        guard let project = try? await service.getProject(id: projectID) else {
            return false
        }
        return project.tasks.contains { $0.title == "Self-improvement proposal: Unknown tool failure review" }
    }
    #expect(created)

    let project = try await service.getProject(id: projectID)
    let task = try #require(project.tasks.first { $0.title == "Self-improvement proposal: Unknown tool failure review" })
    #expect(task.tags.contains("self-improvement"))
    #expect(task.tags.contains("proposal"))
    #expect(task.tags.contains("tools"))
    #expect(task.description.contains("## Failure Classification"))
    #expect(task.description.contains("missing tool"))

    let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
    #expect(detail.events.contains { $0.toolResult?.error?.code == "unknown_tool" })
    let review = try #require(detail.events.last(where: { $0.type == .selfImprovementReview })?.selfImprovementReview)
    #expect(review.reason.hasPrefix("failure_review:"))
}

@Test
func selfImprovementFailureSignalExtractionDetectsRuntimeFailures() {
    let agentID = "failure-signals-agent"
    let sessionID = "failure-signals-session"
    let turnEvents = [
        AgentSessionEvent(
            agentId: agentID,
            sessionId: sessionID,
            type: .toolResult,
            toolResult: AgentToolResultEvent(
                tool: "files.write",
                ok: false,
                error: ToolErrorPayload(code: "tool_forbidden", message: "Tool disabled.", retryable: false)
            )
        ),
        AgentSessionEvent(
            agentId: agentID,
            sessionId: sessionID,
            type: .toolResult,
            toolResult: AgentToolResultEvent(
                tool: "runtime.exec",
                ok: true,
                data: .object(["timedOut": .bool(true)])
            )
        ),
        AgentSessionEvent(
            agentId: agentID,
            sessionId: sessionID,
            type: .toolResult,
            toolResult: AgentToolResultEvent(tool: "project.task_clarification_create", ok: true)
        ),
        AgentSessionEvent(
            agentId: agentID,
            sessionId: sessionID,
            type: .toolResult,
            toolResult: AgentToolResultEvent(tool: "project.task_clarification_create", ok: true)
        ),
    ]

    let signals = CoreService.selfImprovementFailureSignals(
        turnEvents: turnEvents,
        responseEvents: [
            AgentSessionEvent(
                agentId: agentID,
                sessionId: sessionID,
                type: .runStatus,
                runStatus: AgentRunStatusEvent(
                    stage: .interrupted,
                    label: "Incomplete",
                    details: "Agent reached the tool turn limit before producing a final answer."
                )
            )
        ]
    )
    let kinds = Set(signals.map(\.kind))
    #expect(kinds.contains("tool_forbidden"))
    #expect(kinds.contains("tool_timeout"))
    #expect(kinds.contains("repeated_clarification"))
    #expect(kinds.contains("turn_limit"))
}

@Test
func selfImprovementFailureClassificationRequiresStructuredHeading() {
    let valid = """
    ## Goal
    Improve tool selection.

    ## Failure Classification
    policy issue
    """
    #expect(CoreService.failureClassification(in: valid) == .policyIssue)
    #expect(CoreService.proposalDescriptionHasRequiredFailureClassification(valid))
    #expect(!CoreService.proposalDescriptionHasRequiredFailureClassification("## Failure Classification\nmaybe"))
}

@Test
func selfImprovementCuratorCreatesPatchPlanAndAnnotatesDuplicates() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let projectID = "curator-project-\(UUID().uuidString.lowercased())"
    _ = try await service.createProject(ProjectCreateRequest(id: projectID, name: "Curator Project"))

    let firstProject = try await service.createProjectTask(
        projectID: projectID,
        request: ProjectTaskCreateRequest(
            title: "Self-improvement proposal: Build mode OCR workflow",
            description: curatorProposalDescription(
                title: "Improve Build mode OCR workflow",
                subsystem: "skills",
                classification: nil,
                evidence: "The agent asked for pasted screenshot text even though OCR tooling was available."
            ),
            priority: "medium",
            status: ProjectTaskStatus.pendingApproval.rawValue,
            kind: .planning,
            tags: ["self-improvement", "proposal", "skills"],
            changedBy: "system:self-improvement"
        )
    )
    let firstTask = try #require(firstProject.tasks.first { $0.title == "Self-improvement proposal: Build mode OCR workflow" })

    let secondProject = try await service.createProjectTask(
        projectID: projectID,
        request: ProjectTaskCreateRequest(
            title: "Self-improvement proposal: Build mode OCR workflow duplicate",
            description: curatorProposalDescription(
                title: "Improve Build mode OCR workflow duplicate",
                subsystem: "skills",
                classification: nil,
                evidence: "A later session repeated the same OCR workflow issue."
            ),
            priority: "medium",
            status: ProjectTaskStatus.pendingApproval.rawValue,
            kind: .planning,
            tags: ["self-improvement", "proposal", "skills"],
            changedBy: "system:self-improvement"
        )
    )
    let secondTask = try #require(secondProject.tasks.first { $0.title == "Self-improvement proposal: Build mode OCR workflow duplicate" })

    let result = await service.runSelfImprovementCurator(projectID: projectID, reason: "test-weekly")

    #expect(result.proposalCount == 2)
    #expect(result.duplicateGroupCount == 1)
    #expect(result.proposalTasksUpdated == 2)
    #expect(result.patchPlanCreated)
    #expect(result.patchPlanTaskID != nil)

    let project = try await service.getProject(id: projectID)
    let refreshedFirst = try #require(project.tasks.first { $0.id == firstTask.id })
    let refreshedSecond = try #require(project.tasks.first { $0.id == secondTask.id })
    #expect(refreshedFirst.description.contains("## Curator Duplicate Group"))
    #expect(refreshedFirst.description.contains(secondTask.id))
    #expect(refreshedSecond.description.contains("## Curator Duplicate Group"))
    #expect(refreshedSecond.description.contains(firstTask.id))

    let patchPlan = try #require(project.tasks.first { task in
        task.tags.contains("self-improvement") &&
            task.tags.contains("curator") &&
            task.tags.contains("patch-plan")
    })
    #expect(patchPlan.status == ProjectTaskStatus.pendingApproval.rawValue)
    #expect(patchPlan.kind == .planning)
    #expect(patchPlan.description.contains("## Duplicate Groups"))
    #expect(patchPlan.description.contains("## Patch Plan"))
    #expect(patchPlan.description.contains(firstTask.id))
    #expect(patchPlan.description.contains(secondTask.id))

    let logs = try await service.listTaskLogs(projectID: projectID, taskID: patchPlan.id)
    #expect(logs.contains { $0.kind == "lifecycle" && $0.actorId == "system:self-improvement-curator" })
}

@Test
func selfImprovementCuratorRefreshesExistingPatchPlan() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let projectID = "curator-refresh-\(UUID().uuidString.lowercased())"
    _ = try await service.createProject(ProjectCreateRequest(id: projectID, name: "Curator Refresh"))

    _ = try await service.createProjectTask(
        projectID: projectID,
        request: ProjectTaskCreateRequest(
            title: "Self-improvement proposal: Unknown tool failure review",
            description: curatorProposalDescription(
                title: "Review unknown tool failures",
                subsystem: "tools",
                classification: "missing tool",
                evidence: "Session recorded unknown_tool for a generated tool call."
            ),
            priority: "medium",
            status: ProjectTaskStatus.pendingApproval.rawValue,
            kind: .planning,
            tags: ["self-improvement", "proposal", "tools"],
            changedBy: "system:self-improvement"
        )
    )
    let created = await service.runSelfImprovementCurator(projectID: projectID, reason: "first")
    let patchPlanID = try #require(created.patchPlanTaskID)

    let updatedProject = try await service.updateProjectTask(
        projectID: projectID,
        taskID: patchPlanID,
        request: ProjectTaskUpdateRequest(
            description: "stale",
            changedBy: "user"
        )
    )
    #expect(updatedProject.tasks.first(where: { $0.id == patchPlanID })?.description == "stale")

    let refreshed = await service.runSelfImprovementCurator(projectID: projectID, reason: "second")
    #expect(!refreshed.patchPlanCreated)
    #expect(refreshed.patchPlanUpdated)
    #expect(refreshed.patchPlanTaskID == patchPlanID)

    let project = try await service.getProject(id: projectID)
    let patchPlan = try #require(project.tasks.first { $0.id == patchPlanID })
    #expect(patchPlan.description.contains("Curator run reason: second"))
    #expect(patchPlan.description.contains("Unknown tool failure review"))
}

@Test
func scheduledSelfImprovementCuratorAggregatesProjects() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let firstProjectID = "curator-scheduled-a-\(UUID().uuidString.lowercased())"
    let secondProjectID = "curator-scheduled-b-\(UUID().uuidString.lowercased())"
    _ = try await service.createProject(ProjectCreateRequest(id: firstProjectID, name: "Curator Scheduled A"))
    _ = try await service.createProject(ProjectCreateRequest(id: secondProjectID, name: "Curator Scheduled B"))
    _ = try await service.createProjectTask(
        projectID: firstProjectID,
        request: ProjectTaskCreateRequest(
            title: "Self-improvement proposal: Runtime timeout handling",
            description: curatorProposalDescription(
                title: "Runtime timeout handling",
                subsystem: "runtime",
                classification: "runtime bug",
                evidence: "A tool timeout was not explained clearly."
            ),
            status: ProjectTaskStatus.pendingApproval.rawValue,
            kind: .planning,
            tags: ["self-improvement", "proposal", "runtime"],
            changedBy: "system:self-improvement"
        )
    )

    let result = await service.runScheduledSelfImprovementCurator(reason: "weekly-test")
    #expect(result.projectsReviewed == 1)
    #expect(result.proposalsReviewed == 1)
    #expect(result.patchPlanTasksCreated == 1)
    #expect(result.projectResults.first?.projectID == firstProjectID)

    let secondProject = try await service.getProject(id: secondProjectID)
    #expect(secondProject.tasks.isEmpty)
}

@Test
func selfImprovementCuratorRunnerSkipsOverlappingRuns() async {
    let probe = SelfImprovementCuratorRunnerProbe()
    let runner = SelfImprovementCuratorRunner(
        config: SelfImprovementCuratorRunnerConfig(interval: .seconds(60), jitter: .seconds(0)),
        logger: Logger(label: "sloppy.tests.self-improvement.curator")
    ) {
        await probe.run()
    }

    async let firstRun = runner.triggerImmediately()
    await probe.waitUntilBlocked()
    async let overlappingRun = runner.triggerImmediately()

    let overlappingStarted = await overlappingRun
    #expect(!overlappingStarted)

    await probe.releaseRun()
    let firstStarted = await firstRun
    #expect(firstStarted)

    let counts = await probe.counts()
    #expect(counts.started == 1)
    #expect(counts.finished == 1)
}

private actor SelfImprovementCuratorRunnerProbe {
    private var startedCount = 0
    private var finishedCount = 0
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    func run() async {
        startedCount += 1
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            blockedWaiters.forEach { $0.resume() }
            blockedWaiters.removeAll()
        }
        finishedCount += 1
    }

    func waitUntilBlocked() async {
        if releaseContinuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseRun() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func counts() -> (started: Int, finished: Int) {
        (startedCount, finishedCount)
    }
}

private func curatorProposalDescription(
    title: String,
    subsystem: String,
    classification: String?,
    evidence: String
) -> String {
    var sections = [
        """
        ## Goal
        \(title)
        """,
        """
        ## Context
        Captured by self-improvement proposal review.
        """,
        """
        ## Observed Issue
        The runtime behavior should be improved.
        """,
        """
        ## Evidence
        \(evidence)
        """,
        """
        ## Suggested Change
        Create an approval-gated patch task before changing skills, prompts, runtime behavior, or tools.
        """,
        """
        ## Risk
        Low if changes stay reviewable.
        """,
        """
        ## Affected Subsystem
        \(subsystem)
        """,
    ]
    if let classification {
        sections.append(
            """
            ## Failure Classification
            \(classification)
            """
        )
    }
    sections += [
        """
        ## Definition of Done
        Proposal has a clear approval path.
        """,
        """
        ## Tests / Verification
        Run the narrow tests for the affected subsystem.
        """,
    ]
    return sections.joined(separator: "\n\n")
}

private func waitForSelfImprovementProposalCondition(
    timeoutNanoseconds: UInt64,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return await condition()
}
