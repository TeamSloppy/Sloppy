import Foundation
import AnyLanguageModel
import Testing
@testable import PluginSDK
@testable import Protocols
@testable import sloppy

@Suite("Workflow agent execution", .timeLimit(.minutes(1)))
struct WorkflowAgentExecutionTests {
    @Test(arguments: ["agent", "ai_transform"])
    func runsRealSessionAndPersistsResult(blockKind: String) async throws {
        let probe = WorkflowModelProbe(gated: true)
        let (service, projectID, agentID, workflow) = try await fixture(probe: probe, blockKind: blockKind)
        let task = Task {
            try await service.startWorkflowRun(projectID: projectID, workflowID: workflow.id,
                                               request: .init(startedBy: "human:admin", input: ["ticket": .string("WF-42")]))
        }
        defer { task.cancel(); Task { await probe.release(); await service.shutdownChannelPlugins() } }
        var starts = probe.started.makeAsyncIterator()
        _ = await starts.next()
        let running = try #require(await service.listWorkflowRuns(projectID: projectID).first)
        let detail = try await service.getWorkflowRunDetail(projectID: projectID, runID: running.id)
        let step = try #require(detail.steps.first { $0.nodeId == "agent" })
        #expect(running.status == .running)
        #expect(step.status == .running)
        let sessionID = try #require(step.output["sessionId"]?.asString)
        #expect(step.output["agentId"] == .string(agentID))
        await probe.release()
        let finished = try await task.value
        #expect(finished.run.id == running.id)
        #expect(finished.run.status == .completed)
        let completed = try #require(finished.steps.first { $0.nodeId == "agent" })
        #expect(completed.id == step.id)
        #expect(completed.status == .succeeded)
        #expect(completed.output["text"] == .string("Workflow model answer"))
        #expect(completed.output["sessionId"] == .string(sessionID))
        let session = try await service.getAgentSession(agentID: agentID, sessionID: sessionID)
        #expect(session.summary.projectId == projectID)
        #expect(session.events.contains { $0.message?.role == .user && $0.message?.userId == "workflow" && $0.message?.segments.contains { $0.text?.contains("WF-42") == true } == true })
        #expect(session.events.contains { $0.message?.role == .assistant && $0.message?.segments.contains { $0.text == "Workflow model answer" } == true })
        #expect(session.events.compactMap(\.runStatus).last?.executionOutcome?.state == .completed)
        #expect(await probe.prompts.contains { $0.contains("Work on WF-42") && $0.contains("[Workflow input]") })
    }

    @Test
    func providerFailureFailsRunWithoutReachingEnd() async throws {
        let probe = WorkflowModelProbe(failing: true)
        let (service, projectID, _, workflow) = try await fixture(probe: probe)
        let result = try await service.startWorkflowRun(projectID: projectID, workflowID: workflow.id,
                                                       request: .init(startedBy: "human", input: ["ticket": .string("WF-42")]))
        #expect(result.run.status == .failed)
        let step = try #require(result.steps.first { $0.nodeId == "agent" })
        #expect(step.status == .failed)
        #expect(step.output["sessionId"]?.asString != nil)
        #expect(step.error != nil)
        #expect(!result.steps.contains { $0.nodeId == "done" })
        await service.shutdownChannelPlugins()
    }

    @Test(arguments: [ExecutionState.failed, .cancelled, .waitingInput, .waitingApproval, .interrupted])
    func nonCompletedOutcomesNeverCountAsSuccess(state: ExecutionState) {
        let response = AgentSessionMessageResponse(
            summary: AgentSessionSummary(id: "session", agentId: "agent", title: "Workflow"),
            appendedEvents: [AgentSessionEvent(agentId: "agent", sessionId: "session", type: .runStatus,
                runStatus: AgentRunStatusEvent(stage: .done, label: "Successfully completed", executionOutcome: .init(state: state)))], routeDecision: nil
        )
        let result = CoreService.workflowAgentResult(response: response, output: ["sessionId": .string("session")])
        #expect(!result.ok)
        #expect(result.data?.asObject?["sessionId"] == .string("session"))
    }

    @Test
    func missingTerminalOutcomeDoesNotCountAsSuccess() {
        let response = AgentSessionMessageResponse(summary: .init(id: "session", agentId: "agent", title: "Workflow"), appendedEvents: [], routeDecision: nil)
        #expect(!CoreService.workflowAgentResult(response: response, output: [:]).ok)
    }

    @Test
    func forwardsOnlyAssistantTextToFollowingSteps() {
        let response = AgentSessionMessageResponse(summary: .init(id: "session", agentId: "agent", title: "Workflow"), appendedEvents: [
            AgentSessionEvent(agentId: "agent", sessionId: "session", type: .message,
                message: AgentSessionMessage(id: "message", role: .assistant, segments: [
                    AgentMessageSegment(kind: .thinking, text: "Internal reasoning"),
                    AgentMessageSegment(kind: .text, text: "Final answer")
                ])),
            AgentSessionEvent(agentId: "agent", sessionId: "session", type: .runStatus,
                runStatus: AgentRunStatusEvent(stage: .done, label: "Done", executionOutcome: .completed))
        ], routeDecision: nil)
        let result = CoreService.workflowAgentResult(response: response, output: [:])
        #expect(result.ok)
        #expect(result.data?.asObject?["text"] == .string("Final answer"))
    }

    @Test(arguments: ["agentId", "prompt"])
    func missingConfigurationDoesNotCreateSession(key: String) async throws {
        let (service, projectID, agentID, workflow) = try await fixture(probe: WorkflowModelProbe())
        var nodes = workflow.nodes
        nodes[1].config.removeValue(forKey: key)
        _ = try await service.updateWorkflowDefinition(projectID: projectID, workflowID: workflow.id,
                                                       request: .init(name: workflow.name, lanes: workflow.lanes, nodes: nodes, edges: workflow.edges))
        let result = try await service.startWorkflowRun(projectID: projectID, workflowID: workflow.id,
                                                       request: .init(startedBy: "human", input: ["ticket": .string("WF-42")]))
        #expect(result.run.status == .failed)
        #expect(try await service.listAgentSessions(agentID: agentID).isEmpty)
        await service.shutdownChannelPlugins()
    }

    @Test
    func passesAgentAnswerToNextFreshSession() async throws {
        let probe = WorkflowModelProbe()
        let (service, projectID, agentID, workflow) = try await fixture(probe: probe)
        var nodes = workflow.nodes
        var review = nodes[1]
        review.id = "review"
        review.config["prompt"] = .string("Review {{nodes.agent.output.text}}")
        nodes.insert(review, at: 2)
        _ = try await service.updateWorkflowDefinition(projectID: projectID, workflowID: workflow.id,
            request: .init(name: workflow.name, lanes: workflow.lanes, nodes: nodes, edges: [
                workflow.edges[0], WorkflowEdge(id: "e2", sourceNodeId: "agent", targetNodeId: "review"),
                WorkflowEdge(id: "e3", sourceNodeId: "review", targetNodeId: "done")
            ]))
        let result = try await service.startWorkflowRun(projectID: projectID, workflowID: workflow.id, request: .init(startedBy: "human", input: ["ticket": .string("WF-42")]))
        #expect(result.run.status == .completed)
        #expect(await probe.prompts.contains { $0.contains("Review Workflow model answer") })
        #expect(try await service.listAgentSessions(agentID: agentID).count == 2)
        await service.shutdownChannelPlugins()
    }

    @Test
    func concurrentStartsReturnTheirOwnRun() async throws {
        let probe = WorkflowModelProbe(gated: true)
        let (service, projectID, _, workflow) = try await fixture(probe: probe)
        let first = Task { try await service.startWorkflowRun(projectID: projectID, workflowID: workflow.id, request: .init(startedBy: "first", input: ["ticket": .string("WF-42")])) }
        defer { first.cancel(); Task { await probe.release(); await service.shutdownChannelPlugins() } }
        var starts = probe.started.makeAsyncIterator()
        _ = await starts.next()
        let firstRun = try #require(await service.listWorkflowRuns(projectID: projectID).first)
        let second = Task { try await service.startWorkflowRun(projectID: projectID, workflowID: workflow.id, request: .init(startedBy: "second", input: ["ticket": .string("WF-42")])) }
        defer { second.cancel() }
        _ = await starts.next()
        #expect(await service.listWorkflowRuns(projectID: projectID).count == 2)
        await probe.release()
        let a = try await first.value
        let b = try await second.value
        #expect(a.run.id == firstRun.id)
        #expect(a.run.id != b.run.id)
        #expect(a.run.startedBy == "first")
        #expect(b.run.startedBy == "second")
    }

    @Test(arguments: ["code", "sub_workflow"])
    func unsupportedAutomationCannotSucceed(blockKind: String) async throws {
        let (service, projectID, _, workflow) = try await fixture(probe: WorkflowModelProbe())
        var nodes = workflow.nodes
        nodes[1].type = .toolCheck
        nodes[1].config = ["blockKind": .string(blockKind), "language": .string("swift"), "workflowId": .string(workflow.id)]
        _ = try await service.updateWorkflowDefinition(projectID: projectID, workflowID: workflow.id,
            request: .init(name: workflow.name, lanes: workflow.lanes, nodes: nodes, edges: workflow.edges))
        let result = try await service.startWorkflowRun(projectID: projectID, workflowID: workflow.id, request: .init(startedBy: "human", input: ["ticket": .string("WF-42")]))
        #expect(result.run.status == .failed)
        #expect(!result.steps.contains { $0.nodeId == "done" })
        #expect(await service.listWorkflowRuns(projectID: projectID).count == 1)
        await service.shutdownChannelPlugins()
    }

    private func fixture(probe: WorkflowModelProbe, blockKind: String = "agent") async throws -> (CoreService, String, String, WorkflowDefinition) {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: probe), defaultModel: "mock:test-model")
        let projectID = "workflow-agent-\(UUID().uuidString.lowercased())"
        let agentID = "worker-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Workflow", description: "", channels: []))
        _ = try await service.createAgent(.init(id: agentID, displayName: "Workflow worker", role: "Assistant"))
        let workflow = try await service.createWorkflowDefinition(projectID: projectID, request: .init(
            name: "Agent workflow", lanes: [WorkflowLane(id: "system", title: "System", kind: .system)],
            nodes: [
                WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
                WorkflowNode(id: "agent", type: .agentStep, title: "Agent", laneId: "system", config: [
                    "blockKind": .string(blockKind), "agentId": .string(agentID), "mode": .string("ask"),
                    "model": .string("mock:test-model"), "prompt": .string("Work on {{input.ticket}}")
                ]),
                WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system")
            ], edges: [WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "agent"), WorkflowEdge(id: "e2", sourceNodeId: "agent", targetNodeId: "done")]
        ))
        return (service, projectID, agentID, workflow)
    }
}

actor WorkflowModelProbe {
    nonisolated let started: AsyncStream<Void>
    private let events: AsyncStream<Void>.Continuation
    private let gated: Bool
    private let failing: Bool
    private let answers: [String]
    private var requestsInput: Bool
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var prompts: [String] = []

    init(gated: Bool = false, failing: Bool = false, requestsInput: Bool = false, answers: [String] = ["Workflow model answer"]) {
        let stream = AsyncStream<Void>.makeStream()
        started = stream.stream
        events = stream.continuation
        self.gated = gated
        self.failing = failing
        self.answers = answers
        self.requestsInput = requestsInput
    }

    func takeInputRequest() -> Bool {
        let result = requestsInput
        requestsInput = false
        return result
    }

    func response(prompt: String) async throws -> String {
        prompts.append(prompt)
        events.yield(())
        if gated && !released { await withCheckedContinuation { waiters.append($0) } }
        if failing { throw WorkflowModelError.unavailable }
        return answers.isEmpty ? "" : answers[min(prompts.count - 1, answers.count - 1)]
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private enum WorkflowModelError: Error { case unavailable, unsupportedContent }

actor WorkflowModelProvider: ModelProvider {
    nonisolated let id = "workflow-test"
    nonisolated let supportedModels = ["mock:test-model"]
    let probe: WorkflowModelProbe
    init(probe: WorkflowModelProbe) { self.probe = probe }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { WorkflowLanguageModel(probe: probe) }
}

private struct WorkflowLanguageModel: LanguageModel {
    typealias UnavailableReason = Never
    let probe: WorkflowModelProbe
    func respond<Content>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type, includeSchemaInPrompt: Bool, options: GenerationOptions) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard type == String.self else { throw WorkflowModelError.unsupportedContent }
        if await probe.takeInputRequest() {
            guard let delegate = session.toolExecutionDelegate else { throw WorkflowModelError.unavailable }
            let call = Transcript.ToolCall(id: UUID().uuidString, toolName: "planning.request_input",
                arguments: try GeneratedContent(json: #"{"questions":[{"id":"choice","question":"Continue?","options":[{"id":"yes","label":"Yes"},{"id":"no","label":"No"}]}]}"#))
            await delegate.didGenerateToolCalls([call], in: session)
            let decision = await delegate.toolCallDecision(for: call, in: session)
            var entries: [Transcript.Entry] = [.toolCalls(.init([call]))]
            if case .provideOutput(let segments) = decision {
                let output = Transcript.ToolOutput(id: call.id, toolName: call.toolName, segments: segments)
                await delegate.didExecuteToolCall(call, output: output, in: session)
                entries.append(.toolOutput(output))
            }
            return .init(content: "Input requested" as! Content, rawContent: GeneratedContent("Input requested"), transcriptEntries: ArraySlice(entries))
        }
        let text = try await probe.response(prompt: prompt.description)
        return .init(content: text as! Content, rawContent: GeneratedContent(text), transcriptEntries: [])
    }
    func streamResponse<Content>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type, includeSchemaInPrompt: Bool, options: GenerationOptions) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                do {
                    let response = try await respond(within: session, to: prompt, generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
                    continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
        return .init(stream: stream)
    }
}
