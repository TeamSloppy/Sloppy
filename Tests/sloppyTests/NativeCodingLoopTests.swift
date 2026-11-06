import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy
private typealias JSONValue = Protocols.JSONValue

private enum NativeCodingCase: CaseIterable {
    case buildCompleted, buildFreshEvidence, debugCompleted, buildMissingCompletion, debugWaitingInput, debugWaitingInputInterruptSkipped
    case planWaitingInput, buildSeparate, buildLegacyPlanning
    case autoBuildCompleted, autoBuildMissingCompletion
    case debugResumesInput
    case debugResumesInputAfterRestart
    case workerCompleted, workerMissingCompletion, workerResumesInputAfterRestart
    var isWorker: Bool { self == .workerCompleted || self == .workerMissingCompletion || self == .workerResumesInputAfterRestart }
    var resumesInput: Bool { self == .debugResumesInput || self == .debugResumesInputAfterRestart || self == .workerResumesInputAfterRestart }
    var selectsRoute: Bool { self == .autoBuildCompleted || self == .autoBuildMissingCompletion }
    var usesPlanner: Bool { self == .buildSeparate || self == .buildLegacyPlanning }
    var waitsForInput: Bool { self == .debugWaitingInput || self == .debugWaitingInputInterruptSkipped || self == .planWaitingInput || resumesInput }
    var mode: AgentChatMode { selectsRoute ? .auto : (self == .planWaitingInput ? .plan : (self == .debugCompleted || waitsForInput ? .debug : .build)) }
    var completes: Bool { self != .workerMissingCompletion && self != .buildMissingCompletion && self != .autoBuildMissingCompletion }
}

private struct CodingDeclaration: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String
    let name: String
    var description: String { "Native coding declaration" }
    var parameters: GenerationSchema {
        switch name {
        case "runtime.exec": RuntimeExecTool().parameters
        case "planning.request_input": PlanningRequestInputTool().parameters
        case "planning.select_route": PlanningSelectRouteTool().parameters
        case "agent_delegate.finish": AgentDelegateFinishTool().parameters
        default: SessionCompleteTool().parameters
        }
    }
    func call(arguments: GeneratedContent) async throws -> String {
        throw ModelStepFailure(category: .protocolViolation, code: "provider_executed_tool", message: "A declaration cannot execute work")
    }
}

private actor CodingScript: ModelStepProvider {
    let fixture: URL
    let completes: Bool
    let waitsForInput: Bool
    let usesPlanner: Bool
    let selectsRoute: Bool
    let resumesInput: Bool
    let isWorker: Bool
    private var workSteps = 0
    private(set) var requests: [ModelStepRequest] = []
    private(set) var legacyCalls = 0
    init(fixture: URL, completes: Bool, waitsForInput: Bool, usesPlanner: Bool = false, selectsRoute: Bool = false, resumesInput: Bool = false, isWorker: Bool = false) {
        self.fixture = fixture; self.completes = completes; self.waitsForInput = waitsForInput; self.usesPlanner = usesPlanner
        self.selectsRoute = selectsRoute
        self.resumesInput = resumesInput
        self.isWorker = isWorker
    }
    func legacy() { legacyCalls += 1 }
    private func next(_ request: ModelStepRequest) throws -> ModelStepResponse {
        requests.append(request)
        if usesPlanner, request.tools.isEmpty {
            return .init(text: "Inspect the fixture, build it, then complete with verification.", stopReason: .endTurn)
        }
        workSteps += 1
        if selectsRoute, workSteps == 1 {
            #expect(request.messages.contains { $0.text.contains("mode-build") })
            return .init(toolCalls: [.init(id: "route", name: "planning_select_route", rawArguments: #"{"route":"mode-build"}"#)], stopReason: .toolCalls)
        }
        let executionStep = workSteps - (selectsRoute ? 1 : 0)
        if usesPlanner {
            #expect(request.messages.contains { $0.text.contains("[Planner output]") })
        }
        if executionStep == 1 || (resumesInput && executionStep == 2) {
            let arguments: [String: JSONValue] = ["command": .string("swift"), "cwd": .string(fixture.path),
                "arguments": .array(["build", "--package-path", fixture.path, "--scratch-path", fixture.appendingPathComponent(".build").path].map(JSONValue.string))]
            let raw = String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
            var calls = [ModelStepToolCall(id: "build", name: "runtime_exec", rawArguments: raw)]
            if waitsForInput && executionStep == 1 {
                calls.insert(.init(id: "input", name: "planning_request_input", rawArguments:
                    #"{"title":"Choose target","questions":[{"id":"choice","question":"Which target?","options":[{"id":"fixture","label":"Fixture"},{"id":"other","label":"Other"}]}]}"#), at: 0)
            }
            return .init(toolCalls: calls, stopReason: .toolCalls)
        }
        if executionStep == (resumesInput ? 3 : 2), completes {
            let output = request.messages.last(where: { $0.toolOutput != nil })?.toolOutput?.content ?? "{}"
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(output.utf8))
            let evidence = value.asObject?["data"]?.asObject?["verificationEvidence"]?.asObject?["id"]?.asString
            let arguments: [String: JSONValue] = ["status": .string("completed"), "summary": .string("Built and verified the fixture."),
                "verificationEvidenceIds": .array(evidence.map { [.string($0)] } ?? [])]
            let raw = String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
            if isWorker {
                let raw = #"{"status":"completed","summary":"Built and verified the fixture."}"#
                return .init(toolCalls: [.init(id: "complete", name: "agent_delegate_finish", rawArguments: raw),
                    .init(id: "after-finish", name: "runtime_exec", rawArguments: #"{"command":"swift","arguments":["--version"]}"#)], stopReason: .toolCalls)
            }
            return .init(toolCalls: [.init(id: "complete", name: "session_complete", rawArguments: raw)], stopReason: .toolCalls)
        }
        return .init(text: "The fixture build was reported without a finalizer.", stopReason: .endTurn)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    continuation.yield(.started)
                    continuation.yield(.final(try await self.next(request)))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}

private struct CodingFactory: ModelProvider, ModelStepProviderFactory {
    let id = "native-coding-fixture"
    let supportedModels = ["openai-api:gpt-5.4-mini"]
    let script: CodingScript
    var tools: [any Tool] {
        [CodingDeclaration(name: "runtime.exec"), CodingDeclaration(name: "session.complete"), CodingDeclaration(name: "planning.request_input"), CodingDeclaration(name: "planning.select_route"), CodingDeclaration(name: "agent_delegate.finish")]
    }
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        await script.legacy()
        throw ModelStepFailure(category: .protocolViolation, code: "legacy_planner_used", message: "Executor planning must stay in the shared loop")
    }
}

private actor CodingPauseDeliveryProbe {
    private(set) var wasCancelled = false
    func record(_ value: Bool) { wasCancelled = value }
}

@Suite("Native coding modes")
struct NativeCodingLoopTests {
    @Test(arguments: NativeCodingCase.allCases)
    fileprivate func executorPolicyUsesRealVerificationAndRequiredCompletion(scenario: NativeCodingCase) async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        await service.setToolApprovalPresenter { _ in .approve(.once) }
        let workspace = await service.workspaceRootURL
        let fixture = workspace.appendingPathComponent("verification-fixture")
        let sources = fixture.appendingPathComponent("Sources/Fixture")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: \"Fixture\", targets: [.target(name: \"Fixture\")])\n"
            .write(to: fixture.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "public let fixtureValue = 1\n".write(to: sources.appendingPathComponent("Value.swift"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let script = CodingScript(fixture: fixture, completes: scenario.completes, waitsForInput: scenario.waitsForInput,
            usesPlanner: scenario.usesPlanner, selectsRoute: scenario.selectsRoute, resumesInput: scenario.resumesInput, isWorker: scenario.isWorker)
        await service.overrideModelProviderForTests(CodingFactory(script: script), defaultModel: "openai-api:gpt-5.4-mini")
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let agentID = "native-coding-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native coding fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false, autoApproveInput: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified,
                planningPolicy: scenario == .buildSeparate ? .separate : (scenario == .buildLegacyPlanning ? .legacy : .executor),
                evidencePolicyVersion: scenario == .buildFreshEvidence ? 2 : nil)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native coding fixture"))
        if scenario.isWorker {
            await orchestrator.markDelegatedSubagentSession(sessionID: session.id)
            await service.installNativeWorkerScopeForTests(sessionID: session.id, workingDirectory: fixture.path, includesInput: scenario.resumesInput)
        }
        let messageID = UUID().uuidString
        let pauseGate = SessionStepGate()
        let pauseProbe = CodingPauseDeliveryProbe()
        defer { Task { await pauseGate.release() } }
        if scenario == .debugWaitingInputInterruptSkipped {
            await orchestrator.updateEventAppendObserver { _, _, _, events in
                if events.contains(where: { event in
                    guard let raw = event.runtimeMetadata?.runState,
                          let snapshot = try? JSONValueCoder.decode(RunStateSnapshot.self, from: raw) else { return false }
                    return snapshot.phase == .finalizing && snapshot.completion?.disposition == .waitingInput
                }) {
                    await pauseGate.hold()
                    await pauseProbe.record(Task.isCancelled)
                }
            }
        }
        let post = Task {
            try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: "Build the prepared verification-fixture Swift package and report its recorded verification.",
                    mode: scenario.mode, clientMessageId: messageID))
        }
        if scenario == .debugWaitingInputInterruptSkipped {
            let held = await pauseGate.waitUntilHeld(during: post)
            if !held { await pauseGate.release(); _ = try await post.value }
            try #require(held)
            let before = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
            let questionID = try #require(before.events.compactMap(\.inputRequest).last?.id)
            let control = try await service.controlAgentSession(agentID: agentID, sessionID: session.id,
                request: .init(action: .interrupt, requestedBy: "fixture"))
            #expect(control.appendedEvents.isEmpty)
            let after = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
            #expect(after.events.compactMap(\.inputRequest).last?.id == questionID)
            await pauseGate.release()
        }
        var response: AgentSessionMessageResponse?
        do { response = try await post.value } catch { }
        if scenario.resumesInput {
            let paused = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
            let question = try #require(paused.events.compactMap(\.inputRequest).last)
            let resumeService: CoreService
            if scenario == .debugResumesInputAfterRestart || scenario == .workerResumesInputAfterRestart {
                await service.stop()
                resumeService = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
                await resumeService.waitForStartup(dispatchReadyTasks: false)
                await resumeService.setToolApprovalPresenter { _ in .approve(.once) }
                await resumeService.overrideModelProviderForTests(CodingFactory(script: script), defaultModel: models[0].id)
                await resumeService.sessionOrchestrator.updateAvailableModels(models)
            } else { resumeService = service }
            let answer = PlanInputAnswerRequest(answers: [.init(questionId: "choice", selectedOptionId: "fixture")], userId: "fixture")
            response = try await resumeService.answerAgentPlanInput(agentID: agentID, sessionID: session.id, requestID: question.id, payload: answer)
            let beforeRetry = try await resumeService.getAgentSession(agentID: agentID, sessionID: session.id)
            let replay = try await resumeService.answerAgentPlanInput(agentID: agentID, sessionID: session.id, requestID: question.id, payload: answer)
            #expect(replay.replayed == true)
            #expect(try await resumeService.getAgentSession(agentID: agentID, sessionID: session.id).events == beforeRetry.events)
        }
        if scenario == .debugWaitingInputInterruptSkipped { #expect(await pauseProbe.wasCancelled == false) }
        #expect(response != nil)
        let requests = await script.requests
        #expect(requests.count == (scenario.resumesInput ? 3 : (scenario.waitsForInput ? 1 : (scenario.completes ? 2 : 5))) +
            (scenario.usesPlanner ? 1 : 0) + (scenario.selectsRoute ? 1 : 0))
        #expect(await script.legacyCalls == 0)
        let store = await service.sessionStore
        let detail = try store.loadSession(agentID: agentID, sessionID: session.id)
        let waiting = scenario.waitsForInput && !scenario.resumesInput
        if scenario.resumesInput {
            #expect(Set(requests.map(\.runId)).count == 1)
            #expect(Set(requests.map(\.userTurnId)) == [messageID])
            #expect(detail.events.filter { $0.message?.role == .user && $0.runtimeMetadata?.presentationOnly != true }.count == 1)
            #expect(detail.summary.userTurnCount == 1)
        }
        let verified = detail.events.compactMap { $0.runtimeMetadata?.verificationEvidence }.flatMap { $0 }
        #expect(verified.count == (waiting ? 0 : 1))
        #expect(verified.first?.asObject?["tool"]?.asString == (waiting ? nil : "runtime.exec"))
        #expect(verified.first?.asObject?["id"]?.asString == (waiting ? nil : "verification-1"))
        #expect(detail.events.contains { $0.toolResult?.tool == "runtime.exec" && $0.toolResult?.ok == true } == !waiting)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started && $0.runtimeMetadata?.providerCallId == "build" }.count == (waiting ? 0 : 1))
        let journal = SessionLoopJournal(store: store, agentID: agentID, sessionID: session.id, authorizeWriter: {})
        let restored = try await journal.restoreRunState(userTurnID: messageID)
        #expect(restored != nil)
        if let restored {
            let snapshot = await restored.snapshot()
            #expect(snapshot.verificationEvidence.count == (waiting ? 0 : 1))
            #expect(snapshot.loopConfig?.requiresExplicitCompletion == (scenario.mode != .plan))
            if scenario.isWorker {
                #expect(snapshot.loopConfig?.completionContract == .worker)
                #expect(snapshot.requestSettings?.toolScope == (scenario.resumesInput
                    ? ["agent_delegate.finish", "planning.request_input", "runtime.exec"] : ["agent_delegate.finish", "runtime.exec"]))
                #expect(snapshot.requestSettings?.delegatedAuthority?.workingDirectory == fixture.path)
                #expect(snapshot.requestSettings?.delegatedAuthority?.extraRoots == [fixture.path])
                if scenario.completes {
                    #expect(detail.events.contains { $0.runtimeMetadata?.providerCallId == "after-finish" && $0.toolResult?.error?.code == "not_executed_after_completion" })
                }
            }
            if waiting {
                #expect(snapshot.phase == .settled)
                #expect(snapshot.generation == 0)
                let input = detail.events.compactMap(\.inputRequest).last
                #expect(input != nil)
                #expect(snapshot.completion?.disposition == .waitingInput)
                #expect(snapshot.completion?.inputRequestId == input?.id)
                #expect(detail.events.contains { $0.runtimeMetadata?.providerCallId == "build" && $0.toolResult?.error?.code == "not_executed_after_completion" })
                #expect(detail.events.last(where: { $0.runStatus != nil })?.runStatus?.stage == .paused)
                #expect(!FileManager.default.fileExists(atPath: fixture.appendingPathComponent(".build").path))
            } else if scenario.completes {
                #expect(snapshot.completion?.summary == "Built and verified the fixture.")
                #expect(snapshot.phase == .settled)
            } else {
                #expect(snapshot.completion == nil)
                #expect(snapshot.toolStop?.reason == .missingCompletion)
            }
        }
    }
}

private extension CoreService {
    func installNativeWorkerScopeForTests(sessionID: String, workingDirectory: String, includesInput: Bool) async {
        var scope: Set<String> = ["runtime.exec", "agent_delegate.finish"]
        if includesInput { scope.insert("planning.request_input") }
        sessionWorkingDirectories[sessionID] = workingDirectory
        sessionExtraRoots[sessionID] = [workingDirectory]
        sessionSubagentToolAllowList[sessionID] = scope
    }
}
