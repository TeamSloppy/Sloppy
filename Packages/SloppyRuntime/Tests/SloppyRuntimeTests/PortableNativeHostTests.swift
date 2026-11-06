import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import Testing
@testable import SloppyRuntime

private actor PortableHostScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    let generationGate: EmbeddedBuildGate?
    private var heldGeneration = false
    init(generationGate: EmbeddedBuildGate? = nil) { self.generationGate = generationGate }
    func next(_ request: ModelStepRequest) async -> ModelStepResponse {
        if !heldGeneration, let generationGate {
            heldGeneration = true
            _ = await generationGate.hold()
        }
        let firstForRun = !requests.contains { $0.runId == request.runId }
        requests.append(request)
        if firstForRun {
            return .init(toolCalls: [
                .init(id: "write", name: "files_write", rawArguments: #"{"path":"Sources/main.ada","content":"portable fixture"}"#),
                .init(id: "build", name: "editor_build", rawArguments: "{}")
            ], stopReason: .toolCalls)
        }
        return .init(text: "Created and built the portable project.", stopReason: .endTurn)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started)
                continuation.yield(.final(await self.next(request)))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private enum EmbeddedRecoveryCase: CaseIterable { case terminal, unknownEffect, futureFormat }

private actor EmbeddedBuildGate {
    var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { arrivals.append($0) }
    }
    func hold() async -> SloppyBuildResult {
        started = true
        for arrival in arrivals { arrival.resume() }; arrivals.removeAll()
        await withCheckedContinuation { waiter = $0 }
        return .init(ok: true, summary: "Built")
    }
    func release() { waiter?.resume(); waiter = nil }
}

private enum CompactionFailureCase: CaseIterable { case authentication, toolCall, insufficientSummary }
private enum ProviderContextCase: CaseIterable { case recovered, repeatedOverflow, transportAfterCompaction, authentication }

private actor PortableCompactionScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    let failure: CompactionFailureCase?
    let providerContext: ProviderContextCase?
    let duringSummary: (@Sendable () throws -> Void)?
    init(failure: CompactionFailureCase? = nil, providerContext: ProviderContextCase? = nil,
         duringSummary: (@Sendable () throws -> Void)? = nil) {
        self.failure = failure; self.providerContext = providerContext; self.duringSummary = duringSummary
    }
    func next(_ request: ModelStepRequest) throws -> ModelStepResponse {
        requests.append(request)
        if let providerContext, request.purpose == .work {
            let workAttempts = requests.filter { $0.purpose == .work }.count
            if providerContext == .authentication {
                throw ModelStepFailure(category: .authentication, code: "invalid_credentials", message: "Credentials expired.")
            }
            if workAttempts == 1 || providerContext == .repeatedOverflow {
                throw ModelStepFailure(category: .context, code: "provider_context_limit", message: "Fixture limit exceeded.")
            }
            if providerContext == .transportAfterCompaction && workAttempts == 2 {
                throw ModelStepFailure(category: .transport, code: "connection_reset", message: "Fixture connection reset.", retryable: true)
            }
        }
        if request.purpose.rawValue == "compaction" {
            try duringSummary?()
            if failure == .authentication {
                throw ModelStepFailure(category: .authentication, code: "compaction_credentials_invalid", message: "Fixture credentials expired.")
            }
            if failure == .toolCall {
                return .init(toolCalls: [.init(id: "forbidden", name: "files_write", rawArguments: "{}")], stopReason: .toolCalls)
            }
        }
        return .init(text: request.purpose.rawValue == "compaction"
            ? "Earlier factual context is retained in this compact summary."
            : "The current task and protected context were retained.", stopReason: .endTurn)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started)
                do {
                    continuation.yield(.final(try await self.next(request)))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct PortableCompactionFactory: ModelProvider, ModelStepProviderFactory {
    let id = "portable-compaction-fixture"
    let supportedModels = ["openai-api:portable-fixture"]
    let script: PortableCompactionScript
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        throw ModelStepFailure(category: .unavailable, code: "legacy_compaction_forbidden", message: "Use a single-step request.")
    }
}

private struct PortableHostFactory: ModelProvider, ModelStepProviderFactory {
    let id = "portable-host-fixture"
    let supportedModels = ["openai-api:portable-fixture"]
    let script: PortableHostScript
    var tools: [any Tool] { SloppyWorkspaceToolExecutor.modelTools }
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        throw ModelStepFailure(category: .unavailable, code: "legacy_host_forbidden", message: "The fixture only implements a single model step.")
    }
}

@Suite("Portable native host")
struct PortableNativeHostTests {
    @Test(.timeLimit(.minutes(3)), arguments: [false, true])
    func steeringDuringCompactionEntersTheNextFrozenRequest(providerReported: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("steering-compaction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = "session-" + UUID().uuidString.lowercased(), inputID = UUID().uuidString
        let store = AgentSessionFileStore(agentsRootURL: root.appendingPathComponent(".ada/workspace/native-agent-v1/agents"))
        let script = PortableCompactionScript(providerContext: providerReported ? .recovered : nil, duringSummary: {
            var request = AgentSessionPostMessageRequest(userId: "user", content: "Correction during summary.", clientMessageId: inputID)
            request.deliveryIntent = .steering
            let fingerprint = try SessionInputCapture.fingerprint(request, peerOrigin: nil)
            let context = try SessionInputCapture.capture(request, messageID: inputID, attachments: [], peerOrigin: nil)
            _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: [
                .init(id: inputID, version: 3, agentId: "mobile", sessionId: sessionID, type: .message,
                    inputTransitions: [.init(messageId: inputID, fingerprint: fingerprint, disposition: .queued, context: context)],
                    message: .init(id: inputID, role: .user, segments: [.init(kind: .text, text: request.content)], userId: "user"))
            ])
        })
        let model = "openai-api:portable-fixture"
        let provider = ContextLimitedModelProvider(wrapping: PortableCompactionFactory(script: script),
            limits: [model: .init(contextWindowTokens: providerReported ? 65_536 : 16_384)])
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: provider, memoryStore: InMemoryMemoryStore(),
            configuration: .init(defaultModel: model))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .unified)
        _ = try await host.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
        for index in 0..<(providerReported ? 12 : 40) {
            _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: [
                .init(agentId: "mobile", sessionId: sessionID, type: .message,
                    message: .init(role: .user, segments: [.init(kind: .text, text: "Earlier task \(index).")])),
                .init(agentId: "mobile", sessionId: sessionID, type: .message,
                    message: .init(role: .assistant, segments: [.init(kind: .text,
                        text: String(repeating: "Historical detail for message \(index).\n", count: providerReported ? 32 : 64))]))
            ])
        }
        _ = try await host.send(prompt: "Current task.", sessionID: sessionID, workspaceURL: root,
            build: { Issue.record("Unexpected tool effect"); return .init(ok: false, summary: "Unexpected") },
            onText: { _ in }, persistedSessionID: sessionID)
        let requests = await script.requests
        let work = requests.filter { $0.purpose == .work }
        #expect(requests.filter { $0.purpose == .compaction }.count == 1)
        #expect(work.count == (providerReported ? 2 : 1))
        #expect(work.last?.messages.contains { $0.text == "Correction during summary." } == true)
        let inputs = try SessionInputLifecycle.states(in: store.loadSession(agentID: "mobile", sessionID: sessionID).events)
        #expect(inputs[inputID]?.latest.delivery == .delivered)
        #expect(inputs[inputID]?.owner?.runId == work.last?.runId)
    }

    @Test(.timeLimit(.minutes(3)))
    func embeddedCancelledWaiterDoesNotBlockTheNextFollowUp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("embedded-queue-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableHostScript(), gate = EmbeddedBuildGate()
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: "openai-api:portable-fixture"))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: "openai-api:portable-fixture", nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased(), cancelledID = UUID().uuidString
        let (store, _) = try await host.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
        let first = Task { try await host.send(prompt: "First task.", sessionID: sessionID, workspaceURL: root,
            build: { await gate.hold() }, onText: { _ in }, persistedSessionID: sessionID) }
        for _ in 0..<500 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await gate.started)
        let cancelled = Task { () -> Bool in
            do {
                _ = try await host.send(prompt: "Cancelled follow-up.", sessionID: sessionID, workspaceURL: root,
                    build: { Issue.record("Cancelled queued input executed"); return .init(ok: false, summary: "Unexpected") },
                    onText: { _ in }, persistedSessionID: sessionID, clientMessageID: cancelledID)
                return false
            } catch { return error is CancellationError }
        }
        for _ in 0..<100 {
            if try SessionInputLifecycle.states(in: store.loadSession(agentID: "mobile", sessionID: sessionID).events)[cancelledID] != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        cancelled.cancel()
        #expect(await cancelled.value)
        let next = Task { try await host.send(prompt: "Next task.", sessionID: sessionID, workspaceURL: root,
            build: { .init(ok: true, summary: "Built") }, onText: { _ in }, persistedSessionID: sessionID) }
        await gate.release()
        _ = try await first.value
        var failure: Error?
        do { _ = try await next.value } catch { failure = error }
        #expect(failure == nil)
        let events = try store.loadSession(agentID: "mobile", sessionID: sessionID).events
        let input = try SessionInputLifecycle.states(in: events)[cancelledID]
        #expect(input?.latest.disposition == .cancelled)
        #expect(input?.latest.delivery == .delivered)
        #expect(input?.owner == nil)
        #expect(await script.requests.count == 4)
    }

    @Test(.timeLimit(.minutes(3)), arguments: [false, true])
    func embeddedFollowUpIsDurableBeforeWaitingAndRunsAfterSettlement(steering: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("embedded-queue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableHostScript(), gate = EmbeddedBuildGate()
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: "openai-api:portable-fixture"))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: "openai-api:portable-fixture", nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased(), nextID = UUID().uuidString
        let (store, _) = try await host.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
        let first = Task { try await host.send(prompt: "First task.", sessionID: sessionID, workspaceURL: root,
            build: { await gate.hold() }, onText: { _ in }, persistedSessionID: sessionID) }
        for _ in 0..<500 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await gate.started)
        let second = Task { try await host.send(prompt: "Follow-up task.", sessionID: "another-ui-channel", workspaceURL: root,
            build: { .init(ok: true, summary: "Follow-up built") }, onText: { _ in },
            persistedSessionID: sessionID, clientMessageID: nextID, deliveryIntent: steering ? .steering : nil) }
        var queued: SessionInputLifecycle.State?
        for _ in 0..<100 {
            queued = try SessionInputLifecycle.states(in: store.loadSession(agentID: "mobile", sessionID: sessionID).events)[nextID]
            if queued != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(queued?.latest.disposition == .queued)
        #expect(queued?.owner == nil)
        #expect(await script.requests.count == 1)
        await gate.release()
        _ = try await first.value
        var failure: Error?
        do { _ = try await second.value } catch { failure = error }
        #expect(failure == nil)
        let events = try store.loadSession(agentID: "mobile", sessionID: sessionID).events
        #expect(try SessionInputLifecycle.states(in: events)[nextID]?.latest.delivery == .delivered)
        let requests = await script.requests
        #expect(requests.count == (steering ? 2 : 4))
        #expect(!requests[0].messages.contains { $0.text == "Follow-up task." })
        if steering { #expect(Set(requests.map(\.runId)).count == 1) }
        else { #expect(requests.prefix(2).allSatisfy { !$0.messages.contains { $0.text == "Follow-up task." } }) }
        #expect(requests.last?.messages.contains { $0.text == "Follow-up task." } == true)
        #expect(events.filter { $0.message?.id == nextID }.count == 1)
    }

    @Test(.timeLimit(.minutes(3)))
    func embeddedQueuedInputCanResumeWithAFreshHost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("embedded-queue-restart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = "session-" + UUID().uuidString.lowercased(), inputID = UUID().uuidString
        let original = SloppyRuntimeHost(nativeEngine: .unified)
        let (store, _) = try await original.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
        let request = AgentSessionPostMessageRequest(userId: "user", content: "Saved follow-up.", mode: .ask, clientMessageId: inputID)
        let fingerprint = try SessionInputCapture.fingerprint(request, peerOrigin: nil)
        let context = try SessionInputCapture.capture(request, messageID: inputID, attachments: [], peerOrigin: nil)
        _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: [
            .init(id: inputID, version: 3, agentId: "mobile", sessionId: sessionID, type: .message,
                inputTransitions: [.init(messageId: inputID, fingerprint: fingerprint, disposition: .queued, context: context)],
                message: .init(id: inputID, role: .user, segments: [.init(kind: .text, text: request.content)], userId: "user"))
        ])
        let script = PortableHostScript()
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: "openai-api:portable-fixture"))
        let fresh = SloppyRuntimeHost(runtime: runtime, modelID: "openai-api:portable-fixture", nativeEngine: .unified)
        var failure: Error?
        do {
            _ = try await fresh.send(prompt: request.content, sessionID: sessionID, workspaceURL: root,
                build: { .init(ok: true, summary: "Built") }, onText: { _ in }, persistedSessionID: sessionID, clientMessageID: inputID)
        } catch { failure = error }
        #expect(failure == nil)
        let events = try store.loadSession(agentID: "mobile", sessionID: sessionID).events
        #expect(events.filter { $0.message?.id == inputID }.count == 1)
        #expect(try SessionInputLifecycle.states(in: events)[inputID]?.latest.delivery == .delivered)
        #expect(await script.requests.count == 2)
    }

    @Test(.timeLimit(.minutes(3)), arguments: ProviderContextCase.allCases)
    fileprivate func providerContextOverflowCompactsOnceAndKeepsRetryProjection(scenario: ProviderContextCase) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("provider-context-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableCompactionScript(providerContext: scenario), model = "openai-api:portable-fixture"
        let limits = ModelContextLimits(contextWindowTokens: 65_536)
        let provider = ContextLimitedModelProvider(wrapping: PortableCompactionFactory(script: script), limits: [model: limits])
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: provider, memoryStore: InMemoryMemoryStore(),
            configuration: .init(defaultModel: model))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased()
        let (store, _) = try await host.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
        var history: [AgentSessionEvent] = []
        for index in 0..<12 {
            history += [
                .init(agentId: "mobile", sessionId: sessionID, type: .message,
                    message: .init(role: .user, segments: [.init(kind: .text, text: "Original objective \(index).")])),
                .init(agentId: "mobile", sessionId: sessionID, type: .message,
                    message: .init(role: .assistant, segments: [.init(kind: .text,
                        text: String(repeating: "Historical detail for message \(index).\n", count: 32))]))
            ]
        }
        _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: history)
        var failure: Error?, answer: String?
        do {
            answer = try await host.send(prompt: "Keep the current objective.", sessionID: sessionID, workspaceURL: root,
                build: { Issue.record("Context recovery invoked a tool"); return .init(ok: false, summary: "Unexpected") },
                onText: { _ in }, persistedSessionID: sessionID)
        } catch { failure = error }
        let shouldComplete = scenario == .recovered || scenario == .transportAfterCompaction
        #expect((failure == nil) == shouldComplete)
        #expect((answer != nil) == shouldComplete)
        let requests = await script.requests
        let work = requests.filter { $0.purpose == .work }
        let summaries = requests.filter { $0.purpose == .compaction }
        #expect(work.count == (scenario == .authentication ? 1 : scenario == .transportAfterCompaction ? 3 : 2))
        #expect(summaries.count == (scenario == .authentication ? 0 : 1))
        #expect(summaries.allSatisfy { $0.tools.isEmpty })
        #expect(Set(work.map(\.attemptId)).count == work.count)
        #expect(Set(work.map(\.stepId)).count == 1)
        #expect(Set(requests.map(\.runId)).count == 1)
        if work.count > 1 {
            #expect(try ModelStepContextBudget.estimate(work[1]) < ModelStepContextBudget.estimate(work[0]))
            #expect(work[1].messages.contains { $0.text == "Keep the current objective." })
            #expect(work[1].messages.contains { $0.text == "Original objective 0." })
            #expect(work[1].messages.contains { $0.text == "Original objective 11." })
        }
        if work.count == 3 { #expect(work[1].messages == work[2].messages) }
        let journal = try store.loadJournal(agentID: "mobile", sessionID: sessionID)
        #expect(Set(history.map(\.id)).isSubset(of: Set(journal.detail.events.map(\.id))))
        #expect(journal.detail.events.compactMap(\.toolCall).isEmpty)
        let snapshot = try JSONValueCoder.decode(RunStateSnapshot.self, from: #require(
            journal.detail.events.last { $0.runtimeMetadata?.runState != nil }?.runtimeMetadata?.runState))
        #expect(snapshot.requestAttempts == requests.count)
        #expect(snapshot.recoveryCounts["context_overflow", default: 0] == (scenario == .repeatedOverflow ? 1 : 0))
        if shouldComplete {
            let response = try #require(journal.detail.events.last { $0.runtimeMetadata?.auxiliaryPurpose == nil && $0.message?.role == .assistant })
            #expect(response.runtimeMetadata?.attemptId == work.last?.attemptId)
        }
    }

    @Test(.timeLimit(.minutes(3)), arguments: CompactionFailureCase.allCases)
    fileprivate func failedCompactionRetainsItsPreviousProjection(scenario: CompactionFailureCase) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compaction-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableCompactionScript(failure: scenario), model = "openai-api:portable-fixture"
        let provider = ContextLimitedModelProvider(wrapping: PortableCompactionFactory(script: script),
            limits: [model: .init(contextWindowTokens: scenario == .insufficientSummary ? 4_096 : 16_384)])
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: provider, memoryStore: InMemoryMemoryStore(),
            configuration: .init(defaultModel: model))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased()
        let (store, _) = try await host.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
        var history: [AgentSessionEvent] = []
        for index in 0..<40 {
            history += [
                .init(agentId: "mobile", sessionId: sessionID, type: .message,
                    message: .init(role: .user, segments: [.init(kind: .text, text: "Original request \(index).") ])),
                .init(agentId: "mobile", sessionId: sessionID, type: .message,
                    message: .init(role: .assistant, segments: [.init(kind: .text,
                        text: String(repeating: "Historical detail for message \(index).\n", count: 64))]))
            ]
        }
        _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: history)
        var failure: Error?
        do {
            _ = try await host.send(prompt: "Keep this active task.", sessionID: sessionID, workspaceURL: root,
                build: { Issue.record("A failed compaction invoked a tool"); return .init(ok: false, summary: "Unexpected") },
                onText: { _ in }, persistedSessionID: sessionID)
        } catch { failure = error }
        #expect(failure != nil)
        let requests = await script.requests
        #expect(requests.count == 1)
        #expect(requests.allSatisfy { $0.purpose.rawValue == "compaction" && $0.tools.isEmpty })
        let journal = try store.loadJournal(agentID: "mobile", sessionID: sessionID)
        let visible = try await host.messages(workspaceURL: root)
        #expect(visible.count == history.count + 1)
        #expect(visible.last?.text == "Keep this active task.")
        #expect(journal.detail.summary.messageCount == history.count + 1)
        #expect(journal.detail.summary.lastMessagePreview == "Keep this active task.")
        #expect(!journal.detail.events.contains { $0.runtimeMetadata?.checkpoint != nil })
        #expect(journal.detail.events.compactMap(\.toolCall).isEmpty)
        #expect(Set(history.map(\.id)).isSubset(of: Set(journal.detail.events.map(\.id))))
        let metadata = try #require(journal.detail.events.last { $0.runtimeMetadata?.runState != nil }?.runtimeMetadata)
        let saved = try JSONValueCoder.decode(RunStateSnapshot.self, from: #require(metadata.runState))
        #expect(saved.phase == .stopping)
        #expect(saved.requestAttempts == 1)
        let request = ModelStepRequest(runId: metadata.runId, userTurnId: metadata.userTurnId,
            stepId: "inspect", attemptId: "inspect", model: model, projectionRevision: "", cacheScope: "inspect", messages: [])
        let projected = try SessionProjection.project(journal).modelMessages(for: request)
        #expect(projected.contains { $0.text == "Keep this active task." })
        #expect(projected.filter { $0.role == .assistant && $0.text.hasPrefix("Historical detail for message") }.count == 40)
    }

    @Test(.timeLimit(.minutes(3)))
    func backgroundCompactionCannotBorrowHiddenForegroundHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("context-scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("mobile"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "mobile", request: .init())
        let foreground = (0..<8).map { index in
            AgentSessionEvent(agentId: "mobile", sessionId: session.id, type: .message,
                message: .init(role: index.isMultiple(of: 2) ? .user : .assistant,
                    segments: [.init(kind: .text, text: "FOREGROUND ONLY \(index)")]))
        }
        _ = try store.appendEvents(agentID: "mobile", sessionID: session.id, events: foreground)
        let model = "openai-api:portable-fixture"
        let source = AgentDerivedWorkSource(agentID: "mobile", sessionID: session.id,
            owner: .init(runId: "source-run", userTurnId: "source-turn", generation: 0),
            terminalEventID: "source-terminal", model: model)
        var settings = RunRequestSettings(retryDelays: [], reasoningEffort: nil)
        settings.toolScope = []
        settings.delegatedAuthority = .init(policy: .init(), workingDirectory: root.path, extraRoots: [root.path])
        settings.derivedSource = source
        var config = NativeAgentLoopConfig(engine: .unified, requiresExplicitCompletion: false)
        config.completionContract = .background
        let snapshot = RunStateSnapshot(schemaVersion: 2, runID: "background-run", userTurnID: "background-turn",
            loopConfig: config, model: model, requestSettings: settings)
        let state = try RunState(snapshot: snapshot)
        var metadata = AgentRunMetadata(runId: state.runID, userTurnId: state.userTurnID,
            runState: try JSONValueCoder.encode(snapshot), admissionInstructions: (0..<4).map { _ in
                .init(kind: .turnContext, text: String(repeating: "Protected background data. ", count: 250))
            })
        metadata.derivedSource = source
        _ = try store.appendEvents(agentID: "mobile", sessionID: session.id, events: [
            .init(version: 2, agentId: "mobile", sessionId: session.id, type: .runStatus, runtimeMetadata: metadata)
        ])
        let script = PortableCompactionScript()
        let provider = ContextLimitedModelProvider(wrapping: PortableCompactionFactory(script: script),
            limits: [model: .init(contextWindowTokens: 4_096)])
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: provider, memoryStore: InMemoryMemoryStore(),
            configuration: .init(defaultModel: model))
        let journal = SessionLoopJournal(store: store, agentID: "mobile", sessionID: session.id,
            authorizeWriter: {}, includeResponseMessages: false, derivedSource: source)
        _ = await runtime.postMessage(channelId: "background-scope", request: .init(userId: "fixture", content: "Internal", model: model),
            forceInlineResponse: true, nativeLoopConfig: config, runState: state,
            agentLoopServices: .init(journal: journal, executor: .init(invoke: { _, _, _, _ in
                Issue.record("An over-budget background request executed a tool"); throw CancellationError()
            })))
        #expect(await script.requests.isEmpty)
        #expect(await state.requestAttempts == 0)
        let detail = try store.loadSession(agentID: "mobile", sessionID: session.id)
        #expect(!detail.events.contains { $0.runtimeMetadata?.checkpoint != nil })
        #expect(Set(foreground.map(\.id)).isSubset(of: Set(detail.events.map(\.id))))
    }

    @Test(.timeLimit(.minutes(3)), arguments: [false, true])
    func nativeCompactionKeepsCanonicalHistoryAndProtectedTask(withImage: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-compaction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableCompactionScript(), model = "openai-api:portable-fixture"
        let provider = ContextLimitedModelProvider(wrapping: PortableCompactionFactory(script: script),
            limits: [model: .init(contextWindowTokens: withImage ? 18_432 : 16_384)])
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: provider, memoryStore: InMemoryMemoryStore(),
            configuration: .init(defaultModel: model))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased()
        let (store, _) = try await host.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
        var history: [AgentSessionEvent] = []
        for index in 0..<40 {
            history += [
                .init(agentId: "mobile", sessionId: sessionID, type: .message,
                    message: .init(role: .user, segments: [.init(kind: .text, text: "Earlier request \(index).")])),
                .init(agentId: "mobile", sessionId: sessionID, type: .message,
                    message: .init(role: .assistant, segments: [.init(kind: .text,
                        text: String(repeating: "Historical detail for message \(index).\n", count: 64))]))
            ]
        }
        _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: history)
        let image = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jR9sAAAAASUVORK5CYII="))
        var failure: Error?, answer: String?
        do {
            answer = try await host.send(prompt: "Keep this current task intact.", sessionID: sessionID, workspaceURL: root,
                build: { Issue.record("Compaction invoked a tool"); return .init(ok: false, summary: "Unexpected") },
                onText: { _ in }, images: withImage ? [.init(data: image, mimeType: "image/png")] : [], persistedSessionID: sessionID)
        } catch { failure = error }
        #expect(failure == nil)
        #expect(answer == "The current task and protected context were retained.")
        let requests = await script.requests
        #expect(requests.contains { $0.purpose.rawValue == "compaction" && $0.tools.isEmpty })
        let work = requests.last { $0.purpose == .work }
        #expect(work?.messages.contains { $0.text.components(separatedBy: "\n").first == "Keep this current task intact." } == true)
        #expect(work?.messages.contains { $0.text == "Earlier request 0." } == true)
        #expect(work?.messages.contains { $0.text == "Earlier request 39." } == true)
        let images = work?.messages.flatMap(\.images) ?? []
        #expect(images.count == (withImage ? 1 : 0))
        if withImage { #expect(images.first?.data == image) }
        let detail = try store.loadSession(agentID: "mobile", sessionID: sessionID)
        #expect(Set(history.map(\.id)).isSubset(of: Set(detail.events.map(\.id))))
        let visible = try await host.messages(workspaceURL: root)
        #expect(visible.count == history.count + 2)
        #expect(detail.summary.messageCount == history.count + 2)
        #expect(detail.events.contains { $0.runtimeMetadata?.checkpoint != nil })
        let checkpoint = try detail.events.last(where: { $0.runtimeMetadata?.runState != nil })?.runtimeMetadata?.runState.map {
            try JSONValueCoder.decode(RunStateSnapshot.self, from: $0)
        }
        #expect(checkpoint?.phase == .settled)
        #expect(checkpoint?.requestAttempts == requests.count)
    }

    @Test(.timeLimit(.minutes(3)), arguments: [true, false])
    func nativePreparationBudgetsProtectedContextBeforeGeneration(enabled: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-budget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableHostScript(), model = "openai-api:portable-fixture"
        let provider = ContextLimitedModelProvider(wrapping: PortableHostFactory(script: script),
            limits: [model: .init(contextWindowTokens: 512)])
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: provider, memoryStore: InMemoryMemoryStore(),
            configuration: .init(defaultModel: model, compactorConfiguration: .init(enabled: enabled)))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased()
        var failure: Error?
        do {
            _ = try await host.send(prompt: "Create the project.", sessionID: sessionID, workspaceURL: root,
                build: { .init(ok: true, summary: "Built") }, onText: { _ in }, persistedSessionID: sessionID)
        } catch { failure = error }
        let requests = await script.requests
        if enabled {
            #expect(failure != nil)
            #expect(requests.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/main.ada").path))
            let (store, _) = try await host.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
            let detail = try store.loadSession(agentID: "mobile", sessionID: sessionID)
            let saved = try detail.events.last(where: { $0.runtimeMetadata?.runState != nil })?.runtimeMetadata?.runState.map {
                try JSONValueCoder.decode(RunStateSnapshot.self, from: $0)
            }
            #expect(saved?.phase == .stopping)
            #expect(saved?.requestAttempts == 0)
            #expect(saved?.toolStop?.modelFailure?.category == .context)
        } else {
            #expect(failure == nil)
            #expect(requests.count == 2)
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func embeddedCacheScopeIncludesWorkspaceAndStoredConversation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-scope-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableHostScript()
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: "openai-api:portable-fixture"))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: "openai-api:portable-fixture", nativeEngine: .unified)
        for index in 0..<2 {
            let workspace = root.appendingPathComponent("project-\(index)")
            _ = try await host.send(prompt: "Create project \(index).", sessionID: "shared-ui-channel", workspaceURL: workspace,
                build: { .init(ok: true, summary: "Built") }, onText: { _ in },
                persistedSessionID: "session-" + UUID().uuidString.lowercased())
            #expect((try? String(contentsOf: workspace.appendingPathComponent("Sources/main.ada"), encoding: .utf8)) == "portable fixture")
        }
        let requests = await script.requests
        #expect(requests.count == 4)
        #expect(Set(requests.map(\.cacheScope)).count == 2)
        #expect(!requests[2].messages.contains { $0.text == "Create project 0." })
    }

    @Test(.timeLimit(.minutes(3)), arguments: EmbeddedRecoveryCase.allCases)
    fileprivate func embeddedRestartRetainsReceiptAndNeverReplaysUnknownEffects(scenario: EmbeddedRecoveryCase) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-host-restart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableHostScript()
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: "openai-api:portable-fixture"))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: "openai-api:portable-fixture", nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased(), inputID = UUID().uuidString
        _ = try await host.send(prompt: "Create the project.", sessionID: sessionID, workspaceURL: root,
            build: { .init(ok: true, summary: "Built") }, onText: { _ in }, persistedSessionID: sessionID, clientMessageID: inputID)
        let (store, _) = try await host.prepareSession(channelID: sessionID, workspaceURL: root, persistedSessionID: sessionID)
        let journal = try store.loadJournal(agentID: "mobile", sessionID: sessionID)
        let file = URL(fileURLWithPath: try store.sessionFilePath(agentID: "mobile", sessionID: sessionID))
        let complete = try Data(contentsOf: file)
        if scenario == .terminal {
            let boundary = try #require(journal.records.last { $0.event.runtimeMetadata?.runState != nil })
            try complete.prefix(Int(boundary.endCursor)).write(to: file)
        } else if scenario == .unknownEffect {
            let boundary = try #require(journal.records.first { $0.event.runtimeMetadata?.executionPhase == .started })
            try complete.prefix(Int(boundary.endCursor)).write(to: file)
        } else {
            try Data(#"{"version":99,"journalVersion":3}"#.utf8).write(
                to: root.appendingPathComponent(".ada/workspace/native-agent-v1/format.json"))
        }
        let before = try Data(contentsOf: file)
        // A fresh public host has neither credentials nor a provider. Saved delivery needs neither.
        let freshHost = SloppyRuntimeHost(nativeEngine: .unified)
        var failure: Error?, answer: String?
        do {
            answer = try await freshHost.send(prompt: "Create the project.", sessionID: sessionID, workspaceURL: root,
                build: { Issue.record("A recovered effect was replayed"); return .init(ok: false, summary: "Unexpected build") },
                onText: { _ in }, persistedSessionID: sessionID, clientMessageID: inputID)
        } catch { failure = error }
        if scenario == .terminal {
            #expect(failure == nil)
            #expect(answer == "Created and built the portable project.")
            let saved = try store.loadSession(agentID: "mobile", sessionID: sessionID)
            #expect(try SessionInputLifecycle.states(in: saved.events)[inputID]?.latest.delivery == .delivered)
            let deliveredBytes = try Data(contentsOf: file)
            _ = try await freshHost.send(prompt: "Create the project.", sessionID: sessionID, workspaceURL: root,
                build: { Issue.record("A settled effect was replayed"); return .init(ok: false, summary: "Unexpected build") },
                onText: { _ in }, persistedSessionID: sessionID, clientMessageID: inputID)
            #expect(try Data(contentsOf: file) == deliveredBytes)
        } else {
            #expect(failure != nil)
            #expect(try Data(contentsOf: file) == before)
            if scenario == .unknownEffect {
                guard let error = failure as? SloppyRuntimeHost.HostError, case .reconciliationRequired = error else {
                    Issue.record("Unknown effects did not produce the explicit reconciliation error"); return
                }
            }
        }
        #expect(await script.requests.count == 2)
        #expect((try? String(contentsOf: root.appendingPathComponent("Sources/main.ada"), encoding: .utf8)) == "portable fixture")
    }

    @Test
    func immediatelyConcurrentCallsToOneHostBothRetainQueueOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-concurrent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableHostScript(), model = "openai-api:portable-fixture"
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: model))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .unified)
        let session = "session-" + UUID().uuidString.lowercased()
        try await withThrowingTaskGroup(of: String.self) { group in
            for content in ["First", "Second"] {
                group.addTask { try await host.send(prompt: content, sessionID: session, workspaceURL: root,
                    build: { .init(ok: true, summary: "Built") }, onText: { _ in }, persistedSessionID: session) }
            }
            var replies = 0
            for try await reply in group { #expect(!reply.isEmpty); replies += 1 }
            #expect(replies == 2)
        }
        #expect(await script.requests.count == 4)
    }

    @Test
    func lowLevelLegacySelectorUsesTheSameLoopAndRetainsItsInMemoryTranscript() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("runtime-selector-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = PortableHostScript(), model = "openai-api:portable-fixture"
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: model))
        let workspace = SloppyWorkspaceToolExecutor(rootURL: root, build: {
            let text = try? String(contentsOf: root.appendingPathComponent("Sources/main.ada"), encoding: .utf8)
            return .init(ok: text == "portable fixture", summary: "Checked actual source")
        })
        for content in ["First request", "Second request"] {
            _ = await runtime.postMessage(channelId: "channel", request: .init(userId: "fixture", content: content, model: model),
                toolInvoker: { await workspace.invoke($0) }, forceInlineResponse: true,
                nativeLoopConfig: .init(engine: .legacy, requiresExplicitCompletion: false))
        }
        let ledger = try #require(await runtime.contextLedgerSnapshot(channelId: "channel"))
        #expect(ledger.entries.contains { $0.category == .currentTurn })
        #expect(ledger.entries.contains { $0.category == .toolsSchema })
        #expect(ledger.entries.contains { $0.category == .toolResults })
        let requests = await script.requests
        #expect(requests.count == 4)
        #expect(requests.last?.messages.contains { $0.text == "First request" } == true)
        #expect(requests.last?.messages.contains { $0.text == "Second request" } == true)
        #expect(requests.last?.messages.compactMap(\.toolOutput).count == 4)
        #expect((try? String(contentsOf: root.appendingPathComponent("Sources/main.ada"), encoding: .utf8)) == "portable fixture")
    }

    @Test
    func legacyHostSendImportsSettledHistoryAndUsesOnlyTheCanonicalOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-legacy-import-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyRoot = root.appendingPathComponent(".ada/workspace/agents")
        try FileManager.default.createDirectory(at: legacyRoot.appendingPathComponent("mobile"), withIntermediateDirectories: true)
        let legacy = AgentSessionFileStore(agentsRootURL: legacyRoot)
        let session = try legacy.createSession(agentID: "mobile", request: .init())
        _ = try legacy.appendEvents(agentID: "mobile", sessionID: session.id, events: [
            .init(agentId: "mobile", sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Earlier game requirement")]))
        ])
        let source = URL(fileURLWithPath: try legacy.sessionFilePath(agentID: "mobile", sessionID: session.id))
        let before = try Data(contentsOf: source)
        let script = PortableHostScript(), model = "openai-api:portable-fixture"
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: model))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .legacy)
        _ = try await host.send(prompt: "Continue", sessionID: session.id, workspaceURL: root,
            build: { .init(ok: true, summary: "Built") }, onText: { _ in }, persistedSessionID: session.id)
        #expect(try Data(contentsOf: source) == before)
        let store = AgentSessionFileStore(agentsRootURL: root.appendingPathComponent(".ada/workspace/native-agent-v1/agents"))
        let detail = try store.loadSession(agentID: "mobile", sessionID: session.id)
        #expect(detail.events.contains { $0.isHistorical && $0.message?.segments.first?.text == "Earlier game requirement" })
        #expect(await script.requests.count == 2)
        #expect(await script.requests.first?.messages.contains { $0.text.contains("Earlier game requirement") } == true)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 2)
    }

    @Test
    func missingCredentialsCannotLeaveANewInputBlockingTheQueue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-no-credentials-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = SloppyRuntimeHost(nativeEngine: .unified)
        let session = "session-" + UUID().uuidString.lowercased()
        await #expect(throws: (any Error).self) {
            try await host.send(prompt: "New request", sessionID: session, workspaceURL: root,
                build: { .init(ok: false, summary: "Unexpected") }, onText: { _ in }, persistedSessionID: session)
        }
        let store = AgentSessionFileStore(agentsRootURL: root.appendingPathComponent(".ada/workspace/native-agent-v1/agents"))
        #expect(try SessionInputLifecycle.states(in: store.loadSession(agentID: "mobile", sessionID: session).events).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func awaitedBuildCallbackCannotDeadlockItsOwnConversation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-reentry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = "openai-api:portable-fixture"
        let script = PortableHostScript()
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: model))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased()
        let result = try await host.send(prompt: "Outer", sessionID: sessionID, workspaceURL: root,
            build: {
                do {
                    _ = try await host.send(prompt: "Nested", sessionID: sessionID, workspaceURL: root,
                        build: { .init(ok: false, summary: "Unexpected nested build") }, onText: { _ in }, persistedSessionID: sessionID)
                    Issue.record("Reentrant send was not rejected")
                } catch SloppyRuntimeHost.HostError.reentrantSend {} catch { Issue.record("Unexpected reentry error: \(error)") }
                return .init(ok: true, summary: "Built")
            }, onText: { _ in }, persistedSessionID: sessionID)
        #expect(!result.isEmpty)
        #expect(await script.requests.count == 2)
        let store = AgentSessionFileStore(agentsRootURL: root.appendingPathComponent(".ada/workspace/native-agent-v1/agents"))
        #expect(try store.loadSession(agentID: "mobile", sessionID: sessionID).events.filter { $0.message?.role == .user }.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func independentEmbeddedHostsCannotEnqueueIntoAnOwnedSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-ownership-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = "openai-api:portable-fixture"
        let gate = EmbeddedBuildGate()
        let script = PortableHostScript(generationGate: gate)
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: model))
        let first = SloppyRuntimeHost(runtime: runtime, modelID: model, nativeEngine: .unified)
        let otherRuntime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: model))
        let second = SloppyRuntimeHost(runtime: otherRuntime, modelID: model, nativeEngine: .unified)
        let sessionID = "session-" + UUID().uuidString.lowercased()
        let owner = Task { try await first.send(prompt: "First", sessionID: sessionID, workspaceURL: root,
            build: { .init(ok: true, summary: "Built") }, onText: { _ in }, persistedSessionID: sessionID) }
        await gate.waitUntilStarted()
        let files = AgentSessionFileStore(agentsRootURL: root.appendingPathComponent(".ada/workspace/native-agent-v1/agents"))
        let path = URL(fileURLWithPath: try files.sessionFilePath(agentID: "mobile", sessionID: sessionID))
        let before = try Data(contentsOf: path)
        var rejected = false
        do { _ = try await second.send(prompt: "Contender", sessionID: sessionID, workspaceURL: root,
            build: { .init(ok: true, summary: "Unexpected") }, onText: { _ in }, persistedSessionID: sessionID) }
        catch { rejected = true }
        #expect(rejected)
        #expect(try Data(contentsOf: path) == before)
        await gate.release()
        _ = try await owner.value
        _ = try await second.send(prompt: "After release", sessionID: sessionID, workspaceURL: root,
            build: { .init(ok: true, summary: "Built") }, onText: { _ in }, persistedSessionID: sessionID)
        #expect(await script.requests.count == 4)
    }

    @Test(.timeLimit(.minutes(3)))
    func embeddedHostUsesDurableSharedLoopAndIsolatesLegacyStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-host-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyRoot = root.appendingPathComponent(".ada/workspace/agents")
        try FileManager.default.createDirectory(at: legacyRoot.appendingPathComponent("mobile"), withIntermediateDirectories: true)
        let legacy = AgentSessionFileStore(agentsRootURL: legacyRoot)
        let old = try legacy.createSession(agentID: "mobile", request: .init())
        _ = try legacy.appendEvents(agentID: "mobile", sessionID: old.id, events: [
            .init(agentId: "mobile", sessionId: old.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Legacy conversation")]))
        ])
        let script = PortableHostScript()
        let runtime = SloppyRuntimeBootstrap.makeSystem(modelProvider: PortableHostFactory(script: script),
            memoryStore: InMemoryMemoryStore(), configuration: .init(defaultModel: "openai-api:portable-fixture"))
        let host = SloppyRuntimeHost(runtime: runtime, modelID: "openai-api:portable-fixture", nativeEngine: .unified)
        let selected = "session-" + UUID().uuidString.lowercased()
        var failure: Error?
        var answer: String?
        do {
            answer = try await host.send(prompt: "Create the project.", sessionID: selected, workspaceURL: root,
                build: {
                    let text = try? String(contentsOf: root.appendingPathComponent("Sources/main.ada"), encoding: .utf8)
                    return .init(ok: text == "portable fixture", summary: "Verified project contents")
                }, onText: { _ in }, persistedSessionID: selected)
        } catch { failure = error }
        #expect(failure == nil)
        #expect(answer == "Created and built the portable project.")
        #expect((try? String(contentsOf: root.appendingPathComponent("Sources/main.ada"), encoding: .utf8)) == "portable fixture")
        let (store, sessionID) = try await host.prepareSession(channelID: selected, workspaceURL: root, persistedSessionID: selected)
        let fresh = try store.loadSession(agentID: "mobile", sessionID: sessionID)
        #expect(fresh.events.filter { $0.message?.role == .user }.count == 1)
        #expect(fresh.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 2)
        #expect(fresh.events.compactMap(\.toolResult).count == 2)
        #expect(fresh.events.compactMap(\.toolResult).allSatisfy { $0.ok })
        #expect(SessionToolRecovery.unknownEffectCallIDs(in: fresh.events).isEmpty)
        let checkpoint = try fresh.events.last(where: { $0.runtimeMetadata?.runState != nil })?.runtimeMetadata?.runState.map {
            try JSONValueCoder.decode(RunStateSnapshot.self, from: $0)
        }
        #expect(checkpoint?.phase == .settled)
        #expect(checkpoint?.toolRoundsUsed == 1)
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.last?.messages.compactMap(\.toolOutput).count == 2)
        #expect(try legacy.listSessions(agentID: "mobile").count == 1)
        #expect(try legacy.loadSession(agentID: "mobile", sessionID: old.id).summary.messageCount == 1)
    }
}
