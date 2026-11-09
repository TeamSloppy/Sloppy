import Foundation
import Testing
import AgentRuntime
import PluginSDK
import SloppyRuntime
import Protocols
@testable import sloppy

private actor NativeStartProbe {
    private(set) var count = 0
    func started() { count += 1 }
}

private enum NativeEffectCase: CaseIterable, Sendable { case settled, deadline, cancelled }

private actor NativeEffectClock {
    private var instant = ContinuousClock.now
    func now() -> ContinuousClock.Instant { instant }
    func advance(_ duration: Duration) { instant = instant + duration }
}

private actor NativeEffectCompletionProbe {
    private(set) var entered = false
    private(set) var returned: AgentLoopToolOutcome?
    private(set) var lateCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private let entry = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let late = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    func waitUntilEntered(during operation: Task<Void, Error>) async -> Bool {
        if entered { return true }
        let completion = Task { [weak self] in
            _ = try? await operation.value
            await self?.finishEntry()
        }
        defer { completion.cancel() }
        for await _ in entry.stream { return true }
        return false
    }
    private func finishEntry() { entry.continuation.finish() }
    func waitForLate() async { for await _ in late.stream { break } }
    func enter(holding: Bool) async {
        entered = true
        if holding {
            await withCheckedContinuation { continuation = $0; entry.continuation.yield(()) }
        } else { entry.continuation.yield(()) }
    }
    func release() { continuation?.resume(); continuation = nil }
    func finish(_ outcome: AgentLoopToolOutcome) { returned = outcome }
    func recordLate() { lateCount += 1; late.continuation.yield(()); late.continuation.finish() }
}

@Suite("Native Core effect boundary")
struct NativeToolExecutionTests {
    @Test(.timeLimit(.minutes(10)), arguments: NativeEffectCase.allCases)
    fileprivate func coreOwnsEffectDeadlineAndKeepsCandidatesTyped(mode: NativeEffectCase) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agentID = "native-lifetime-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native lifetime fixture"))
        let session = try await service.createAgentSession(agentID: agentID, request: .init())
        let file = await service.workspaceRootURL.appendingPathComponent("late-effect.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let definition = ModelStepToolDefinition(name: "session_complete", toolId: "session.complete",
            parameters: .object(["type": .string("object")]))
        let arguments: [String: JSONValue] = ["status": .string("completed"), "summary": .string("Known finalizer result")]
        let frame = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "script:model", projectionRevision: "", cacheScope: session.id, messages: [], tools: [definition])
        let call = AgentLoopCall(sourceOrder: 0, call: .init(id: "finalizer", name: definition.name,
            rawArguments: String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)))
        let journal = SessionLoopJournal(store: await service.sessionStore, agentID: agentID, sessionID: session.id, authorizeWriter: {})
        try await journal.appendResponse(.init(toolCalls: [call.call], stopReason: .toolCalls), request: frame)
        try await journal.appendRequested([call], request: frame)
        let candidate = RunCompletion(disposition: .completed, summary: "Known finalizer result",
            verification: [], verificationEvidence: [], limitations: [])
        let probe = NativeEffectCompletionProbe()
        let clock = NativeEffectClock()
        let context = NativeToolExecutionContext(metadata: .init(runId: frame.runId, userTurnId: frame.userTurnId,
            stepId: frame.stepId, attemptId: frame.attemptId, generation: 0, sourceOrder: 0,
            providerCallId: call.call.id, callEventId: call.eventID), definition: definition, beforeEffect: {
                try await journal.appendStarted(call, request: frame)
            }, finalizer: { _ in
                await probe.enter(holding: mode != .settled)
                do {
                    try "actual effect".write(to: file, atomically: true, encoding: .utf8)
                    return .init(result: .init(tool: definition.toolId, ok: true, data: candidate.jsonValue), completion: candidate)
                } catch {
                    return .init(result: .init(tool: definition.toolId, ok: false,
                        error: .init(code: "fixture_write_failed", message: error.localizedDescription, retryable: false)))
                }
            }, recordLateResult: { result in
                try await journal.appendResult(result, call: call, request: frame)
                await probe.recordLate()
            }, remainingDeadlineMilliseconds: mode == .deadline ? 500 : 5_000, effectNow: { await clock.now() })
        let invocation = Task<Void, Error> {
            let outcome = await service.invokeNativeTool(agentID: agentID, sessionID: session.id,
                request: .init(tool: definition.toolId, arguments: arguments), context: context)
            await probe.finish(outcome)
        }
        let entered = await probe.waitUntilEntered(during: invocation)
        #expect(entered)
        guard entered else { _ = try await invocation.value; return }
        if mode == .deadline { await clock.advance(.milliseconds(500)) }
        if mode == .cancelled { invocation.cancel() }
        try await withTaskCancellationHandler {
            try await invocation.value
        } onCancel: {
            invocation.cancel()
            Task { await probe.release() }
        }
        let outcome = await probe.returned
        #expect(outcome != nil)
        if mode == .settled {
            #expect(outcome?.result.ok == true)
            #expect(outcome?.completion == candidate)
        } else {
            #expect(outcome?.result.error?.code == "tool_execution_interrupted")
            #expect(outcome?.completion == nil)
            #expect(try String(contentsOf: file, encoding: .utf8) == "original")
        }
        if let outcome { try await journal.appendResult(outcome.result, call: call, request: frame) }
        await probe.release()
        if mode != .settled {
            await probe.waitForLate()
            #expect(await probe.lateCount == 1)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "actual effect")
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        #expect(detail.events.last(where: { $0.type == .toolResult })?.toolResult?.ok == true)
        #expect(SessionToolRecovery.unknownEffectCallIDs(in: detail.events).isEmpty)
    }

    @Test(.timeLimit(.minutes(10)))
    func cancellationSettlesApprovalWithoutAHumanDecision() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agentID = "native-cancel-wait-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Approval cancellation fixture"))
        let session = try await service.createAgentSession(agentID: agentID, request: .init())
        _ = try await service.updateAgentToolsPolicy(agentID: agentID, request: .init(approval: .init(enabled: true)))
        let file = await service.workspaceRootURL.appendingPathComponent("cancel-wait.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let arguments: [String: JSONValue] = ["path": .string(file.lastPathComponent), "content": .string("must not execute")]
        let definition = ModelStepToolDefinition(name: "files_write", toolId: "files.write", parameters: .object(["type": .string("object")]))
        let frame = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "script:model", projectionRevision: "", cacheScope: session.id, messages: [], tools: [definition])
        let call = AgentLoopCall(sourceOrder: 0, call: .init(id: "call", name: definition.name,
            rawArguments: String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)))
        let journal = SessionLoopJournal(store: await service.sessionStore, agentID: agentID, sessionID: session.id, authorizeWriter: {})
        try await journal.appendRequested([call], request: frame)
        let starts = NativeStartProbe()
        let probe = NativeEffectCompletionProbe()
        let context = NativeToolExecutionContext(metadata: .init(runId: "run", userTurnId: "turn", stepId: "step",
            attemptId: "attempt", generation: 0, sourceOrder: 0, providerCallId: call.call.id, callEventId: call.eventID),
            definition: definition, beforeEffect: {
                await starts.started()
                try await journal.appendStarted(call, request: frame)
            }, recordLateResult: { result in try await journal.appendResult(result, call: call, request: frame) })
        let invocation = Task {
            let result = await service.invokeNativeTool(agentID: agentID, sessionID: session.id,
                request: .init(tool: definition.toolId, arguments: arguments), context: context)
            await probe.finish(result)
        }
        defer { invocation.cancel() }
        var pending: ToolApprovalRecord?
        for _ in 0..<250 {
            pending = await service.listPendingToolApprovals().first
            if pending != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let approval = try #require(pending)
        invocation.cancel()
        await withTaskCancellationHandler {
            await invocation.value
        } onCancel: {
            invocation.cancel()
            Task { _ = await service.rejectToolApproval(id: approval.id, decidedBy: "test-timeout-cleanup") }
        }
        #expect(await probe.returned?.result.error?.code == "not_executed_cancelled")
        #expect(!(await service.listPendingToolApprovals()).contains(where: { $0.id == approval.id }))
        // Also releases the old implementation's waiter if cancellation was incorrectly ignored.
        let lateDecision = await service.approveToolApproval(id: approval.id, decidedBy: "late-test-decision")
        #expect(lateDecision?.status != .approved)
        await invocation.value
        #expect(await starts.count == 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test(arguments: [false, true])
    func durableStartControlsARealCoreFileWrite(failStart: Bool) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agentID = "native-boundary-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native boundary fixture"))
        let session = try await service.createAgentSession(agentID: agentID, request: .init())
        let root = await service.workspaceRootURL
        let file = root.appendingPathComponent("native-effect-" + UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let arguments: [String: JSONValue] = ["path": .string(file.lastPathComponent), "content": .string("one durable effect")]
        let definition = ModelStepToolDefinition(name: "files_write", toolId: "files.write",
            parameters: .object(["type": .string("object"), "required": .array([.string("path"), .string("content")]),
                "properties": .object(["path": .object(["type": .string("string")]), "content": .object(["type": .string("string")])])]))
        let frame = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "script:model", projectionRevision: "", cacheScope: session.id, messages: [], tools: [definition])
        let call = AgentLoopCall(sourceOrder: 0, call: .init(id: "provider-call", name: definition.name,
            rawArguments: String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)))
        let journal = SessionLoopJournal(store: await service.sessionStore, agentID: agentID, sessionID: session.id, authorizeWriter: {})
        try await journal.appendRequested([call], request: frame)
        let probe = NativeStartProbe()
        let context = NativeToolExecutionContext(metadata: .init(runId: frame.runId, userTurnId: frame.userTurnId,
            stepId: frame.stepId, attemptId: frame.attemptId, generation: frame.generation, sourceOrder: 0,
            providerCallId: call.call.id, callEventId: call.eventID), definition: definition, beforeEffect: {
                await probe.started()
                if failStart { throw CocoaError(.fileWriteNoPermission) }
                try await journal.appendStarted(call, request: frame)
            }, recordLateResult: { result in
                try await journal.appendResult(result, call: call, request: frame)
            })
        let result = await service.invokeNativeTool(agentID: agentID, sessionID: session.id,
            request: .init(tool: definition.toolId, arguments: arguments), context: context).result
        #expect(await probe.count == 1)
        #expect(result.ok == !failStart)
        #expect(try String(contentsOf: file, encoding: .utf8) == (failStart ? "original" : "one durable effect"))
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(detail.events.filter { $0.type == .toolCall }.count == 1)
        #expect(detail.events.filter { $0.type == .toolResult }.isEmpty)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == (failStart ? 0 : 1))
    }

    @Test(arguments: [false, true])
    func approvalCannotOutliveRevocationOrCancellation(cancelDuringApproval: Bool) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agentID = "native-approval-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native approval fixture"))
        let session = try await service.createAgentSession(agentID: agentID, request: .init())
        _ = try await service.updateAgentToolsPolicy(agentID: agentID, request: .init(approval: .init(enabled: true)))
        let root = await service.workspaceRootURL
        let file = root.appendingPathComponent("native-approval-" + UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let arguments: [String: JSONValue] = ["path": .string(file.lastPathComponent), "content": .string("must not execute")]
        let definition = ModelStepToolDefinition(name: "files_write", toolId: "files.write", parameters: .object(["type": .string("object")]))
        let frame = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "script:model", projectionRevision: "", cacheScope: session.id, messages: [], tools: [definition])
        let call = AgentLoopCall(sourceOrder: 0, call: .init(id: "provider-call", name: definition.name,
            rawArguments: String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)))
        let journal = SessionLoopJournal(store: await service.sessionStore, agentID: agentID, sessionID: session.id, authorizeWriter: {})
        try await journal.appendRequested([call], request: frame)
        let probe = NativeStartProbe()
        let context = NativeToolExecutionContext(metadata: .init(runId: frame.runId, userTurnId: frame.userTurnId,
            stepId: frame.stepId, attemptId: frame.attemptId, generation: 0, sourceOrder: 0,
            providerCallId: call.call.id, callEventId: call.eventID), definition: definition, beforeEffect: {
                await probe.started()
                try await journal.appendStarted(call, request: frame)
            }, recordLateResult: { result in
                try await journal.appendResult(result, call: call, request: frame)
            })
        let invocation = Task {
            await service.invokeNativeTool(agentID: agentID, sessionID: session.id,
                request: .init(tool: definition.toolId, arguments: arguments), context: context).result
        }
        defer { invocation.cancel() }
        var pending: ToolApprovalRecord?
        for _ in 0..<250 {
            pending = await service.listPendingToolApprovals().first
            if pending != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let approval = try #require(pending)
        #expect(approval.toolCallId == call.eventID)
        if cancelDuringApproval { invocation.cancel() }
        else {
            _ = try await service.updateAgentToolsPolicy(agentID: agentID,
                request: .init(tools: ["files.write": false], approval: .init(enabled: true)))
        }
        _ = await service.approveToolApproval(id: approval.id, decidedBy: "test")
        let result = await invocation.value
        #expect(!result.ok)
        #expect(await probe.count == 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
        #expect(result.error?.code == (cancelDuringApproval ? "not_executed_cancelled" : "tool_forbidden"))
    }
}
