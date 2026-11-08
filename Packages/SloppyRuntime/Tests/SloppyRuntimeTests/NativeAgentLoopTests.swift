import Foundation
@testable import AgentRuntime
import AnyLanguageModel
import PluginSDK
import Protocols
import SloppyRuntime
import Testing

private enum OutcomeTailCase: CaseIterable { case verified, late, denied }
private enum TerminalCancelCase: CaseIterable { case answer, completion, alreadyAccepted, restoredSettled }

private actor RetrySettingsSleepProbe {
    private(set) var delays: [Duration] = []
    func record(_ delay: Duration) { delays.append(delay) }
}

private actor StepScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    private(set) var legacyCalls = 0
    var steps: [[ModelStepEvent]]
    var failures: [Int: ModelStepFailure] = [:]
    init(events: [ModelStepEvent]) { self.steps = [events] }
    init(steps: [[ModelStepEvent]], failures: [Int: ModelStepFailure] = [:]) { self.steps = steps; self.failures = failures }
    func recordLegacy() { legacyCalls += 1 }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let events = try await self.next(request)
                    for event in events { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
    private func next(_ request: ModelStepRequest) throws -> [ModelStepEvent] {
        requests.append(request)
        if let failure = failures[requests.count] { throw failure }
        return steps.isEmpty ? [] : steps.removeFirst()
    }
}

private actor LoopJournalProbe: AgentLoopJournal, AgentLoopInstructionJournal, AgentLoopOutcomeJournal {
    var preparations = 0
    var trace: [String] = []
    var messages: [ModelStepMessage] = []
    var failurePhase: String?
    var outcomes: [AgentLoopToolOutcome] = []
    init(failurePhase: String? = nil) { self.failurePhase = failurePhase }
    func record(_ phase: String) throws {
        if phase == failurePhase { throw CocoaError(.fileWriteOutOfSpace) }
        trace.append(phase)
    }
    func prepareRequest(_ request: ModelStepRequest) throws -> ModelStepRequest {
        preparations += 1
        var prepared = request
        prepared.messages += messages
        return prepared
    }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) throws {
        try record("assistant")
        messages.append(.init(role: .assistant, text: response.text, toolCalls: response.toolCalls))
    }
    func appendRequested(_ calls: [AgentLoopCall], request: ModelStepRequest) throws { try record("requested") }
    func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) throws { try record("started") }
    func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) throws {
        try record("result")
        let content = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        messages.append(.init(role: .tool, toolOutput: .init(callId: call.call.id, name: call.call.name, content: content)))
    }
    func effect() throws { try record("effect") }
    func appendOutcome(_ outcome: AgentLoopToolOutcome, call: AgentLoopCall, request: ModelStepRequest) throws {
        try appendResult(outcome.result, call: call, request: request)
        outcomes.append(outcome)
    }
    func appendInstruction(_ instruction: AgentRunInstruction, request: ModelStepRequest) {
        messages.append(.init(id: instruction.id, role: .user, text: instruction.text))
    }
}

private func loopRequest() -> ModelStepRequest {
    .init(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt", model: "script:model",
        projectionRevision: "1", cacheScope: "session", messages: [.init(role: .user, text: "Read the file")],
        tools: [.init(name: "files_read", toolId: "files.read", parameters: .object([
            "type": .string("object"), "properties": .object(["path": .object(["type": .string("string")])]),
            "required": .array([.string("path")]), "additionalProperties": .bool(false)
        ]), readOnly: true, concurrencySafe: true)])
}

private actor ConcurrentEffects {
    var active = 0
    var maximumActive = 0
    var finished: [String] = []
    var barrierWasExclusive = false
    func begin(_ id: String) {
        if id == "write" { barrierWasExclusive = active == 0 && Set(finished) == ["read-1", "read-2"] }
        active += 1
        maximumActive = max(maximumActive, active)
    }
    func finish(_ id: String) { active -= 1; finished.append(id) }
}

private actor CancellableStepScript: ModelStepProvider {
    var didStart = false
    var didCancel = false
    var startWaiters: [CheckedContinuation<Void, Never>] = []
    func waitForStart() async {
        if didStart { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func started() {
        didStart = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
    }
    func cancelled() { didCancel = true }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let gate = AsyncStream<Void>.makeStream()
            let producer = Task {
                continuation.yield(.started)
                await self.started()
                for await _ in gate.stream { }
                if Task.isCancelled {
                    await self.cancelled()
                    continuation.finish(throwing: CancellationError())
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}

private actor NativeRunStartGate {
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrivalWaiters: [String: AsyncStream<Bool>.Continuation] = [:]
    func hold() async {
        entered = true
        for waiter in arrivalWaiters.values { waiter.yield(true); waiter.finish() }
        arrivalWaiters.removeAll()
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func isEntered() -> Bool { entered }
    func waitUntilHeld<T: Sendable>(during operation: Task<T, Error>) async -> Bool {
        if entered { return true }
        let id = UUID().uuidString
        let subscription = AsyncStream<Bool>.makeStream()
        arrivalWaiters[id] = subscription.continuation
        let completion = Task { [weak self] in
            _ = try? await operation.value
            await self?.finishArrival(id)
        }
        defer { completion.cancel(); arrivalWaiters.removeValue(forKey: id)?.finish() }
        for await value in subscription.stream { return value }
        return false
    }
    private func finishArrival(_ id: String) {
        guard let waiter = arrivalWaiters.removeValue(forKey: id) else { return }
        waiter.yield(false)
        waiter.finish()
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private struct StepScriptFactory: ModelProvider, ModelStepProviderFactory {
    let id = "step-script"
    let supportedModels = ["script:model"]
    let script: StepScript
    var tools: [any Tool] = []
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        await script.recordLegacy()
        throw ModelStepFailure(category: .protocolViolation, code: "legacy_path_used", message: "Legacy generation was invoked")
    }
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
}

private struct DeclaredReadTool: Tool {
    @Generable struct Arguments { var path: String }
    typealias Output = String
    let name = "files.read"
    let description = "Read the requested complete file"
    func call(arguments: Arguments) async throws -> String {
        throw ModelStepFailure(category: .protocolViolation, code: "executable_closure_used", message: "A provider invoked an executable tool closure")
    }
}

private actor LoopObservationProbe {
    var calls: [ToolInvocationRequest] = []
    var results: [ToolInvocationResult] = []
    var usage: [TokenUsage] = []
    func record(_ observation: RuntimeResponseObservation) {
        switch observation {
        case .toolCall(let call): calls.append(call)
        case .toolResult(let result): results.append(result)
        case .usage(let value): usage.append(value)
        case .thinking: break
        }
    }
}

private struct ResultWriteFaultJournal: AgentLoopStateJournal {
    let base: SessionLoopJournal
    func prepareRequest(_ request: ModelStepRequest) async throws -> ModelStepRequest { try await base.prepareRequest(request) }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) async throws { try await base.appendResponse(response, request: request) }
    func appendRequested(_ calls: [AgentLoopCall], request: ModelStepRequest) async throws { try await base.appendRequested(calls, request: request) }
    func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) async throws { try await base.appendStarted(call, request: request) }
    func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) async throws { throw CocoaError(.fileWriteOutOfSpace) }
    func appendRunState(_ snapshot: RunStateSnapshot, request: ModelStepRequest) async throws { try await base.appendRunState(snapshot, request: request) }
    func restoreRunState(userTurnID: String?) async throws -> RunState? { try await base.restoreRunState(userTurnID: userTurnID) }
}

private final class OwnedCancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@Suite("Unified native model steps")
struct NativeAgentLoopTests {
    @Test(.timeLimit(.minutes(3)))
    func largeToolOutputIsArchivedBeforeItsBoundedProjection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tool-artifact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {}, externalizeToolOutputs: false)
        let state = RunState(runID: "run", userTurnID: "turn")
        let payload = String(repeating: "Complete Unicode output: привет 🌲\n", count: 2_000)
        let script = StepScript(steps: [
            [.started, .final(.init(toolCalls: [.init(id: "read", name: "files_read", rawArguments: #"{"path":"large.txt"}"#)], stopReason: .toolCalls))],
            [.started, .final(.init(toolCalls: [.init(id: "small-read", name: "files_read", rawArguments: #"{"path":"small.txt"}"#)], stopReason: .toolCalls))],
            [.started, .final(.init(text: "Saved full output.", stopReason: .endTurn))]
        ])
        _ = try await AgentLoop(provider: script, state: state).run(loopRequest(), journal: journal,
            executor: .init { _, definition, arguments, start in
                try await start()
                return .init(tool: definition.toolId, ok: true, data: .string(arguments["path"]?.asString == "large.txt" ? payload : "Small current result."))
            },
            config: .init(engine: .unified, requiresExplicitCompletion: false))
        let requests = await script.requests
        #expect(requests.count == 3)
        if requests.count >= 2 {
            let currentOutput = try #require(requests[1].messages.compactMap(\.toolOutput).first)
            #expect(currentOutput.content.utf8.count > 8_192)
            #expect(currentOutput.content.contains("Complete Unicode output"))
        }
        let projected = try #require(requests.last?.messages.compactMap(\.toolOutput).first)
        #expect(projected.content.utf8.count < 8_192)
        let detail = try store.loadSession(agentID: "agent", sessionID: session.id)
        let result = try #require(detail.events.first { $0.toolResult != nil })
        #expect(result.toolResult?.data == .string(payload))
        let metadata = try #require(JSONValueCoder.encode(result.runtimeMetadata).asObject)
        let artifact = try #require(metadata["toolOutputArtifact"]?.asObject)
        let attachment = try JSONValueCoder.decode(AgentAttachment.self, from: #require(artifact["attachment"]))
        let bytes = try store.readInputAttachment(agentID: "agent", sessionID: session.id, attachment: attachment)
        #expect(ContentDigest.sha256(bytes) == artifact["sha256"]?.asString)
        #expect(try JSONDecoder().decode(ToolInvocationResult.self, from: bytes).data == .string(payload))
        #expect(projected.content.contains(attachment.id))
        #expect(projected.content.contains(artifact["sha256"]?.asString ?? "missing-digest"))
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let prepared = try await fresh.prepareRequest(loopRequest())
        #expect(prepared.messages.compactMap(\.toolOutput).first?.content == projected.content)
        // A corrupt artifact cannot silently replace the complete canonical observation.
        let file = try #require(try store.resolveAttachmentFileURL(agentID: "agent", attachment: attachment))
        try Data("corrupt".utf8).write(to: file)
        let fallback = try await fresh.prepareRequest(loopRequest())
        let original = try #require(fallback.messages.compactMap(\.toolOutput).first)
        #expect(original.content.utf8.count > 8_192)
        #expect(original.content.contains("Complete Unicode output"))
    }

    @Test(.timeLimit(.minutes(3)))
    func steeringAtEndTurnKeepsItsOwnerAndFollowUpsStayQueued() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("steering-boundary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let steerID = UUID().uuidString, followID = UUID().uuidString
        let queue: @Sendable (String, String, Bool) throws -> Void = { id, text, steering in
            var object = try #require(JSONValueCoder.encode(AgentSessionPostMessageRequest(
                userId: "user", content: text, clientMessageId: id)).asObject)
            if steering { object["deliveryIntent"] = .string("steering") }
            let request = try JSONValueCoder.decode(AgentSessionPostMessageRequest.self, from: .object(object))
            let context = try SessionInputCapture.capture(request, messageID: id, attachments: [], peerOrigin: nil)
            let fingerprint = try SessionInputCapture.fingerprint(request, peerOrigin: nil)
            _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
                .init(id: id, version: 3, agentId: "agent", sessionId: session.id, type: .message,
                    inputTransitions: [.init(messageId: id, fingerprint: fingerprint, disposition: .queued, context: context)],
                    message: .init(id: id, role: .user, segments: [.init(kind: .text, text: text)], userId: "user"))
            ])
        }
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {},
            onPersisted: { _, events in
                if events.contains(where: { $0.message?.segments.first?.text == "Initial answer." }) {
                    do { try queue(steerID, "Apply the correction.", true); try queue(followID, "Next unrelated task.", false) }
                    catch { Issue.record("Enqueue failed: \(error)") }
                }
            })
        let state = RunState(runID: "run", userTurnID: "turn")
        let script = StepScript(steps: [
            [.started, .final(.init(text: "Initial answer.", stopReason: .endTurn))],
            [.started, .final(.init(text: "Corrected answer.", stopReason: .endTurn))]
        ])
        let response = try await AgentLoop(provider: script, state: state).run(loopRequest(), journal: journal,
            executor: .init { _, definition, _, _ in Issue.record("Unexpected effect"); return .init(tool: definition.toolId, ok: false) },
            config: .init(engine: .unified, requiresExplicitCompletion: false))
        #expect(response.text == "Corrected answer.")
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(Set(requests.map(\.runId)) == ["run"])
        #expect(Set(requests.map(\.userTurnId)) == ["turn"])
        #expect(requests.last?.messages.contains { $0.text == "Apply the correction." } == true)
        #expect(requests.allSatisfy { !$0.messages.contains { $0.text == "Next unrelated task." } })
        let fresh = AgentSessionFileStore(agentsRootURL: root)
        let inputs = try SessionInputLifecycle.states(in: fresh.loadSession(agentID: "agent", sessionID: session.id).events)
        #expect(inputs[steerID]?.owner == .init(runId: "run", userTurnId: "turn", generation: 0))
        #expect(inputs[steerID]?.latest.delivery == .delivered)
        #expect(inputs[followID]?.latest.disposition == .queued)
        #expect(inputs[followID]?.owner == nil)
    }

    @Test(.timeLimit(.minutes(3)))
    func contextRecoveryRemainsSpentUntilTheWholeToolStepSettles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("context-step-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "Known content".write(to: root.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let state = RunState(runID: "run", userTurnID: "turn")
        _ = await state.reserveRecovery(for: .contextOverflow, limit: 1)
        let script = StepScript(steps: [
            [.started, .final(.init(toolCalls: [.init(id: "read", name: "files_read", rawArguments: #"{"path":"fixture.txt"}"#)], stopReason: .toolCalls))],
            [.started, .final(.init(text: "Observed the actual read result.", stopReason: .endTurn))]
        ])
        let gate = NativeRunStartGate()
        let executor = AgentLoopToolExecutor { _, definition, arguments, beforeEffect in
            try await beforeEffect()
            await gate.hold()
            let path = try #require(arguments["path"]?.asString)
            return .init(tool: definition.toolId, ok: true,
                data: .string(try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)))
        }
        let operation = Task {
            try await AgentLoop(provider: script, state: state).run(loopRequest(), journal: journal, executor: executor,
                config: .init(engine: .unified, requiresExplicitCompletion: false))
        }
        defer { operation.cancel(); Task { await gate.release() } }
        let held = await gate.waitUntilHeld(during: operation)
        try #require(held)
        #expect(await state.recoveryCount(for: .contextOverflow) == 1)
        let detail = try AgentSessionFileStore(agentsRootURL: root).loadSession(agentID: "agent", sessionID: session.id)
        let raw = try #require(detail.events.last { $0.runtimeMetadata?.runState != nil }?.runtimeMetadata?.runState)
        let checkpoint = try JSONValueCoder.decode(RunStateSnapshot.self, from: raw)
        #expect(checkpoint.recoveryCounts["context_overflow"] == 1)
        await gate.release()
        _ = try await operation.value
        #expect(await state.recoveryCount(for: .contextOverflow) == 0)
    }

    @Test
    func reopenedTurnRetainsItsRetryCeilingDelaysAndReasoning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-retry-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Retry only this authorized request.")]))
        ])
        let failure = ModelStepFailure(category: .transport, code: "connection_lost", message: "Scripted transport loss", retryable: true)
        let first = StepScript(steps: [], failures: [1: failure])
        let original = RunState(runID: "run", userTurnID: "turn")
        let originalDelays: [Duration] = [.milliseconds(5), .milliseconds(7)]
        var frame = loopRequest()
        frame.reasoningEffort = .high
        let executor = AgentLoopToolExecutor { _, definition, _, _ in .init(tool: definition.toolId, ok: false) }
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        await #expect(throws: CocoaError.self) {
            _ = try await AgentLoop(provider: first, state: original, retryDelays: originalDelays,
                retrySleeper: { _ in throw CocoaError(.fileWriteOutOfSpace) })
                .run(frame, journal: journal, executor: executor)
        }
        #expect(await first.requests.count == 1)
        #expect(await original.recoveryCount(for: .transportLoss) == 1)
        let freshStore = AgentSessionFileStore(agentsRootURL: root)
        let fresh = SessionLoopJournal(store: freshStore, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let restored = try #require(try await fresh.restoreRunState(userTurnID: "turn"))
        let saved = await restored.snapshot()
        #expect(saved.schemaVersion == 2)
        #expect(try saved.requestSettings?.transportRetryDelays() == originalDelays)
        #expect(saved.requestSettings?.reasoningEffort == .high)
        let second = StepScript(steps: [], failures: Dictionary(uniqueKeysWithValues: (1...5).map { ($0, failure) }))
        let sleeps = RetrySettingsSleepProbe()
        frame.reasoningEffort = .low
        var stopped: ModelStepFailure?
        do {
            _ = try await AgentLoop(provider: second, state: restored,
                retryDelays: [.seconds(10), .seconds(20), .seconds(30), .seconds(40)],
                retrySleeper: { await sleeps.record($0) }).run(frame, journal: fresh, executor: executor)
        } catch let failure as ModelStepFailure { stopped = failure }
        #expect(stopped?.category == .transport)
        #expect(await second.requests.count == 2)
        #expect(await sleeps.delays == [.milliseconds(7)])
        #expect(await second.requests.allSatisfy { $0.reasoningEffort == .high })
        #expect(await restored.requestAttempts == 3)
        #expect(await restored.recoveryCount(for: .transportLoss) == 2)
        let detail = try freshStore.loadSession(agentID: "agent", sessionID: session.id)
        #expect(!detail.events.contains { $0.toolCall != nil || $0.toolResult != nil })
    }

    @Test
    func requestSettingsSnapshotCanBeReadBeforeAnyNewWriterUsesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-reader-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let legacy = RunStateSnapshot(runID: "run", userTurnID: "turn")
        var object = try #require(JSONValueCoder.encode(legacy).asObject)
        object["schemaVersion"] = .number(2)
        let settings: Protocols.JSONValue = .object([
            "retryDelays": .array([.object(["seconds": .number(0), "attoseconds": .string("7000000000000000")])]),
            "reasoningEffort": .string("high")
        ])
        object["requestSettings"] = settings
        var failure: Error?
        do {
            _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
                .init(version: 2, agentId: "agent", sessionId: session.id, type: .runStatus,
                    runtimeMetadata: .init(runId: "run", userTurnId: "turn", runState: .object(object)))
            ])
        } catch { failure = error }
        #expect(failure == nil)
        guard failure == nil else { return }
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent",
            sessionID: session.id, authorizeWriter: {})
        let restored = try #require(try await fresh.restoreRunState())
        let snapshot = await restored.snapshot()
        #expect(snapshot.schemaVersion == 2)
        #expect(try JSONValueCoder.encode(snapshot).asObject?["requestSettings"] == settings)
        #expect(try await RunState(snapshot: legacy).snapshot().schemaVersion == 1)
    }

    @Test
    func restoredSettledCompletionHasAnOwnedDeliveryWithoutAnotherRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settled-delivery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        var frame = loopRequest()
        frame.tools = []
        let config = NativeAgentLoopConfig(engine: .unified)
        let original = try RunState(snapshot: .init(runID: frame.runId, userTurnID: frame.userTurnId,
            loopConfig: config, model: frame.model))
        #expect(await original.acceptCompletion(.init(disposition: .completed, summary: "Saved completion.",
            verification: [], verificationEvidence: [], limitations: [])))
        await original.markSettled()
        let base = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        try await base.appendRunState(await original.snapshot(), request: frame)
        let restored = try #require(try await base.restoreRunState())
        #expect(await restored.phase == .settled)
        let gate = NativeRunStartGate()
        defer { Task { await gate.release() } }
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id,
            authorizeWriter: {}, onPersisted: { _, events in
                if events.contains(where: { $0.runtimeMetadata?.runState != nil }) { await gate.hold() }
            })
        let script = StepScript(events: [])
        let executor = AgentLoopToolExecutor(execute: { _, _, _, _ -> AgentLoopToolOutcome in
            throw ModelStepFailure(category: .protocolViolation, code: "unexpected_replay_effect", message: "Replay must not execute work")
        })
        let delivery = Task { try await AgentLoop(provider: script, state: restored).run(frame,
            journal: journal, executor: executor, config: config) }
        _ = await gate.waitUntilHeld(during: delivery)
        await gate.release()
        var response: ModelStepResponse?
        var failure: Error?
        do { response = try await delivery.value } catch { failure = error }
        #expect(failure == nil)
        #expect(response?.text == "Saved completion.")
        #expect(await script.requests.isEmpty)
        #expect(await restored.generation == 0)
        #expect(await restored.phase == .settled)
    }

    @Test(arguments: TerminalCancelCase.allCases)
    fileprivate func cancellationDuringTerminalCheckpointCannotReturnSuccess(scenario: TerminalCancelCase) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-cancel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        var frame = loopRequest()
        let definition = ModelStepToolDefinition(name: "session_complete", toolId: "session.complete",
            parameters: .object(["type": .string("object")]))
        frame.tools = scenario == .completion ? [definition] : []
        let config = NativeAgentLoopConfig(finalizerToolNames: ["session.complete"], engine: .unified)
        var state = try RunState(snapshot: .init(runID: frame.runId, userTurnID: frame.userTurnId,
            loopConfig: config, model: frame.model))
        let completed = RunCompletion(disposition: .completed, summary: "Recorded completed work.",
            verification: [], verificationEvidence: [], limitations: [])
        if scenario == .alreadyAccepted || scenario == .restoredSettled { #expect(await state.acceptCompletion(completed)) }
        if scenario == .restoredSettled {
            await state.markSettled()
            let saved = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
            try await saved.appendRunState(await state.snapshot(), request: frame)
            state = try #require(try await saved.restoreRunState())
            #expect(await state.phase == .settled)
        }
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(id: frame.userTurnId, role: .user, segments: [.init(kind: .text, text: "Finish this recorded turn.")]))
        ])
        let gate = NativeRunStartGate()
        defer { Task { await gate.release() } }
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id,
            authorizeWriter: {}, onPersisted: { _, events in
                if events.contains(where: { event in
                    guard let raw = event.runtimeMetadata?.runState,
                          let snapshot = try? JSONValueCoder.decode(RunStateSnapshot.self, from: raw) else { return false }
                    return snapshot.phase == .settled
                }) { await gate.hold() }
            })
        let response = scenario == .completion
            ? ModelStepResponse(toolCalls: [.init(id: "complete", name: definition.name, rawArguments: "{}")], stopReason: .toolCalls)
            : ModelStepResponse(text: "Recorded answer.", stopReason: .endTurn)
        let script = StepScript(events: [.started, .final(response)])
        let executor = AgentLoopToolExecutor(execute: { _, _, _, beforeEffect in
            try await beforeEffect()
            return .init(result: .init(tool: "session.complete", ok: true), completion: completed)
        })
        let deliveryState = state
        let pending = Task { try await AgentLoop(provider: script, state: deliveryState).run(frame,
            journal: journal, executor: executor, config: config) }
        let held = await gate.waitUntilHeld(during: pending)
        if !held { await gate.release(); _ = try await pending.value }
        try #require(held)
        await state.cancel()
        await gate.release()
        var returnedSuccess = false
        do { _ = try await pending.value; returnedSuccess = true }
        catch { #expect(error is CancellationError || (error as? ModelStepFailure)?.category == .cancelled) }
        #expect(!returnedSuccess)
        let restored = try #require(try await journal.restoreRunState())
        #expect(await restored.phase == .stopping)
        #expect(await restored.generation == 1)
        #expect(await script.requests.count == (scenario == .alreadyAccepted || scenario == .restoredSettled ? 0 : 1))
    }

    @Test
    func cancellationAfterPolicyStopStillNotifiesOwnedWork() async {
        let state = RunState()
        let cancelled = OwnedCancellationCounter()
        await state.registerCancellation(id: "in-flight-child", cancel: { cancelled.record() })
        await state.stop(reason: .deadlineExceeded, message: "The policy stopped this turn.")
        await state.cancel()
        #expect(cancelled.value == 1)
        let generation = await state.generation
        await state.cancel()
        #expect(cancelled.value == 1)
        #expect(await state.generation == generation)
    }

    @Test(arguments: [false, true])
    func taskCancellationIsDurableAndCannotResumeTheTurn(cancelBeforeStart: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("durable-cancel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let state = RunState(runID: "owned-run", userTurnID: "owned-turn")
        let provider = CancellableStepScript()
        let gate = NativeRunStartGate()
        let executor = AgentLoopToolExecutor { _, definition, _, _ in
            Issue.record("A cancelled run executed a tool")
            return .init(tool: definition.toolId, ok: false)
        }
        let task = Task {
            if cancelBeforeStart { await gate.hold() }
            return try await AgentLoop(provider: provider, state: state).run(loopRequest(), journal: journal, executor: executor)
        }
        if cancelBeforeStart {
            while !(await gate.isEntered()) { try await Task.sleep(for: .milliseconds(5)) }
            task.cancel()
            await gate.release()
        } else {
            await provider.waitForStart()
            task.cancel()
        }
        do { _ = try await task.value; Issue.record("Cancellation returned a successful response") }
        catch { #expect(error is CancellationError || (error as? ModelStepFailure)?.category == .cancelled) }
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent",
            sessionID: session.id, authorizeWriter: {})
        let restored = try await fresh.restoreRunState(userTurnID: "owned-turn")
        #expect(restored != nil)
        guard let restored else { return }
        #expect(await restored.phase == .stopping)
        #expect(await restored.generation == 1)
        #expect(await restored.requestAttempts == (cancelBeforeStart ? 0 : 1))
        let next = StepScript(events: [.started, .final(.init(text: "must not resume", stopReason: .endTurn))])
        do { _ = try await AgentLoop(provider: next, state: restored).run(loopRequest(), journal: fresh, executor: executor) }
        catch { }
        #expect(await next.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func requiredCompletionRecoveryPreservesWorkAuthorityAndPersistsControl(exhaustedBudget: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("required-completion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Complete the original task")]))
        ])
        var request = loopRequest()
        request.tools.append(.init(name: "session_complete", toolId: "session.complete", parameters: .object(["type": .string("object")])))
        let script = StepScript(steps: [[.started, .final(.init(text: "Unaccepted answer", stopReason: .endTurn))],
            [.started, .final(.init(toolCalls: [.init(id: "complete", name: "session_complete", rawArguments: "{}")], stopReason: .toolCalls))]])
        let completion = RunCompletion(disposition: .completed, summary: "Accepted summary", verification: [], verificationEvidence: [], limitations: [])
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let state = RunState(runID: "run", userTurnID: "turn")
        let executor = AgentLoopToolExecutor(execute: { _, definition, _, beforeEffect in
            try await beforeEffect()
            return .init(result: .init(tool: definition.toolId, ok: true, data: completion.jsonValue), completion: completion)
        })
        let response = try await AgentLoop(provider: script, state: state).run(request, journal: journal, executor: executor,
            config: .init(maxToolRounds: exhaustedBudget ? 0 : 60, finalizerToolNames: ["session.complete"], engine: .unified, requiresExplicitCompletion: true))
        #expect(response.text == completion.summary)
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.last?.tools.map(\.toolId) == (exhaustedBudget ? ["session.complete"] : ["files.read", "session.complete"]))
        #expect(requests.last?.purpose == .completionRecovery)
        #expect(await state.recoveryCount(for: .missingCompletion) == 1)
        let detail = try store.loadSession(agentID: "agent", sessionID: session.id)
        let instructions = detail.events.filter { $0.runtimeMetadata?.instruction?.kind == .completionRecovery }
        #expect(instructions.count == 1)
        if let instruction = instructions.first {
            #expect(requests.last?.messages.contains(where: { $0.id == instruction.id && $0.text == instruction.runtimeMetadata?.instruction?.text }) == true)
        }
        #expect(requests.last?.messages.filter { $0.text == "Complete the original task" }.count == 1)
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent", sessionID: session.id, authorizeWriter: {})
        #expect(try await fresh.restoreRunState(userTurnID: "turn")?.completion == completion)
    }

    @Test
    func completionRecoveryHasOneTurnOwnedCeiling() async throws {
        let script = StepScript(steps: (0..<5).map { _ in [.started, .final(.init(text: "No finalizer", stopReason: .endTurn))] })
        let journal = LoopJournalProbe()
        let state = RunState()
        var request = loopRequest()
        request.tools.append(.init(name: "session_complete", toolId: "session.complete", parameters: .object(["type": .string("object")])))
        let executor = AgentLoopToolExecutor { _, definition, _, _ in .init(tool: definition.toolId, ok: false) }
        let loop = AgentLoop(provider: script, state: state)
        var failure: ModelStepFailure?
        do {
            _ = try await loop.run(request, journal: journal, executor: executor,
                config: .init(finalizerToolNames: ["session.complete"], engine: .unified,
                    requiresExplicitCompletion: true, completionRecoveryLimit: 2))
        } catch { failure = error as? ModelStepFailure }
        #expect(failure?.code == "required_completion_missing")
        #expect(await script.requests.count == 3)
        #expect(await state.recoveryCount(for: .missingCompletion) == 2)
        do { _ = try await loop.run(request, journal: journal, executor: executor) } catch { }
        #expect(await script.requests.count == 3)
    }

    @Test(arguments: [false, true])
    func emptyReplyAfterToolsGetsOneToolFreeAnswerStep(unexpectedCall: Bool) async throws {
        let last: ModelStepResponse = unexpectedCall
            ? .init(toolCalls: [.init(id: "unexpected", name: "files_read", rawArguments: "{\"path\":\"a.txt\"}")], stopReason: .toolCalls)
            : .init(text: "Answer from settled results", stopReason: .endTurn)
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: [
            .init(id: "read", name: "files_read", rawArguments: "{\"path\":\"a.txt\"}")
        ], stopReason: .toolCalls))], [.started, .final(.init(stopReason: .endTurn))], [.started, .final(last)]])
        let journal = LoopJournalProbe()
        let executor = AgentLoopToolExecutor { _, definition, _, beforeEffect in
            try await beforeEffect()
            try await journal.effect()
            return .init(tool: definition.toolId, ok: true, data: .string("settled read result"))
        }
        var response: ModelStepResponse?
        var failure: ModelStepFailure?
        do { response = try await AgentLoop(provider: script, state: RunState()).run(loopRequest(), journal: journal, executor: executor) }
        catch { failure = error as? ModelStepFailure }
        #expect(await script.requests.count == 3)
        #expect(await script.requests.last?.tools.isEmpty == true)
        #expect(await script.requests.last?.purpose == .finalAnswer)
        #expect((await journal.trace).filter { $0 == "effect" }.count == 1)
        if unexpectedCall { #expect(failure?.code == "tools_disallowed_during_final_answer") }
        else { #expect(response?.text == "Answer from settled results") }
    }

    @Test
    func aHardLimitPrecedesACompletionCandidate() async throws {
        var request = loopRequest()
        request.tools[0].name = "files_write"; request.tools[0].toolId = "files.write"; request.tools[0].readOnly = false
        request.tools.append(.init(name: "session_complete", toolId: "session.complete", parameters: .object(["type": .string("object")])))
        let script = StepScript(events: [.started, .final(.init(toolCalls: [
            .init(id: "work", name: "files_write", rawArguments: "{\"path\":\"a.txt\"}"),
            .init(id: "complete", name: "session_complete", rawArguments: "{}")
        ], stopReason: .toolCalls))])
        let journal = LoopJournalProbe()
        let state = RunState()
        let completion = RunCompletion(disposition: .completed, summary: "Must not override limit", verification: [], verificationEvidence: [], limitations: [])
        let executor = AgentLoopToolExecutor(execute: { _, definition, _, beforeEffect in
            try await beforeEffect()
            if definition.toolId == "session.complete" { return .init(result: .init(tool: definition.toolId, ok: true), completion: completion) }
            try await journal.effect()
            return .init(result: .init(tool: definition.toolId, ok: true))
        })
        var failure: ModelStepFailure?
        do { _ = try await AgentLoop(provider: script, state: state).run(request, journal: journal, executor: executor,
            config: .init(maxToolRounds: 0, finalizerToolNames: ["session.complete"], engine: .unified)) }
        catch { failure = error as? ModelStepFailure }
        #expect(failure?.code == "tool_budget_exhausted")
        #expect(await state.completion == nil)
        #expect(!(await journal.trace).contains("effect"))
        #expect(await script.requests.count == 1)
    }

    @Test
    func aRestoredTurnCannotSilentlySwitchItsPinnedModel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pinned-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let failed = StepScript(steps: [], failures: [1: .init(category: .authentication, code: "expired", message: "Resume later")])
        let executor = AgentLoopToolExecutor { _, definition, _, _ in .init(tool: definition.toolId, ok: false) }
        do {
            _ = try await AgentLoop(provider: failed, state: RunState(runID: "run", userTurnID: "turn"))
                .run(loopRequest(), journal: journal, executor: executor)
        } catch { }
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent",
            sessionID: session.id, authorizeWriter: {})
        let restored = try #require(try await fresh.restoreRunState(userTurnID: "turn"))
        var request = loopRequest()
        request.model = "another-model"
        let changed = StepScript(events: [.started, .final(.init(text: "Must not generate", stopReason: .endTurn))])
        var failure: ModelStepFailure?
        do { _ = try await AgentLoop(provider: changed, state: restored).run(request, journal: fresh, executor: executor) }
        catch { failure = error as? ModelStepFailure }
        #expect(await changed.requests.isEmpty)
        #expect(failure?.code == "run_model_changed")
        #expect(await restored.requestAttempts == 1)
    }

    @Test
    func unknownEffectAfterResultWriteFailureCannotReplayOnRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("unknown-effect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Make one change")]))
        ])
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        var request = loopRequest()
        request.tools[0].name = "files_write"
        request.tools[0].toolId = "files.write"
        request.tools[0].readOnly = false
        let call = ModelStepToolCall(id: "original", name: "files_write", rawArguments: "{\"path\":\"a.txt\"}")
        let executor = AgentLoopToolExecutor { _, definition, _, beforeEffect in
            try await beforeEffect()
            let path = root.appendingPathComponent("effect.txt")
            let previous = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
            try Data((previous + "effect\n").utf8).write(to: path)
            return .init(tool: definition.toolId, ok: true)
        }
        let first = StepScript(events: [.started, .final(.init(toolCalls: [call], stopReason: .toolCalls))])
        do {
            _ = try await AgentLoop(provider: first, state: RunState(runID: "run", userTurnID: "turn"))
                .run(request, journal: ResultWriteFaultJournal(base: journal), executor: executor)
        } catch { }
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent",
            sessionID: session.id, authorizeWriter: {})
        let restored = try #require(try await fresh.restoreRunState(userTurnID: "turn"))
        let second = StepScript(events: [.started, .final(.init(toolCalls: [
            .init(id: "retry", name: "files_write", rawArguments: "{\"path\":\"a.txt\"}")
        ], stopReason: .toolCalls))])
        do { _ = try await AgentLoop(provider: second, state: restored).run(request, journal: fresh, executor: executor) }
        catch { }
        #expect(try String(contentsOf: root.appendingPathComponent("effect.txt"), encoding: .utf8) == "effect\n")
        #expect(await second.requests.count == 1)
        let detail = try store.loadSession(agentID: "agent", sessionID: session.id)
        #expect(detail.events.compactMap(\.toolResult).last?.error?.code == "tool_reconciliation_required")
        #expect(SessionToolRecovery.unresolvedCalls(in: detail.events).count == 1)
    }

    @Test(arguments: ["tool_forbidden", "tool_approval_rejected", "tool_approval_timeout", "tool_loop_detected"])
    func policyStopSkipsLaterEffectsAndCannotGenerateAContinuation(code: String) async throws {
        var request = loopRequest()
        request.tools[0].name = "files_write"
        request.tools[0].toolId = "files.write"
        request.tools[0].readOnly = false
        let script = StepScript(events: [.started, .final(.init(toolCalls: [
            .init(id: "denied", name: "files_write", rawArguments: "{\"path\":\"a.txt\"}"),
            .init(id: "later", name: "files_write", rawArguments: "{\"path\":\"b.txt\"}")
        ], stopReason: .toolCalls))])
        let journal = LoopJournalProbe()
        let executor = AgentLoopToolExecutor { call, definition, _, beforeEffect in
            if call.call.id == "denied" {
                return .init(tool: definition.toolId, ok: false, error: .init(code: code, message: "Structured policy stop", retryable: false))
            }
            try await beforeEffect()
            try await journal.effect()
            return .init(tool: definition.toolId, ok: true)
        }
        var stopped: ModelStepFailure?
        do { _ = try await AgentLoop(provider: script, state: RunState()).run(request, journal: journal, executor: executor) }
        catch { stopped = error as? ModelStepFailure }
        #expect(stopped?.code == code)
        #expect(!(await journal.trace).contains("effect"))
        #expect(await script.requests.count == 1)
        #expect(await journal.messages.last?.toolOutput?.callId == "later")
        #expect(await journal.messages.last?.toolOutput?.content.contains("not_executed_after_stop") == true)
    }

    @Test
    func restartRetainsTheTurnBudgetAttemptsAndEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("restart-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let stateJournal = journal as? any AgentLoopStateJournal
        #expect(stateJournal != nil)
        guard stateJournal != nil else { return }
        var request = loopRequest()
        request.tools[0].name = "files_write"
        request.tools[0].toolId = "files.write"
        request.tools[0].readOnly = false
        let call = ModelStepToolCall(id: "first", name: "files_write", rawArguments: "{\"path\":\"a.txt\"}")
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: [call], stopReason: .toolCalls))]],
            failures: [2: .init(category: .authentication, code: "expired", message: "Stop until credentials return")])
        let state = RunState(runID: "run", userTurnID: "turn")
        let evidence = await state.recordEvidence(.init(kind: .test, tool: "runtime.exec", command: "fixture-check",
            arguments: [], cwd: nil, exitCode: 0, observedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let executor = AgentLoopToolExecutor { _, definition, _, beforeEffect in
            try await beforeEffect()
            let destination = root.appendingPathComponent("effect.txt")
            let existing = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
            try Data((existing + "effect\n").utf8).write(to: destination)
            return .init(tool: definition.toolId, ok: true)
        }
        do { _ = try await AgentLoop(provider: script, state: state).run(request, journal: journal, executor: executor,
            config: .init(maxToolRounds: 1, engine: .unified)) } catch { }
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent",
            sessionID: session.id, authorizeWriter: {})
        let freshStateJournal = try #require(fresh as? any AgentLoopStateJournal)
        let restored = try #require(try await freshStateJournal.restoreRunState(userTurnID: "turn"))
        #expect(restored.runID == "run")
        #expect(restored.userTurnID == "turn")
        #expect(await restored.requestAttempts == 2)
        #expect(await restored.verificationEvidence == [evidence])
        let resumed = StepScript(events: [.started, .final(.init(toolCalls: [
            .init(id: "second", name: "files_write", rawArguments: "{\"path\":\"a.txt\"}")
        ], stopReason: .toolCalls))])
        do {
            // A restarted caller cannot silently grant this existing turn a larger ceiling.
            _ = try await AgentLoop(provider: resumed, state: restored).run(request, journal: fresh,
                executor: executor, config: .init(maxToolRounds: 99, engine: .unified))
        } catch { }
        #expect(try String(contentsOf: root.appendingPathComponent("effect.txt"), encoding: .utf8) == "effect\n")
        #expect(await resumed.requests.count == 1)
        #expect(await restored.requestAttempts == 3)
    }

    @Test
    func runtimeUnifiedEngineUsesDurableServicesAndRealFilesystemTools() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("runtime-step-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = String(repeating: "complete file contents\n", count: 80)
        try Data(text.utf8).write(to: root.appendingPathComponent("a.txt"))
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Read a.txt")]))
        ])
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: [
            .init(id: "provider-call", name: "files_read", rawArguments: "{\"path\":\"a.txt\"}")
        ], stopReason: .toolCalls, usage: .init(prompt: 10, completion: 2)))],
            [.started, .final(.init(text: "Done", stopReason: .endTurn, usage: .init(prompt: 20, completion: 3)))]])
        let runtime = RuntimeSystem(modelProvider: StepScriptFactory(script: script, tools: [DeclaredReadTool()]), defaultModel: "script:model")
        let workspace = SloppyWorkspaceToolExecutor(rootURL: root)
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let observations = LoopObservationProbe()
        let executor = AgentLoopToolExecutor { _, definition, arguments, beforeEffect in
            try await beforeEffect()
            return await workspace.invoke(.init(tool: definition.toolId, arguments: arguments))
        }
        _ = await runtime.postMessage(channelId: "durable-runtime", request: .init(userId: "user", content: "Read a.txt"),
            observationHandler: { await observations.record($0) }, forceInlineResponse: true,
            nativeLoopConfig: .init(engine: .unified), agentLoopServices: .init(journal: journal, executor: executor))
        #expect(await script.legacyCalls == 0)
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.first?.tools.first?.toolId == "files.read")
        #expect(requests.last?.messages.filter { $0.role == .user }.count == 1)
        #expect(requests.last?.messages.last?.toolOutput?.content.contains("complete file contents") == true)
        #expect(await observations.calls.count == 1)
        #expect(await observations.results.first?.data?.asObject?["content"] == .string(text))
        #expect(await observations.usage == [.init(prompt: 30, completion: 5)])
        #expect((await runtime.workLedgerText(channelId: "durable-runtime")).contains("files.read"))
        #expect((await runtime.channelState(channelId: "durable-runtime"))?.messages.last?.content == "Done")
        let persisted = try store.loadJournal(agentID: "agent", sessionID: session.id)
        #expect(persisted.records.filter { $0.event.runtimeMetadata?.executionPhase == .started }.count == 1)
        #expect(persisted.records.compactMap(\.event.toolResult).count == 1)
    }

    @Test
    func declaredToolsRequireDurableServicesBeforeGeneration() async {
        let script = StepScript(events: [.started, .final(.init(text: "Should not be requested", stopReason: .endTurn))])
        let runtime = RuntimeSystem(modelProvider: StepScriptFactory(script: script, tools: [DeclaredReadTool()]), defaultModel: "script:model")
        _ = await runtime.postMessage(channelId: "missing-services", request: .init(userId: "user", content: "Read a file"),
            forceInlineResponse: true, nativeLoopConfig: .init(engine: .unified))
        #expect(await script.requests.isEmpty)
        #expect(await script.legacyCalls == 0)
    }

    @Test(arguments: ["accepted", "result-write-failed", "cancelled"])
    func completionOwnsTheTurnOnlyAfterItsDurableResult(disposition: String) async throws {
        let completion = RunCompletion(disposition: .completed, summary: "Accepted summary", verification: [], verificationEvidence: [], limitations: [])
        var request = loopRequest()
        request.tools += [
            .init(name: "session_complete", toolId: "session.complete", parameters: .object(["type": .string("object")])),
            .init(name: "files_write", toolId: "files.write", parameters: .object(["type": .string("object")]))
        ]
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: [
            .init(id: "complete", name: "session_complete", rawArguments: "{}"),
            .init(id: "write", name: "files_write", rawArguments: "{}")
        ], stopReason: .toolCalls))], [.started, .final(.init(text: "Unnecessary continuation", stopReason: .endTurn))]])
        let journal = LoopJournalProbe(failurePhase: disposition == "result-write-failed" ? "result" : nil)
        let state = RunState()
        let executor = AgentLoopToolExecutor(execute: { _, definition, _, beforeEffect in
            try await beforeEffect()
            if definition.toolId == "session.complete" {
                if disposition == "cancelled" { await state.cancel() }
                return .init(result: .init(tool: definition.toolId, ok: true, data: completion.jsonValue), completion: completion)
            }
            try await journal.effect()
            return .init(result: .init(tool: definition.toolId, ok: true))
        })
        var response: ModelStepResponse?
        do {
            response = try await AgentLoop(provider: script, state: state).run(request, journal: journal, executor: executor,
                config: .init(finalizerToolNames: ["session.complete"], engine: .unified))
        } catch { /* Write failure and cancellation cannot commit the candidate. */ }
        #expect(!(await journal.trace).contains("effect"))
        #expect(await script.requests.count == 1)
        if disposition == "accepted" {
            #expect(await state.completion == completion)
            #expect(response?.text == completion.summary)
            #expect(await journal.messages.last?.toolOutput?.callId == "write")
            #expect(await journal.messages.last?.toolOutput?.content.contains("not_executed_after_completion") == true)
        } else {
            #expect(await state.completion == nil)
            #expect(response == nil)
        }
    }

    @Test
    func retryUsesTheFrozenStepAndOneCumulativeAttemptBudget() async throws {
        let script = StepScript(steps: [[.started, .final(.init(text: "Recovered", stopReason: .endTurn))]],
            failures: [1: .init(category: .transport, code: "connection_lost", message: "Scripted transport loss", retryable: true, stage: .streaming)])
        let state = RunState()
        let journal = LoopJournalProbe()
        let executor = AgentLoopToolExecutor { _, definition, _, _ in .init(tool: definition.toolId, ok: false) }
        var response: ModelStepResponse?
        do {
            response = try await AgentLoop(provider: script, state: state, retryDelays: [.zero], retrySleeper: { _ in })
                .run(loopRequest(), journal: journal, executor: executor)
        } catch { /* The next assertions distinguish bounded replay of a frozen request from rebuilding a task. */ }
        #expect(response?.text == "Recovered")
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(await journal.preparations == 1)
        #expect(await state.requestAttempts == 2)
        if requests.count == 2 {
            #expect(requests[0].stepId == requests[1].stepId)
            #expect(requests[0].attemptId != requests[1].attemptId)
            #expect(requests[0].messages == requests[1].messages)
            #expect(requests[0].tools == requests[1].tools)
            #expect(requests[0].projectionRevision == requests[1].projectionRevision)
        }
        #expect(!(await journal.trace).contains("effect"))
    }

    @Test(arguments: [ModelStepFailure.Category.authentication, .transport])
    func nonRetryableFailuresNeverStartAnotherAttempt(category: ModelStepFailure.Category) async throws {
        let script = StepScript(steps: [], failures: [1: .init(category: category, code: "stop", message: "Stop", retryable: false)])
        let journal = LoopJournalProbe()
        let executor = AgentLoopToolExecutor { _, definition, _, _ in .init(tool: definition.toolId, ok: false) }
        await #expect(throws: (any Error).self) {
            _ = try await AgentLoop(provider: script, state: RunState(), retryDelays: [.zero], retrySleeper: { _ in })
                .run(loopRequest(), journal: journal, executor: executor)
        }
        #expect(await script.requests.count == 1)
    }

    @Test
    func cancellingRunStateCancelsTheActiveProviderStream() async throws {
        let state = RunState()
        let script = CancellableStepScript()
        let pending = Task { try await AgentLoop(provider: script, state: state).collectStep(loopRequest()) }
        await script.waitForStart()
        await state.cancel()
        var cancelled = false
        do { _ = try await pending.value }
        catch { cancelled = error is CancellationError || (error as? ModelStepFailure)?.category == .cancelled }
        #expect(cancelled)
        // The provider stays suspended until cancellation, independent of scheduling latency.
        for _ in 0..<600 where !(await script.didCancel) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await script.didCancel)
        #expect(await state.phase == .stopping)
    }

    @Test(arguments: [ModelStepResponse.StopReason.outputLimit, .incomplete, .endTurn])
    func callsFromAnUnfinishedOrInconsistentBatchNeverExecute(reason: ModelStepResponse.StopReason) async throws {
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: [
            .init(id: "call", name: "files_read", rawArguments: "{\"path\":\"a.txt\"}")
        ], stopReason: reason))], [.started, .final(.init(text: "must not continue", stopReason: .endTurn))]])
        let journal = LoopJournalProbe()
        let executor = AgentLoopToolExecutor { _, definition, _, start in
            try await start()
            try await journal.effect()
            return .init(tool: definition.toolId, ok: true)
        }
        do { _ = try await AgentLoop(provider: script, state: RunState()).run(loopRequest(), journal: journal, executor: executor) }
        catch { /* Persist complete call diagnostics, then stop this incomplete attempt. */ }
        #expect(!(await journal.trace).contains("effect"))
        #expect(await journal.messages.last?.toolOutput?.callId == "call")
        #expect(await journal.messages.last?.toolOutput?.content.contains("incomplete_model_response") == true)
        #expect(await script.requests.count == 1)
    }

    @Test(arguments: ["{\"path\":", "[]", "{}", "{\"path\":4}", "{\"path\":\"x\",\"extra\":true}"])
    func malformedAndSchemaInvalidArgumentsReturnDiagnosticsWithoutEffects(arguments: String) async throws {
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: [
            .init(id: "invalid", name: "files_read", rawArguments: arguments)
        ], stopReason: .toolCalls))], [.started, .final(.init(text: "Understood", stopReason: .endTurn))]])
        let journal = LoopJournalProbe()
        let executor = AgentLoopToolExecutor { _, definition, _, start in
            try await start()
            try await journal.effect()
            return .init(tool: definition.toolId, ok: true)
        }
        _ = try await AgentLoop(provider: script, state: RunState()).run(loopRequest(), journal: journal, executor: executor)
        #expect(!(await journal.trace).contains("effect"))
        #expect(await journal.messages.first(where: { $0.toolOutput != nil })?.toolOutput?.content.contains("invalid_tool_arguments") == true)
    }

    @Test
    func safeReadsOverlapAndMutationsRemainExclusiveBarriers() async throws {
        var request = loopRequest()
        var write = try #require(request.tools.first)
        write.name = "files_write"
        write.toolId = "files.write"
        write.readOnly = false
        request.tools.append(write)
        let names = ["read-1", "read-2", "write", "read-3", "read-4"]
        let calls = names.map { ModelStepToolCall(id: $0, name: $0 == "write" ? "files_write" : "files_read", rawArguments: "{\"path\":\"a.txt\"}") }
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: calls, stopReason: .toolCalls))],
            [.started, .final(.init(text: "Done", stopReason: .endTurn))]])
        let effects = ConcurrentEffects()
        let journal = LoopJournalProbe()
        let executor = AgentLoopToolExecutor { call, definition, _, beforeEffect in
            try await beforeEffect()
            await effects.begin(call.call.id)
            try await Task.sleep(for: .milliseconds(call.call.id.hasSuffix("1") ? 100 : 20))
            await effects.finish(call.call.id)
            return .init(tool: definition.toolId, ok: true)
        }
        _ = try await AgentLoop(provider: script, state: RunState()).run(request, journal: journal, executor: executor)
        #expect(await effects.maximumActive == 2)
        #expect(await effects.barrierWasExclusive)
        #expect(await journal.messages.compactMap(\.toolOutput?.callId) != [])
        let projected = try #require(await script.requests.last)
        // The journal probe deliberately uses physical result order; the durable projector has its own source-order test.
        #expect(Set(projected.messages.compactMap(\.toolOutput?.callId)) == Set(names))
    }

    @Test(arguments: [false, true])
    func cancellationPreventsApprovalStartAndPreservesKnownLateResults(cancelAfterStart: Bool) async throws {
        let state = RunState()
        let journal = LoopJournalProbe()
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: [
            .init(id: "call", name: "files_read", rawArguments: "{\"path\":\"a.txt\"}")
        ], stopReason: .toolCalls))], [.started, .final(.init(text: "must not run", stopReason: .endTurn))]])
        let executor = AgentLoopToolExecutor { _, definition, _, beforeEffect in
            if !cancelAfterStart { await state.cancel() }
            try await beforeEffect()
            try await journal.effect()
            if cancelAfterStart { await state.cancel() }
            return .init(tool: definition.toolId, ok: true, data: .string("actual completed outcome"))
        }
        do { _ = try await AgentLoop(provider: script, state: state).run(loopRequest(), journal: journal, executor: executor) }
        catch { /* Cancellation is terminal, while a known effect outcome remains durable. */ }
        let trace = await journal.trace
        #expect(trace.contains("effect") == cancelAfterStart)
        #expect(await script.requests.count == 1)
        if cancelAfterStart {
            #expect(trace.contains("result"))
            #expect(await journal.messages.last?.toolOutput?.content.contains("actual completed outcome") == true)
        }
    }

    @Test
    func toolResultContinuesThroughTheSameLoopAfterDurableStart() async throws {
        let script = StepScript(steps: [
            [.started, .final(.init(toolCalls: [.init(id: "call-1", name: "files_read", rawArguments: "{\"path\":\"a.txt\"}")], stopReason: .toolCalls))],
            [.started, .final(.init(text: "Done", stopReason: .endTurn))]
        ])
        let journal = LoopJournalProbe()
        let executor = AgentLoopToolExecutor { _, definition, arguments, beforeEffect in
            try await beforeEffect()
            try await journal.effect()
            return .init(tool: definition.toolId, ok: true, data: .string(arguments["path"] == .string("a.txt") ? "full content" : "wrong path"))
        }
        var response: ModelStepResponse?
        do { response = try await AgentLoop(provider: script, state: RunState()).run(loopRequest(), journal: journal, executor: executor) }
        catch { /* Assertions below describe the missing runtime behavior. */ }
        #expect(response?.text == "Done")
        #expect(await journal.trace == ["assistant", "requested", "started", "effect", "result", "assistant"])
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.last?.messages.last?.toolOutput?.callId == "call-1")
        #expect(requests.last?.messages.last?.toolOutput?.content.contains("full content") == true)
        #expect(requests.first?.stepId != requests.last?.stepId)
    }

    @Test(arguments: ["assistant", "requested", "started"])
    func failedDurableWritePreventsTheEffect(phase: String) async throws {
        let script = StepScript(events: [.started, .final(.init(toolCalls: [
            .init(id: "call-1", name: "files_read", rawArguments: "{\"path\":\"a.txt\"}")
        ], stopReason: .toolCalls))])
        let journal = LoopJournalProbe(failurePhase: phase)
        let executor = AgentLoopToolExecutor { _, definition, _, beforeEffect in
            try await beforeEffect()
            try await journal.effect()
            return .init(tool: definition.toolId, ok: true)
        }
        await #expect(throws: (any Error).self) {
            _ = try await AgentLoop(provider: script, state: RunState()).run(loopRequest(), journal: journal, executor: executor)
        }
        #expect(!(await journal.trace).contains("effect"))
        #expect(await script.requests.count == 1)
    }

    @Test
    func oneTextStepUsesCompanionCapabilityWithoutLegacyGeneration() async throws {
        let script = StepScript(events: [.started, .textDelta("Do"), .textDelta("ne"), .final(.init(text: "Done", stopReason: .endTurn))])
        let runtime = RuntimeSystem(modelProvider: StepScriptFactory(script: script), defaultModel: "script:model")
        _ = await runtime.postMessage(channelId: "step-text", request: .init(userId: "user", content: "Hello"),
            forceInlineResponse: true, nativeLoopConfig: .init(engine: .unified))
        #expect(await script.legacyCalls == 0)
        #expect(await script.requests.count == 1)
        let snapshot = await runtime.channelState(channelId: "step-text")
        #expect(snapshot?.messages.last(where: { $0.userId == "system" })?.content == "Done")
        let request = try #require(await script.requests.first)
        #expect(request.messages.last?.text == "Hello")
        #expect(request.tools.isEmpty)
    }
}

private struct CompletionResultGapJournal: AgentLoopStateJournal, AgentLoopOutcomeJournal {
    let base: SessionLoopJournal
    let lateObservation: Bool
    func prepareRequest(_ request: ModelStepRequest) async throws -> ModelStepRequest { try await base.prepareRequest(request) }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) async throws { try await base.appendResponse(response, request: request) }
    func appendRequested(_ calls: [AgentLoopCall], request: ModelStepRequest) async throws { try await base.appendRequested(calls, request: request) }
    func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) async throws { try await base.appendStarted(call, request: request) }
    func appendRunState(_ snapshot: RunStateSnapshot, request: ModelStepRequest) async throws { try await base.appendRunState(snapshot, request: request) }
    func restoreRunState(userTurnID: String?) async throws -> RunState? { try await base.restoreRunState(userTurnID: userTurnID) }
    func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) async throws {
        try await base.appendResult(result, call: call, request: request)
        throw CocoaError(.fileWriteOutOfSpace)
    }
    func appendOutcome(_ outcome: AgentLoopToolOutcome, call: AgentLoopCall, request: ModelStepRequest) async throws {
        if lateObservation { try await base.appendResult(outcome.result, call: call, request: request) }
        else { try await base.appendOutcome(outcome, call: call, request: request) }
        // Simulate losing the process after its durable result, before acceptance/checkpoint.
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

extension NativeAgentLoopTests {
    @Test(arguments: [false, true])
    func completionAuthoritySurvivesResultSnapshotGap(lateObservation: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("completion-gap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Finish the authorized operation once.")]))
        ])
        let marker = root.appendingPathComponent("effect-count.txt")
        try "0".write(to: marker, atomically: true, encoding: .utf8)
        var request = loopRequest()
        request.tools = [.init(name: "session_complete", toolId: "session.complete",
            parameters: .object(["type": .string("object"), "properties": .object([:])]))]
        let final = ModelStepResponse(toolCalls: [.init(id: "finish", name: "session_complete", rawArguments: "{}")], stopReason: .toolCalls)
        let completion = RunCompletion(disposition: .completed, summary: "The authorized operation finished.",
            verification: [], verificationEvidence: [], limitations: [])
        let executor = AgentLoopToolExecutor(execute: { _, definition, _, beforeEffect in
            try await beforeEffect()
            let count = Int(try String(contentsOf: marker, encoding: .utf8)) ?? 0
            try String(count + 1).write(to: marker, atomically: true, encoding: .utf8)
            return .init(result: .init(tool: definition.toolId, ok: true, data: completion.jsonValue), completion: completion)
        })
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let config = NativeAgentLoopConfig(finalizerToolNames: ["session.complete"], engine: .unified)
        let first = StepScript(events: [.started, .final(final)])
        await #expect(throws: CocoaError.self) {
            _ = try await AgentLoop(provider: first, state: RunState(runID: "run", userTurnID: "turn"))
                .run(request, journal: CompletionResultGapJournal(base: journal, lateObservation: lateObservation),
                    executor: executor, config: config)
        }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "1")
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent",
            sessionID: session.id, authorizeWriter: {})
        let restored = try #require(try await fresh.restoreRunState(userTurnID: "turn"))
        if lateObservation {
            // Identical result JSON is observation only, without the product-policy candidate.
            #expect(await restored.completion == nil)
            return
        }
        #expect(await restored.completion == completion)
        let second = StepScript(events: [.started, .final(final)])
        let answer = try await AgentLoop(provider: second, state: restored).run(request, journal: fresh, executor: executor, config: config)
        #expect(answer.text == completion.summary)
        #expect(await second.requests.isEmpty)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "1")
    }
    @Test(arguments: ["validation_failed", "not_a_timeout", "tool_timeout", "provider_timeout", "tool_approval_timeout", "tool_execution_interrupted"])
    func timeoutObservationUsesProtocolFieldsInsteadOfErrorProse(code: String) async {
        let state = RunState()
        let isTimeout = ["tool_timeout", "provider_timeout", "tool_approval_timeout", "tool_execution_interrupted"].contains(code)
        let result = ToolInvocationResult(tool: "runtime.exec", ok: false,
            data: code == "tool_execution_interrupted" ? .object(["timedOut": .bool(true)]) : nil,
            error: .init(code: code, message: isTimeout ? "Операция прервана." : "A quoted log says timed out; this is a validation failure.", retryable: false))
        await state.toolStarted(id: "observed")
        await state.toolFinished(id: "observed", result: result)
        #expect(await state.sawToolTimeout == isTimeout)
    }

    @Test(arguments: OutcomeTailCase.allCases)
    fileprivate func settledOutcomeTailRestoresOnlyProductAuthority(scenario: OutcomeTailCase) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("outcome-tail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Verify once; preserve the policy decision after a crash.")]))
        ])
        let marker = root.appendingPathComponent("effects.txt")
        try "0".write(to: marker, atomically: true, encoding: .utf8)
        let state = RunState(runID: "run", userTurnID: "turn")
        let request = loopRequest()
        let first = StepScript(events: [.started, .final(.init(toolCalls: [
            .init(id: "operation", name: "files_read", rawArguments: "{\"path\":\"a.txt\"}")
        ], stopReason: .toolCalls))])
        let executor = AgentLoopToolExecutor(execute: { _, definition, _, beforeEffect in
            if scenario == .denied {
                return .init(result: .init(tool: definition.toolId, ok: false,
                    error: .init(code: "tool_forbidden", message: "Current policy denied the operation.", retryable: false)))
            }
            try await beforeEffect()
            try "1".write(to: marker, atomically: true, encoding: .utf8)
            let evidence = await state.recordEvidence(.init(kind: .build, tool: definition.toolId,
                command: "fixture-check", arguments: [], cwd: root.path, exitCode: 0, observedAt: Date()))
            // Untrusted payload names must not acquire verification authority on restoration.
            return .init(result: .init(tool: definition.toolId, ok: true,
                data: .object(["verificationEvidence": .object(["id": .string("forged-body-id")])])),
                verificationEvidence: [evidence])
        })
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let config = NativeAgentLoopConfig(maxToolRounds: 1, engine: .unified)
        await #expect(throws: CocoaError.self) {
            _ = try await AgentLoop(provider: first, state: state).run(request,
                journal: CompletionResultGapJournal(base: journal, lateObservation: scenario == .late), executor: executor, config: config)
        }
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let restored = try #require(try await fresh.restoreRunState(userTurnID: "turn"))
        let snapshot = await restored.snapshot()
        #expect(snapshot.toolRoundsUsed == 1)
        #expect(snapshot.requestAttempts == 1)
        #expect(snapshot.verificationEvidence.map(\.id) == (scenario == .verified ? ["verification-1"] : []))
        #expect(snapshot.toolErrors.count == (scenario == .denied ? 1 : 0))
        #expect(snapshot.toolStop?.reason == (scenario == .denied ? .forbidden : nil))
        let resumed = StepScript(events: [.started, .final(.init(text: "Already recorded", stopReason: .endTurn))])
        do { _ = try await AgentLoop(provider: resumed, state: restored).run(request, journal: fresh, executor: executor, config: config) }
        catch { #expect(scenario == .denied) }
        #expect(await resumed.requests.count == (scenario == .denied ? 0 : 1))
        #expect(try String(contentsOf: marker, encoding: .utf8) == (scenario == .denied ? "0" : "1"))
    }

}
private struct ScalarOnlyLoopJournal: AgentLoopJournal {
    let base: LoopJournalProbe
    func prepareRequest(_ request: ModelStepRequest) async throws -> ModelStepRequest { try await base.prepareRequest(request) }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) async throws { try await base.appendResponse(response, request: request) }
    func appendRequested(_ calls: [AgentLoopCall], request: ModelStepRequest) async throws { try await base.appendRequested(calls, request: request) }
    func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) async throws { try await base.appendStarted(call, request: request) }
    func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) async throws { try await base.appendResult(result, call: call, request: request) }
}

extension NativeAgentLoopTests {
    @Test(arguments: [false, true])
    func scalarJournalCannotAcceptOrSilentlyDropProductAuthority(completion: Bool) async throws {
        let state = RunState()
        let base = LoopJournalProbe()
        var request = loopRequest()
        request.tools[0].readOnly = false
        let script = StepScript(steps: [[.started, .final(.init(toolCalls: [
            .init(id: "call", name: "files_read", rawArguments: "{\"path\":\"a\"}")
        ], stopReason: .toolCalls))], [.started, .final(.init(text: "Must not continue", stopReason: .endTurn))]])
        let candidate = RunCompletion(disposition: .completed, summary: "Product candidate", verification: [], verificationEvidence: [], limitations: [])
        let evidence = VerificationEvidence(id: "verification-1", kind: .test, tool: "files.read",
            command: "fixture", arguments: [], cwd: nil, exitCode: 0, observedAt: Date())
        let executor = AgentLoopToolExecutor(execute: { _, definition, _, beforeEffect in
            try await beforeEffect()
            try await base.effect()
            return .init(result: .init(tool: definition.toolId, ok: true, data: .string("Actual known result")),
                completion: completion ? candidate : nil, verificationEvidence: completion ? nil : [evidence])
        })
        var code: String?
        do {
            _ = try await AgentLoop(provider: script, state: state).run(request,
                journal: ScalarOnlyLoopJournal(base: base), executor: executor,
                config: .init(finalizerToolNames: ["files.read"], engine: .unified))
        } catch { code = (error as? ModelStepFailure)?.code }
        #expect(code == "durable_outcome_journal_required")
        #expect(await state.completion == nil)
        #expect(await script.requests.count == 1)
        #expect(await base.trace.filter { $0 == "effect" }.count == 1)
        #expect(await base.messages.last?.toolOutput?.content.contains("Actual known result") == true)
    }
}
