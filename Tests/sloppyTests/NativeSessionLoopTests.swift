import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

actor SessionStepGate {
    private var released = false
    private var arrived = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [String: AsyncStream<Bool>.Continuation] = [:]

    func hold() async {
        arrived = true
        for waiter in arrivalWaiters.values { waiter.yield(true); waiter.finish() }
        arrivalWaiters.removeAll()
        if !released { await withCheckedContinuation { continuations.append($0) } }
    }

    func waitUntilHeld<T: Sendable>(during operation: Task<T, Error>) async -> Bool {
        if arrived { return true }
        let id = UUID().uuidString
        let subscription = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        arrivalWaiters[id] = subscription.continuation
        let completion = Task { [weak self] in
            _ = try? await operation.value
            await self?.finishArrival(id)
        }
        defer {
            completion.cancel()
            arrivalWaiters.removeValue(forKey: id)?.finish()
        }
        for await signal in subscription.stream { return signal }
        return false
    }

    private func finishArrival(_ id: String) {
        guard let waiter = arrivalWaiters.removeValue(forKey: id) else { return }
        waiter.yield(false)
        waiter.finish()
    }

    func release() {
        released = true
        for continuation in continuations { continuation.resume() }
        continuations.removeAll()
    }
}

private actor SessionStepScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    private(set) var legacyCalls = 0
    private var index = 0
    private let firstRequestGate: SessionStepGate?
    private let gateIndex: Int
    private let finishWithCompletion: Bool
    private let perResponseUsage: Protocols.TokenUsage?
    init(firstRequestGate: SessionStepGate? = nil, gateIndex: Int = 0, initialIndex: Int = 0, finishWithCompletion: Bool = false,
         usage: Protocols.TokenUsage? = nil) {
        self.firstRequestGate = firstRequestGate
        self.gateIndex = gateIndex
        self.index = initialIndex
        self.finishWithCompletion = finishWithCompletion
        self.perResponseUsage = usage
    }
    func legacy() { legacyCalls += 1 }
    func next(_ request: ModelStepRequest) async -> ModelStepResponse {
        requests.append(request)
        if index == gateIndex { await firstRequestGate?.hold() }
        defer { index += 1 }
        if index.isMultiple(of: 2) {
            return .init(toolCalls: [.init(id: "read-\(index)", name: "files_read", rawArguments: "{\"path\":\"session-target.txt\"}")], stopReason: .toolCalls, usage: perResponseUsage)
        }
        if finishWithCompletion {
            return .init(toolCalls: [.init(id: "complete-\(index)", name: "session_complete",
                rawArguments: #"{"status":"completed","summary":"Read result reported.","verificationEvidenceIds":[]}"#)], stopReason: .toolCalls, usage: perResponseUsage)
        }
        return .init(text: "Read result reported.", stopReason: .endTurn, usage: perResponseUsage)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                continuation.yield(.started)
                continuation.yield(.final(await self.next(request)))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}

private struct SessionReadDeclaration: Tool {
    @Generable struct Arguments { var path: String }
    typealias Output = String
    let name = "files.read"
    let description = "Read the complete requested file"
    func call(arguments: Arguments) async throws -> String {
        throw ModelStepFailure(category: .protocolViolation, code: "provider_executed_tool", message: "Declarations cannot execute effects")
    }
}

private struct NativeApprovalWriteDeclaration: Tool {
    @Generable struct Arguments { var path: String; var content: String }
    typealias Output = String
    let name = "files.write"
    let description = "Write the approved fixture file"
    func call(arguments: Arguments) async throws -> String { throw CancellationError() }
}

private actor NativeApprovalScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    func next(_ request: ModelStepRequest) -> ModelStepResponse {
        requests.append(request)
        if requests.count == 1 {
            return .init(toolCalls: [.init(id: "approved-write", name: "files_write",
                rawArguments: #"{"path":"approval-output.txt","content":"approved original effect"}"#)], stopReason: .toolCalls)
        }
        return .init(text: "Approved effect completed.", stopReason: .endTurn)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { continuation.yield(.started); continuation.yield(.final(await self.next(request))); continuation.finish() }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct NativeApprovalFactory: ModelProvider, ModelStepProviderFactory {
    let id = "native-approval-fixture"
    let supportedModels = ["openai-api:gpt-5.4-mini"]
    let script: NativeApprovalScript
    var tools: [any Tool] { [NativeApprovalWriteDeclaration()] }
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { throw CancellationError() }
}

private struct SessionCompletionDeclaration: Tool {
    @Generable struct Arguments {
        var status: String
        var summary: String
        var verificationEvidenceIds: [String]
    }
    let name = "session.complete"
    let description = "Commit the completed task summary"
    func call(arguments: Arguments) async throws -> String {
        throw ModelStepFailure(category: .protocolViolation, code: "provider_executed_tool", message: "Declarations cannot execute effects")
    }
}

private struct SessionStepFactory: ModelProvider, ModelStepProviderFactory {
    let id = "session-step-fixture"
    let supportedModels = ["openai-api:gpt-5.4-mini"]
    let script: SessionStepScript
    var allowsLegacy = false
    var allowsModelSteps = true
    var tools: [any Tool] { [SessionReadDeclaration(), SessionCompletionDeclaration()] }
    func supportsModelSteps(for modelName: String) -> Bool { allowsModelSteps && supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { allowsModelSteps ? script : nil }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        await script.legacy()
        if allowsLegacy { return SessionLegacyTextModel() }
        throw ModelStepFailure(category: .protocolViolation, code: "legacy_generation_used", message: "Unified sessions must not create a legacy model session")
    }
}

private struct SessionLegacyTextModel: LanguageModel {
    typealias UnavailableReason = Never
    func respond<Content>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let raw = GeneratedContent("Legacy answer")
        return .init(content: try Content(raw), rawContent: raw, transcriptEntries: [])
    }
    func streamResponse<Content>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        .init(stream: AsyncThrowingStream { continuation in
            do {
                let raw = GeneratedContent("Legacy answer")
                continuation.yield(.init(content: try Content.PartiallyGenerated(raw), rawContent: raw))
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        })
    }
}

private enum SessionRecoveryWindow: Sendable { case acceptance, acceptancePrefix, prePersistedAcceptancePrefix, prePersistedAcceptanceCheckpoint, prePersistedResult, settled, settledWithoutStepProvider, completionWithoutStepProvider, completionResultWithoutStepProvider, completionFinalizingWithoutStepProvider, completionWithDurableInterrupt, completionWithLegacyInterrupt }

private actor SessionResultCrash {
    enum Trigger: Sendable { case acceptance, acceptancePrefix, result, completionResult, finalizing, settled }
    private let trigger: Trigger
    let journal: URL
    let preserved: URL
    private(set) var tripped = false
    private(set) var failure: String?
    private(set) var acceptedContext: [String] = []
    init(journal: URL, trigger: Trigger = .result) {
        self.trigger = trigger
        self.journal = journal
        self.preserved = journal.deletingLastPathComponent().appendingPathComponent("fault-" + UUID().uuidString.prefix(8) + ".jsonl")
    }
    func observe(_ events: [AgentSessionEvent]) {
        guard !tripped, events.contains(where: {
            switch trigger {
            case .acceptance, .acceptancePrefix:
                return $0.runtimeMetadata?.requestFingerprint != nil && $0.runStatus?.stage == .responding
            case .result:
                return $0.toolResult != nil && $0.runtimeMetadata?.executionPhase == .settled &&
                    $0.runtimeMetadata?.observationOnly == false
            case .completionResult:
                return $0.toolResult != nil && $0.runtimeMetadata?.completionCandidate != nil &&
                    $0.runtimeMetadata?.executionPhase == .settled && $0.runtimeMetadata?.observationOnly == false
            case .settled, .finalizing:
                guard let raw = $0.runtimeMetadata?.runState,
                      let snapshot = try? JSONValueCoder.decode(RunStateSnapshot.self, from: raw) else { return false }
                return snapshot.phase == (trigger == .finalizing ? .finalizing : .settled)
            }
        }) else { return }
        tripped = true
        acceptedContext = events.flatMap { event in
            // Inspect the wire envelope so the failure fixture supports both admission formats.
            guard let value = try? JSONValueCoder.encode(event.runtimeMetadata) else { return [String]() }
            let metadata = value.asObject ?? [:]
            return ([metadata["instruction"]].compactMap { $0?.asObject?["text"]?.asString }) +
                (metadata["admissionInstructions"]?.asArray ?? []).compactMap { $0.asObject?["text"]?.asString }
        }
        do {
            try FileManager.default.moveItem(at: journal, to: preserved)
            // Block the next append before reading/truncating the preserved prefix.
            try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: false)
            if trigger == .acceptancePrefix {
                let bytes = try Data(contentsOf: preserved)
                let lines = bytes.split(separator: 10, omittingEmptySubsequences: true)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let end = try #require(lines.firstIndex { line in
                    let event = try? decoder.decode(AgentSessionEvent.self, from: Data(line))
                    return event?.runtimeMetadata?.requestFingerprint != nil
                })
                var prefix = Data()
                for line in lines[...end] { prefix.append(contentsOf: line); prefix.append(10) }
                let handle = try FileHandle(forWritingTo: preserved)
                defer { try? handle.close() }
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: prefix)
                try handle.synchronize()
            }
        } catch { failure = String(reflecting: error) }
    }
    func restore() throws {
        guard FileManager.default.fileExists(atPath: preserved.path) else { return }
        if FileManager.default.fileExists(atPath: journal.path) {
            let contents = try FileManager.default.contentsOfDirectory(atPath: journal.path)
            guard contents.isEmpty else { throw CocoaError(.fileWriteFileExists) }
            try FileManager.default.removeItem(at: journal)
        }
        try FileManager.default.moveItem(at: preserved, to: journal)
    }
}


private actor SessionNativeCalls {
    private(set) var count = 0
    func record() { count += 1 }
}

private struct SessionIdentityFixture {
    let service: CoreService
    let agentID: String
    let session: AgentSessionSummary
    let file: URL

    static func make(script: SessionStepScript, capabilities: [String] = ["tools"],
                     reasoningEffort: ReasoningEffort? = nil) async throws -> Self {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: capabilities)]
        await service.overrideModelProviderForTests(SessionStepFactory(script: script), defaultModel: models[0].id)
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let agentID = "native-identity-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native identity fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, reasoningEffort: reasoningEffort, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native identity fixture"))
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        try "historical read content".write(to: file, atomically: true, encoding: .utf8)
        return .init(service: service, agentID: agentID, session: session, file: file)
    }
}

private enum SessionFixtureFailure: Error { case receipt(any Error), original(any Error) }
private enum SessionHistorySubmission: Sendable { case direct, peer, ui }

private extension CoreService {
    /// End the previous owner while preserving the exact deliberately injected crash image.
    func exitPreservingCrashImageForLoopTests() async throws {
        let root = workspaceRootURL
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).compactMap { path -> (URL, Data)? in
            guard path.hasSuffix(".jsonl") || path == "session-messages/inbox.json" || path == ".runtime/tool-approvals-v1.json" else { return nil }
            let file = root.appendingPathComponent(path)
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &directory), !directory.boolValue else { return nil }
            return (file, try Data(contentsOf: file))
        }
        await stop()
        for (file, data) in files { try data.write(to: file, options: .atomic) }
    }
    func stopInboxDispatchForLoopTests() { sessionMessageIsStopping = true }
    func seedLegacyInboxForLoopTests(_ entry: SessionMessageInboxFileStore.Entry) throws {
        _ = try sessionMessageInbox().enqueue(entry)
    }

    func activeMessageOperationForLoopTests(agentID: String, sessionID: String) -> Task<AgentSessionMessageResponse, Error>? {
        sessionMessageOperations[sessionStreamKey(agentID: agentID, sessionID: sessionID)]?.task
    }
    func holdInboxForLoopTests(_ id: String) { activeSessionMessageRuns.insert(id) }
    func releaseInboxForLoopTests(agentID: String, sessionID: String) {
        activeSessionMessageRuns.remove(sessionID)
        scheduleSessionInbox(agentID: agentID, sessionID: sessionID)
    }
    func rememberDelegatedScopeForLoopTests(sessionID: String) throws {
        sessionSubagentToolAllowList[sessionID] = SessionCommunicationPolicy.tools
        try sessionMessageInbox().rememberScope(sessionID: sessionID, toolIDs: SessionCommunicationPolicy.tools)
    }
    func setControlAdmissionForLoopTests(_ observer: @escaping @Sendable () async -> Void) {
        sessionControlAdmissionForTests = observer
    }
    func setMessagePreparationForLoopTests(_ observer: @escaping @Sendable () async -> Void) {
        sessionMessagePreparationForTests = observer
    }
    func inboxEntryForLoopTests(_ id: String) throws -> SessionMessageInboxFileStore.Entry? {
        try sessionMessageInbox().entries.first { $0.id == id }
    }
}

@Suite("Core unified session integration")
struct NativeSessionLoopTests {
    @Test(.timeLimit(.minutes(10)))
    func coreToolArtifactIsRetrievableOnlyFromItsSessionWithMatchingBytes() async throws {
        let fixture = try await SessionIdentityFixture.make(script: SessionStepScript())
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file); Task { await service.stop() } }
        try String(repeating: "Complete large read output.\n", count: 2_000).write(to: fixture.file, atomically: true, encoding: .utf8)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Read the full fixture.", mode: .ask))
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let artifact = try #require(detail.events.compactMap(\.runtimeMetadata?.toolOutputArtifact).first)
        let loaded = try await service.getAgentSessionAttachment(agentID: fixture.agentID, sessionID: fixture.session.id,
            attachmentID: artifact.attachment.id)
        #expect(ContentDigest.sha256(loaded.data) == artifact.sha256)
        #expect(loaded.data.count == artifact.attachment.sizeBytes)
        #expect(loaded.mediaType == "application/json")
        #expect(try JSONDecoder().decode(ToolInvocationResult.self, from: loaded.data).ok)
        let chunk = try #require(try await service.getAgentSessionAttachmentChunk(agentID: fixture.agentID,
            sessionID: fixture.session.id, attachmentID: artifact.attachment.id, offset: 7, limit: 53))
        #expect(chunk.data == loaded.data[7..<60])
        let router = CoreRouter(service: service)
        let response = await router.handle(method: "GET", path: artifact.downloadPath, body: nil, headers: ["Range": "bytes=7-59"])
        #expect(response.status == 206)
        #expect(response.body == chunk.data)
        #expect(response.headers["Content-Range"] == "bytes 7-59/\(loaded.data.count)")
        let other = try await service.sessionOrchestrator.createSession(agentID: fixture.agentID, request: .init())
        var denied = false
        do { _ = try await service.getAgentSessionAttachment(agentID: fixture.agentID, sessionID: other.id, attachmentID: artifact.attachment.id) }
        catch { denied = true }
        #expect(denied)
    }

    @Test(.timeLimit(.minutes(10)))
    func restartContinuesTheOriginalApprovedEffectWithoutAnotherToolResponse() async throws {
        let config = CoreConfig.test, script = NativeApprovalScript(), model = "openai-api:gpt-5.4-mini"
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        await service.overrideModelProviderForTests(NativeApprovalFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "approval-restart-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Approved native restart"))
        let root = config.resolvedWorkspaceRootURL(), store = AgentSessionFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let catalog = AgentCatalogFileStore(agentsRootURL: root.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        _ = try await service.updateAgentToolsPolicy(agentID: agentID, request: .init(approval: .init(enabled: true)))
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Perform the approved write.", mode: .ask, clientMessageId: UUID().uuidString)
        let operation = Task { try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request) }
        defer { operation.cancel() }
        var approval: ToolApprovalRecord?
        for _ in 0..<500 {
            approval = await service.listPendingToolApprovals().first
            if approval != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pending = try #require(approval)
        let file = URL(fileURLWithPath: try store.sessionFilePath(agentID: agentID, sessionID: session.id))
        let approvalsFile = root.appendingPathComponent(".runtime/tool-approvals-v1.json")
        let prefix = try Data(contentsOf: file), savedApprovals = try Data(contentsOf: approvalsFile)
        operation.cancel(); _ = try? await operation.value; await service.stop()
        try prefix.write(to: file, options: .atomic)
        try savedApprovals.write(to: approvalsFile, options: .atomic)
        let fresh = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await fresh.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await fresh.stop() } }
        await fresh.overrideModelProviderForTests(NativeApprovalFactory(script: script), defaultModel: model)
        await fresh.sessionOrchestrator.updateAvailableModels(models)
        #expect(await fresh.toolApprovalService.approve(id: pending.id, decidedBy: "fixture")?.status == .approved)
        _ = try await fresh.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request)
        let output = root.appendingPathComponent("approval-output.txt")
        #expect((try? String(contentsOf: output, encoding: .utf8)) == "approved original effect")
        let events = try store.loadSession(agentID: agentID, sessionID: session.id).events
        #expect(events.filter { $0.runtimeMetadata?.executionPhase == .started && $0.runtimeMetadata?.callEventId == pending.toolCallId }.count == 1)
        #expect(events.filter { $0.toolResult?.callEventId == pending.toolCallId && $0.toolResult?.ok == true }.count == 1)
        #expect(await script.requests.count == 2)
        #expect(await fresh.listPendingToolApprovals().isEmpty)
    }

    @Test(.timeLimit(.minutes(10)))
    func coreSteeringUsesTheCurrentRunAndSettlesItsReceipt() async throws {
        let gate = SessionStepGate()
        let heldScript = SessionStepScript(firstRequestGate: gate)
        let fixture = try await SessionIdentityFixture.make(script: heldScript)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file); Task { await gate.release(); await service.stop() } }
        let initial = AgentSessionPostMessageRequest(userId: "fixture", content: "Original steering task.",
            mode: .ask, clientMessageId: UUID().uuidString)
        let operation = Task { try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: initial) }
        try #require(await gate.waitUntilHeld(during: operation))
        var correction = AgentSessionPostMessageRequest(userId: "fixture", content: "Use the corrected requirement.", clientMessageId: UUID().uuidString)
        correction.deliveryIntent = .steering
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: correction)
        await gate.release()
        _ = try await operation.value
        // A repeated receipt must not create a second model task, including the disposable inbox path.
        let replay = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: correction)
        #expect(replay.replayed == true)
        let requests = await heldScript.requests
        #expect(requests.count == 2)
        #expect(Set(requests.map(\.runId)).count == 1)
        #expect(requests.last?.messages.contains { $0.text == correction.content } == true)
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let inputs = try SessionInputLifecycle.states(in: detail.events)
        let correctionID = try #require(correction.clientMessageId), initialID = try #require(initial.clientMessageId)
        #expect(inputs[correctionID]?.owner == inputs[initialID]?.owner)
        #expect(inputs[correctionID]?.latest.delivery == .delivered)
        #expect(!NativeSessionDelivery.hasLaterUserInput(after: initialID, in: detail))
        #expect(await heldScript.legacyCalls == 0)
    }

    @Test
    func fallbackUsageIsDurablePerRunAndRebuildsWithoutGeneration() async throws {
        let script = SessionStepScript(usage: .init(prompt: 17, completion: 5,
            cachedInputTokens: 3, cacheCreationInputTokens: 2, reasoningTokens: 1))
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let first = AgentSessionPostMessageRequest(userId: "fixture", content: "Read session-target.txt.",
            mode: .ask, clientMessageId: UUID().uuidString)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: first)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Read it again for an independent task.", mode: .ask, clientMessageId: UUID().uuidString))
        let channel = "agent:\(fixture.agentID):session:\(fixture.session.id)"
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let owner = try #require(detail.events.first { $0.runtimeMetadata?.inputMessageId == first.clientMessageId }?.runtimeMetadata)
        let responses = detail.events.filter { $0.runtimeMetadata?.modelResponse != nil }
        #expect(responses.count == 4)
        let records = try responses.compactMap { event -> Protocols.JSONValue? in
            try JSONValueCoder.encode(event.runtimeMetadata).asObject?["usageRequest"]
        }
        #expect(records.count == 4)
        #expect(Set(records.compactMap { $0.asObject?["id"]?.asString }).count == 4)
        #expect(zip(records, responses).allSatisfy { record, event in
            record.asObject?["runId"]?.asString == event.runtimeMetadata?.runId &&
                record.asObject?["userTurnId"]?.asString == event.runtimeMetadata?.userTurnId
        })
        let original = await service.listTokenUsage(channelId: channel)
        #expect(original.items.count == 4)
        #expect(original.totalPromptTokens == 68)
        #expect(original.totalCompletionTokens == 20)
        #expect(original.totalCachedInputTokens == 12)
        #expect(original.totalCacheCreationInputTokens == 8)
        #expect(original.totalReasoningTokens == 4)
        let store = await service.sessionStore
        let journal = URL(fileURLWithPath: try store.sessionFilePath(agentID: fixture.agentID, sessionID: fixture.session.id))
        let before = try Data(contentsOf: journal)
        // A new, empty projection models the durable-response / missing-accounting crash state.
        // It does not claim that this fixture kills a live process.
        try await service.exitPreservingCrashImageForLoopTests()
        let fresh = CoreService(config: await service.getConfig(), persistenceBuilder: InMemoryCorePersistenceBuilder())
        let unavailable = SessionStepScript()
        let model = "openai-api:gpt-5.4-mini"
        await fresh.overrideModelProviderForTests(SessionStepFactory(script: unavailable, allowsModelSteps: false), defaultModel: model)
        await fresh.waitForStartup(dispatchReadyTasks: false)
        let recovered = await fresh.listTokenUsage(channelId: channel)
        #expect(recovered.items.count == 4)
        #expect(recovered.totalTokens == 88)
        let router = CoreRouter(service: fresh)
        let path = "/v1/usage/breakdown?channelId=\(channel)&runId=\(owner.runId)&userTurnId=\(owner.userTurnId)"
        let response = await router.handle(method: "GET", path: path, body: nil)
        #expect(response.status == 200)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oneRun = try decoder.decode(UsageBreakdownResponse.self, from: response.body)
        #expect(oneRun.requestCount == 2)
        #expect(oneRun.providerUsage.total == 44)
        #expect(oneRun.completeRequestCount == 0)
        let unknown = await router.handle(method: "GET", path: "/v1/usage/breakdown?channelId=\(channel)&runId=\(UUID().uuidString)", body: nil)
        #expect(try decoder.decode(UsageBreakdownResponse.self, from: unknown.body).requestCount == 0)
        for _ in 0..<2 {
            let replay = try await fresh.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: first)
            #expect(replay.replayed == true)
        }
        #expect(await fresh.listTokenUsage(channelId: channel).items.count == 4)
        #expect(try Data(contentsOf: journal) == before)
        #expect(await unavailable.requests.isEmpty)
        #expect(await unavailable.legacyCalls == 0)
    }

    @Test(arguments: [false, true])
    func acceptedInputPinsInheritedReasoningBeforeTheFirstRequest(initiallyUnset: Bool) async throws {
        let expected: ReasoningEffort? = initiallyUnset ? nil : .high
        let script = SessionStepScript()
        let fixture = try await SessionIdentityFixture.make(script: script,
            capabilities: ["tools", "reasoning"], reasoningEffort: expected)
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let service = fixture.service
        let store = await service.sessionStore
        let journal = URL(fileURLWithPath: try store.sessionFilePath(agentID: fixture.agentID, sessionID: fixture.session.id))
        let crash = SessionResultCrash(journal: journal, trigger: .acceptancePrefix)
        await service.sessionOrchestrator.updateEventAppendObserver { _, _, _, events in await crash.observe(events) }
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Read session-target.txt.",
            mode: .ask, clientMessageId: UUID().uuidString)
        do { _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request) }
        catch { /* The first complete acceptance record is the crash boundary. */ }
        #expect(await crash.tripped)
        #expect(await crash.failure == nil)
        #expect(await script.requests.isEmpty)
        try await crash.restore()
        let saved = try store.loadSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let raw = try #require(saved.events.first { $0.runtimeMetadata?.runState != nil }?.runtimeMetadata?.runState)
        let checkpoint = try JSONValueCoder.decode(RunStateSnapshot.self, from: raw)
        #expect(checkpoint.requestSettings != nil)
        #expect(checkpoint.requestSettings?.reasoningEffort == expected)
        let root = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: root.appendingPathComponent("agents"))
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools", "reasoning"])]
        let profile = try catalog.getAgentConfig(agentID: fixture.agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: fixture.agentID,
            request: .init(role: profile.role, selectedModel: models[0].id, documents: profile.documents,
                reasoningEffort: .low, automaticModelRouting: false, runtime: profile.runtime), availableModels: models)
        try await service.exitPreservingCrashImageForLoopTests()
        let fresh = CoreService(config: await service.getConfig(), persistenceBuilder: InMemoryCorePersistenceBuilder())
        let resumed = SessionStepScript()
        await fresh.overrideModelProviderForTests(SessionStepFactory(script: resumed), defaultModel: models[0].id)
        await fresh.sessionOrchestrator.updateAvailableModels(models)
        await fresh.waitForStartup(dispatchReadyTasks: false)
        _ = try await fresh.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request)
        let frames = await resumed.requests
        #expect(frames.count == 2)
        #expect(frames.allSatisfy { $0.reasoningEffort == expected })
        let delivered = try await fresh.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        #expect(delivered.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        #expect(delivered.summary.userTurnCount == 1)
        #expect(await resumed.legacyCalls == 0)
    }

    @Test(arguments: [false, true])
    func legacyQueuedInputMigratesBeforeItsCacheIsDiscarded(modeCommand: Bool) async throws {
        let fixture = try await SessionIdentityFixture.make(script: SessionStepScript())
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        await service.holdInboxForLoopTests(fixture.session.id)
        let id = UUID().uuidString
        let content = "Read session-target.txt."
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: modeCommand ? "/ask " + content : content,
            attachments: [.init(name: "note.txt", mimeType: "text/plain", sizeBytes: 3, contentBase64: "YWJj")],
            mode: .ask, clientMessageId: id)
        let store = await service.sessionStore
        let attachments = try store.persistAttachments(agentID: fixture.agentID, sessionID: fixture.session.id, uploads: request.attachments)
        // Actual v1 user/cache records written by the previous queue contract.
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.session.id, events: [
            .init(agentId: fixture.agentID, sessionId: fixture.session.id, type: .message,
                message: .init(id: id, role: .user, segments: [.init(kind: .text, text: request.content)] + attachments.map { .init(kind: .attachment, attachment: $0) },
                    userId: request.userId, supportsA2UI: request.supportsA2UI))
        ])
        try await service.seedLegacyInboxForLoopTests(.init(id: id, agentId: fixture.agentID, sessionId: fixture.session.id, request: request))
        let config = await service.getConfig()
        try await service.exitPreservingCrashImageForLoopTests()
        let migrated = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await migrated.holdUIInboxForTesting()
        await migrated.waitForStartup(dispatchReadyTasks: false)
        let captured = try await migrated.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let queued = try SessionInputLifecycle.states(in: captured.events)[id]
        #expect(queued?.latest.disposition == .queued)
        #expect(queued?.owner == nil)
        #expect(queued?.context.request.content == content)
        #expect(queued?.context.sourceRequest?.content == (modeCommand ? request.content : nil))
        #expect(queued?.context.attachments.map(\.attachment) == attachments)
        #expect(captured.events.filter { $0.message?.id == id }.count == 1)
        #expect(captured.events.first { $0.message?.id == id }?.message?.segments.first?.text == request.content)
        let cache = config.resolvedWorkspaceRootURL().appendingPathComponent("session-messages/inbox.json")
        try await migrated.exitPreservingCrashImageForLoopTests()
        try FileManager.default.removeItem(at: cache)
        let fresh = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let script = SessionStepScript()
        let model = "openai-api:gpt-5.4-mini"
        await fresh.overrideModelProviderForTests(SessionStepFactory(script: script), defaultModel: model)
        await fresh.sessionOrchestrator.updateAvailableModels([.init(id: model, title: "Fixture", capabilities: ["tools"])])
        await fresh.waitForStartup(dispatchReadyTasks: false)
        if let runner = await fresh.sessionMessageRunners[fixture.session.id] { await runner.value }
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.first?.messages.contains { $0.role == .user && $0.text.hasPrefix(content) } == true)
        let delivered = try await fresh.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        #expect(try SessionInputLifecycle.states(in: delivered.events)[id]?.latest.delivery == .delivered)
        #expect(delivered.summary.userTurnCount == 1)
        #expect(delivered.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        if queued != nil {
            let retry = try await fresh.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request)
            #expect(retry.replayed == true)
        }
        #expect(await script.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func canonicalReceiptCannotBeReboundThroughAnotherIngress(ui: Bool) async throws {
        let script = SessionStepScript()
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let id = UUID().uuidString
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Read session-target.txt.", mode: .ask, clientMessageId: id))
        let sender = try await service.createAgentSession(agentID: fixture.agentID, request: .init(title: "Peer sender"))
        let form = #"[{"version":"v0.9.1","createSurface":{"surfaceId":"form","catalogId":"urn:sloppy:a2ui:catalog:v1"}},{"version":"v0.9.1","updateComponents":{"surfaceId":"form","components":[{"id":"root","component":"Column","children":["go"]},{"id":"go","component":"Button","label":"Continue","action":"submit"}]}}]"#
        _ = try await service.renderAgentUI(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(messages: form, expectedRevision: 0, fallbackText: "Continue"))
        let store = await service.sessionStore
        let journal = URL(fileURLWithPath: try store.sessionFilePath(agentID: fixture.agentID, sessionID: fixture.session.id))
        let before = try Data(contentsOf: journal)
        var accepted = false
        var rejected = false
        do {
            if ui {
                _ = try await service.submitAgentUIAction(agentID: fixture.agentID, sessionID: fixture.session.id,
                    surfaceID: "form", submission: .init(actionId: id, revision: 1, componentId: "go", values: [:]), userID: "fixture")
            } else {
                _ = try await service.sendPeerSessionMessage(senderAgentID: fixture.agentID, senderSessionID: sender.id,
                    targetAgentID: fixture.agentID, targetSessionID: fixture.session.id, content: "A different peer request", messageID: id)
            }
            accepted = true
        } catch CoreService.AgentUIError.actionConflict { rejected = ui }
        catch PeerSessionMessageError.conflict { rejected = !ui }
        #expect(!accepted)
        #expect(rejected)
        if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        #expect(try Data(contentsOf: journal) == before)
        #expect(try await service.listAgentUISurfaces(agentID: fixture.agentID, sessionID: fixture.session.id).first?.submittedActionId == nil)
        #expect(await script.requests.count == 2)
    }

    @Test
    func unpreservedCorruptCacheCannotBlockOrOverwriteCanonicalReceipts() async throws {
        let fixture = try await SessionIdentityFixture.make(script: SessionStepScript())
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        await service.holdInboxForLoopTests(fixture.session.id)
        let id = UUID().uuidString
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Keep this canonical request.", mode: .ask, clientMessageId: id))
        let entry = try #require(try await service.inboxEntryForLoopTests(id))
        let root = await service.workspaceRootURL
        let file = root.appendingPathComponent("session-messages/inbox.json")
        let original = Data("Corrupted cache with potentially recoverable legacy bytes".utf8)
        try original.write(to: file, options: .atomic)
        var recovered: SessionMessageInboxFileStore?
        var failure: Error?
        do {
            recovered = try SessionMessageInboxFileStore(root: root, recovering: [entry], preserveCorruptCache: { _, _ in
                throw CocoaError(.fileWriteNoPermission)
            })
        } catch { failure = error }
        #expect(failure == nil)
        guard let recovered else { return }
        #expect(recovered.entries == [entry])
        #expect(recovered.quarantinedCache == nil)
        #expect(recovered.cacheWriteError != nil)
        try recovered.update(id: id, state: .delivered)
        #expect(recovered.entries.first?.state == .delivered)
        #expect(try Data(contentsOf: file) == original)
        var legacy = entry
        legacy.id = UUID().uuidString
        legacy.request.clientMessageId = legacy.id
        var legacyRejected = false
        do { _ = try recovered.enqueue(legacy) } catch { legacyRejected = true }
        #expect(legacyRejected)
        #expect(recovered.entries.count == 1)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: [false, true])
    func uiReceiptOwnsItsAcceptedSurfaceWithoutTheCache(cacheUnavailable: Bool) async throws {
        let script = SessionStepScript()
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        await service.holdInboxForLoopTests(fixture.session.id)
        let form = #"[{"version":"v0.9.1","createSurface":{"surfaceId":"form","catalogId":"urn:sloppy:a2ui:catalog:v1"}},{"version":"v0.9.1","updateComponents":{"surfaceId":"form","components":[{"id":"root","component":"Column","children":["name","go"]},{"id":"name","component":"TextField","label":"Name","binding":"/name","required":true},{"id":"go","component":"Button","label":"Continue","action":"submit"}]}}]"#
        _ = try await service.renderAgentUI(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(messages: form, expectedRevision: 0, fallbackText: "Name"))
        let action = AgentUISubmission(actionId: UUID().uuidString, revision: 1, componentId: "go", values: ["/name": .string("Ada")])
        let root = await service.workspaceRootURL.standardizedFileURL
        let cache = root.appendingPathComponent("session-messages/inbox.json")
        if cacheUnavailable {
            let directory = cache.deletingLastPathComponent().standardizedFileURL
            let preserved = root.appendingPathComponent("preserved-ui-inbox-" + UUID().uuidString).standardizedFileURL
            try #require(directory.path.hasPrefix(root.path + "/") && preserved.path.hasPrefix(root.path + "/"))
            try FileManager.default.moveItem(at: directory, to: preserved)
            try Data("Blocked UI queue cache directory".utf8).write(to: directory, options: .atomic)
        }
        var failure: Error?
        do {
            let receipt = try await service.submitAgentUIAction(agentID: fixture.agentID, sessionID: fixture.session.id,
                surfaceID: "form", submission: action, userID: "fixture")
            #expect(receipt.status == "accepted")
        } catch { failure = error }
        #expect(failure == nil)
        guard failure == nil else { return }
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let index = try #require(detail.events.firstIndex { $0.message?.id == action.actionId })
        #expect(!detail.events[..<index].contains { $0.id == "ui-accepted-" + action.actionId })
        let context = try #require(detail.events[index].inputTransitions?.first?.context)
        #expect(context.uiSubmission == action)
        #expect(context.uiSnapshot?.submittedActionId == action.actionId)
        #expect(detail.events[index].message?.segments.first?.text == "Continue\nName: Ada")
        // Crash at the first durable receipt, before any derived surface update or delivery.
        let store = await service.sessionStore
        let journal = URL(fileURLWithPath: try store.sessionFilePath(agentID: fixture.agentID, sessionID: fixture.session.id))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = try Data(contentsOf: journal).split(separator: 10)
        let last = try #require(lines.firstIndex { (try? decoder.decode(AgentSessionEvent.self, from: Data($0)))?.id == detail.events[index].id })
        var prefix = Data()
        for line in lines[...last] { prefix.append(contentsOf: line); prefix.append(10) }
        try prefix.write(to: journal, options: .atomic)
        if !cacheUnavailable { try FileManager.default.removeItem(at: cache) }
        try await service.exitPreservingCrashImageForLoopTests()
        let fresh = CoreService(config: await service.getConfig(), persistenceBuilder: InMemoryCorePersistenceBuilder())
        await fresh.holdUIInboxForTesting()
        let resumed = SessionStepScript()
        let model = "openai-api:gpt-5.4-mini"
        await fresh.overrideModelProviderForTests(SessionStepFactory(script: resumed), defaultModel: model)
        await fresh.sessionOrchestrator.updateAvailableModels([.init(id: model, title: "Fixture", capabilities: ["tools"])])
        await fresh.waitForStartup(dispatchReadyTasks: false)
        if let runner = await fresh.sessionMessageRunners[fixture.session.id] { await runner.value }
        #expect(await resumed.requests.isEmpty)
        // Dispatch of default Auto is a separate consumer migration. Exercise the real
        // journal projection here with a typed admission while provider dispatch stays held.
        let recoveredStore = await fresh.sessionStore
        let run = UUID().uuidString
        let snapshot = RunStateSnapshot(runID: run, userTurnID: action.actionId,
            loopConfig: .init(engine: .unified), model: model)
        let fingerprint = try #require(detail.events[index].inputTransitions?.first?.fingerprint)
        _ = try recoveredStore.appendEvents(agentID: fixture.agentID, sessionID: fixture.session.id, events: [
            .init(version: 3, agentId: fixture.agentID, sessionId: fixture.session.id, type: .runStatus,
                runtimeMetadata: .init(runId: run, userTurnId: action.actionId,
                    runState: try JSONValueCoder.encode(snapshot), inputMessageId: action.actionId, requestFingerprint: fingerprint),
                inputTransitions: [.init(messageId: action.actionId, fingerprint: fingerprint,
                    disposition: .admitted, owner: .init(runId: run, userTurnId: action.actionId, generation: 0))])
        ])
        let projection = try SessionProjection.load(store: recoveredStore, agentID: fixture.agentID, sessionID: fixture.session.id)
        #expect(try projection.modelMessages().contains { $0.role == .user && $0.text == context.request.content })
        let duplicate = try await fresh.submitAgentUIAction(agentID: fixture.agentID, sessionID: fixture.session.id,
            surfaceID: "form", submission: action, userID: "fixture")
        #expect(duplicate.status == "accepted")
        #expect(try await fresh.listAgentUISurfaces(agentID: fixture.agentID, sessionID: fixture.session.id).first?.submittedActionId == action.actionId)
        #expect(try await fresh.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id).events.filter { $0.message?.id == action.actionId }.count == 1)
        #expect(await resumed.requests.isEmpty)
        #expect(await resumed.legacyCalls == 0)
    }

    @Test(arguments: ["queued", "cancelled", "failed"])
    func forkCannotResurrectNeverAdmittedInput(disposition: String) async throws {
        let script = SessionStepScript()
        let fixture = try await SessionIdentityFixture.make(script: script)
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let service = fixture.service
        await service.holdInboxForLoopTests(fixture.session.id)
        let store = await service.sessionStore
        let legacyText = "Original untagged user history remains available."
        let legacyID = UUID().uuidString
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.session.id, events: [
            .init(agentId: fixture.agentID, sessionId: fixture.session.id, type: .message,
                message: .init(id: legacyID, role: .user, segments: [.init(kind: .text, text: legacyText)], userId: "fixture"))
        ])
        let id = UUID().uuidString
        let text = "This never-admitted input must not become historical model context."
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: text, mode: .ask, clientMessageId: id))
        if disposition != "queued" {
            let queued = try #require(try SessionInputLifecycle.states(in: store.loadSession(
                agentID: fixture.agentID, sessionID: fixture.session.id).events)[id])
            _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.session.id, events: [
                .init(version: 3, agentId: fixture.agentID, sessionId: fixture.session.id, type: .runStatus,
                    inputTransitions: [.init(messageId: id, fingerprint: queued.latest.fingerprint,
                        disposition: disposition == "cancelled" ? .cancelled : .failed, delivery: .delivered)])
            ])
        }
        let fork = try await service.createAgentSession(agentID: fixture.agentID,
            request: .init(title: "Eligible fork", forkFromSessionId: fixture.session.id, forkThroughMessageId: id))
        let copied = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fork.id)
        #expect(!copied.events.contains { $0.message?.segments.contains { $0.text == text } == true })
        #expect(copied.events.contains { $0.message?.segments.contains { $0.text == legacyText } == true })
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fork.id,
            request: .init(userId: "fixture", content: "Read session-target.txt in this independent fork.", mode: .ask))
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { !$0.messages.contains { $0.text.contains(text) } })
        #expect(requests.first?.messages.contains { $0.text.contains(legacyText) } == true)
        let original = try store.loadSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        #expect(original.events.filter { $0.message?.id == id }.count == 1)
        #expect(try SessionInputLifecycle.states(in: original.events)[id]?.wasAdmitted == false)
    }

    @Test
    func cancelledInboxPreparationPreservesItsTypedDisposition() async throws {
        let modelGate = SessionStepGate()
        let preparation = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: modelGate)
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file); Task { await modelGate.release(); await preparation.release() } }
        let active = Task { try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Original input before queued preparation", mode: .ask, clientMessageId: UUID().uuidString)) }
        try #require(await modelGate.waitUntilHeld(during: active))
        let id = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Cancel this queued preparation",
            mode: .ask, clientMessageId: id)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request)
        await service.setMessagePreparationForLoopTests { await preparation.hold() }
        await modelGate.release()
        _ = try await active.value
        let delivery = Task<Void, Error> {
            if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        }
        try #require(await preparation.waitUntilHeld(during: delivery))
        let operation = try #require(await service.activeMessageOperationForLoopTests(agentID: fixture.agentID, sessionID: fixture.session.id))
        operation.cancel()
        await preparation.release()
        try await delivery.value
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let state = try #require(try SessionInputLifecycle.states(in: detail.events)[id])
        #expect(state.latest.disposition == .cancelled)
        #expect(state.latest.delivery == .delivered)
        #expect(state.owner == nil)
        #expect(detail.events.last { $0.inputTransitions?.contains { $0.messageId == id } ?? false }?.runStatus?.executionOutcome?.state == .cancelled)
        #expect(await script.requests.count == 2)
        #expect(!(await script.requests.contains { $0.userTurnId == id }))
        let replay = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request)
        #expect(replay.replayed == true)
        #expect(await script.requests.count == 2)
    }

    @Test(arguments: [false, true])
    func failedNeverAdmittedQueuedInputCannotResume(corruptAttachment: Bool) async throws {
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file); Task { await gate.release() } }
        let active = Task { try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Original active input", mode: .ask, clientMessageId: UUID().uuidString)) }
        try #require(await gate.waitUntilHeld(during: active))
        let id = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "FAILED_NEVER_ADMITTED_INPUT",
            attachments: [.init(name: "queued.txt", mimeType: "text/plain", sizeBytes: 3, contentBase64: "YWJj")],
            mode: .ask, clientMessageId: id)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request)
        let before = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let queued = try #require(try SessionInputLifecycle.states(in: before.events)[id])
        let attachment = try #require(queued.context.attachments.first?.attachment)
        let store = await service.sessionStore
        let file = try #require(try store.resolveAttachmentFileURL(agentID: fixture.agentID, attachment: attachment))
        if corruptAttachment { try Data("xyz".utf8).write(to: file, options: .atomic) }
        else { try FileManager.default.removeItem(at: file) }
        await gate.release()
        _ = try await active.value
        if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        let failed = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let state = try #require(try SessionInputLifecycle.states(in: failed.events)[id])
        #expect(state.latest.disposition == .failed)
        #expect(state.latest.delivery == .delivered)
        #expect(state.owner == nil)
        #expect(state.context == queued.context)
        #expect(try await service.inboxEntryForLoopTests(id)?.state == .failed)
        var replay: AgentSessionMessageResponse?
        var replayFailure: Error?
        do { replay = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request) }
        catch { replayFailure = error }
        #expect(replayFailure == nil)
        #expect(replay?.replayed == true)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Independent valid task", mode: .ask, clientMessageId: UUID().uuidString))
        let requests = await script.requests
        #expect(!requests.contains { $0.userTurnId == id })
        #expect(!requests.contains { $0.messages.contains { $0.text.contains(request.content) } })
        #expect(requests.count == 4)
    }

    @Test
    func firstInterruptRecordCancelsQueuedInputWithoutTheInboxCache() async throws {
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file); Task { await gate.release() } }
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Original task before interrupt",
            mode: .ask, clientMessageId: UUID().uuidString)
        let active = Task { try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request) }
        try #require(await gate.waitUntilHeld(during: active))
        let queuedID = UUID().uuidString
        let queuedRequest = AgentSessionPostMessageRequest(userId: "fixture", content: "CANCELLED_NEVER_ADMITTED_TASK",
            mode: .ask, clientMessageId: queuedID)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: queuedRequest)
        let control = try await service.controlAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(action: .interrupt, requestedBy: "fixture", interruptPendingInput: true))
        await gate.release()
        _ = try? await active.value
        let first = try #require(control.appendedEvents.first { $0.type == .runControl })
        let cancellation = first.inputTransitions?.first { $0.messageId == queuedID }
        #expect(cancellation?.disposition == .cancelled)
        #expect(cancellation?.delivery == .delivered)
        #expect(cancellation?.owner == nil)
        #expect(cancellation?.context == nil)
        let store = await service.sessionStore
        let file = URL(fileURLWithPath: try store.sessionFilePath(agentID: fixture.agentID, sessionID: fixture.session.id))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = try Data(contentsOf: file).split(separator: 10)
        let boundary = try #require(lines.firstIndex { (try? decoder.decode(AgentSessionEvent.self, from: Data($0)))?.id == first.id })
        var prefix = Data()
        for line in lines[...boundary] { prefix.append(contentsOf: line); prefix.append(10) }
        try prefix.write(to: file, options: .atomic)
        let workspace = await service.workspaceRootURL
        let cache = workspace.appendingPathComponent("session-messages/inbox.json")
        if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
        try await service.exitPreservingCrashImageForLoopTests()
        let fresh = CoreService(config: await service.getConfig(), persistenceBuilder: InMemoryCorePersistenceBuilder())
        await fresh.waitForStartup(dispatchReadyTasks: false)
        let recoveredScript = SessionStepScript(initialIndex: 1)
        let model = "openai-api:gpt-5.4-mini"
        await fresh.overrideModelProviderForTests(SessionStepFactory(script: recoveredScript), defaultModel: model)
        await fresh.sessionOrchestrator.updateAvailableModels([.init(id: model, title: "Fixture", capabilities: ["tools"])])
        var restoredFailure: Error?
        do {
            let restored = try await fresh.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request)
            #expect(restored.appendedEvents.contains { $0.runStatus?.stage == .interrupted })
        } catch { restoredFailure = error }
        #expect(restoredFailure == nil)
        let retry = try await fresh.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: queuedRequest)
        #expect(retry.replayed == true)
        #expect(try await fresh.inboxEntryForLoopTests(queuedID) == nil)
        _ = try await fresh.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Independent later task", mode: .ask, clientMessageId: UUID().uuidString))
        if let runner = await fresh.sessionMessageRunners[fixture.session.id] { await runner.value }
        let recoveredRequests = await recoveredScript.requests
        #expect(recoveredRequests.count == 1)
        #expect(!recoveredRequests.contains { $0.userTurnId == queuedID })
        #expect(!recoveredRequests.contains { $0.messages.contains { $0.text.contains(queuedRequest.content) } })
    }

    @Test(arguments: ["Explain the saved evidence.", "/build Explain the saved evidence.", "/debug Explain the saved evidence.", "/auto Explain the saved evidence."])
    func unifiedPeerDeliveryPinsExecutionNormalizationAndOriginalSubmission(content: String) async throws {
        let script = SessionStepScript(initialIndex: 1)
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let sender = try await service.createAgentSession(agentID: fixture.agentID, request: .init(title: "Peer sender"))
        try await service.rememberDelegatedScopeForLoopTests(sessionID: fixture.session.id)
        await service.holdInboxForLoopTests(fixture.session.id)
        let id = UUID().uuidString
        _ = try await service.sendPeerSessionMessage(senderAgentID: fixture.agentID, senderSessionID: sender.id,
            targetAgentID: fixture.agentID, targetSessionID: fixture.session.id, content: content, messageID: id)
        let queued = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let state = try #require(try SessionInputLifecycle.states(in: queued.events)[id])
        #expect(state.context.request.mode == .ask)
        #expect(state.context.request.content == "Explain the saved evidence.")
        let rawContext = try JSONValueCoder.encode(state.context)
        #expect(rawContext.asObject?["sourceRequest"]?.asObject?["content"]?.asString == content)
        await service.releaseInboxForLoopTests(agentID: fixture.agentID, sessionID: fixture.session.id)
        if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        #expect(try await service.inboxEntryForLoopTests(id)?.state == .delivered)
        #expect(await script.requests.count == 1)
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let delivered = try #require(try SessionInputLifecycle.states(in: detail.events)[id])
        #expect(delivered.latest.delivery == .delivered)
        #expect(delivered.owner?.userTurnId == id)
        let repeated = try await service.sendPeerSessionMessage(senderAgentID: fixture.agentID, senderSessionID: sender.id,
            targetAgentID: fixture.agentID, targetSessionID: fixture.session.id, content: content, messageID: id)
        #expect(repeated.asObject?["state"]?.asString == "delivered")
        #expect(await script.requests.count == 1)
    }

    @Test
    func queuedInputKeepsItsCanonicalContextThroughAdmissionAndDelivery() async throws {
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file); Task { await gate.release() } }
        let initial = Task {
            try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(userId: "fixture", content: "Original active task", mode: .ask, clientMessageId: UUID().uuidString))
        }
        let started = await gate.waitUntilHeld(during: initial)
        if !started { await gate.release(); _ = try await initial.value }
        try #require(started)
        let id = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Queued task with complete original payload",
            attachments: [.init(name: "absent.txt", mimeType: "text/plain", sizeBytes: 0),
                .init(name: "empty.txt", mimeType: "text/plain", sizeBytes: 0, contentBase64: ""),
                .init(name: "data.txt", mimeType: "text/plain", sizeBytes: 3, contentBase64: "YWJj\n")],
            reasoningEffort: .medium, selectedModel: "openai-api:gpt-5.4-mini", mode: .ask,
            clientMessageId: id, supportsA2UI: false)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id, request: request)
        let queued = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let queuedState = try SessionInputLifecycle.states(in: queued.events)[id]
        #expect(queuedState?.latest.disposition == .queued)
        #expect(queuedState?.latest.delivery == .pending)
        #expect(queuedState?.owner == nil)
        #expect(queuedState?.context.request.attachments.allSatisfy { $0.contentBase64 == nil } == true)
        #expect(queuedState?.context.attachments.map(\.hadInlineData) == [false, true, true])
        #expect(queuedState?.context.attachments.map(\.sha256) == [nil,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"])
        #expect(queuedState?.context.request.reasoningEffort == request.reasoningEffort)
        #expect(queuedState?.context.request.selectedModel == request.selectedModel)
        #expect(queuedState?.latest.fingerprint.hasPrefix("v2:") == true)
        #expect(queued.events.contains { $0.message?.id == id && $0.version == 3 && $0.inputTransitions?.first?.context != nil })
        await gate.release()
        _ = try await initial.value
        if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        let delivered = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        let deliveredState = try SessionInputLifecycle.states(in: delivered.events)[id]
        #expect(deliveredState?.latest.disposition == .admitted)
        #expect(deliveredState?.latest.delivery == .delivered)
        #expect(deliveredState?.owner?.userTurnId == id)
        #expect(deliveredState?.context == queuedState?.context)
        let requests = await script.requests
        let queuedRequests = requests.filter { $0.userTurnId == id }
        #expect(queuedRequests.count == 2)
        #expect(queuedRequests.allSatisfy { $0.messages.filter { $0.text.contains(request.content) }.count == 1 })
        #expect(try await service.inboxEntryForLoopTests(id)?.state == .delivered)
        #expect(await script.legacyCalls == 0)
    }

    @Test(arguments: ["v2", "partial", "v3"])
    func lifecycleJournalWritesRequireBothProfilesAtVersionThree(protection: String) async throws {
        let script = SessionStepScript()
        let fixture = try await SessionIdentityFixture.make(script: script)
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let directory = await fixture.service.workspaceRootURL.appendingPathComponent("agents").appendingPathComponent(fixture.agentID)
        for (index, name) in ["agent.json", "config.json"].enumerated() {
            let file = directory.appendingPathComponent(name)
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var runtime = try #require(object["runtime"] as? [String: Any])
            runtime["type"] = protection == "v3" || (protection == "partial" && index == 0) ? "native_v3" : "native_v2"
            runtime["storageRuntimeType"] = "native"
            object["runtime"] = runtime
            try JSONSerialization.data(withJSONObject: object).write(to: file, options: .atomic)
        }
        let store = await fixture.service.sessionStore
        let file = URL(fileURLWithPath: try store.sessionFilePath(agentID: fixture.agentID, sessionID: fixture.session.id))
        let before = try Data(contentsOf: file)
        let event = AgentSessionEvent(version: 3, agentId: fixture.agentID, sessionId: fixture.session.id, type: .runStatus,
            runStatus: .init(stage: .thinking, label: "Reader compatibility fixture"))
        var failure: Error?
        do {
            _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.session.id, events: [event])
        } catch { failure = error }
        if protection == "v3" {
            #expect(failure == nil)
            #expect(try store.loadSession(agentID: fixture.agentID, sessionID: fixture.session.id).events.contains { $0.id == event.id })
        } else {
            #expect(failure != nil)
            #expect(try Data(contentsOf: file) == before)
        }
        #expect(await script.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func cancellationDuringPreparationCannotStartAnAdmittedPost(callerCancellation: Bool) async throws {
        let gate = SessionStepGate()
        let script = SessionStepScript()
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file); Task { await gate.release() } }
        await service.setMessagePreparationForLoopTests { await gate.hold() }
        let messageID = UUID().uuidString
        let post = Task {
            try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(userId: "fixture", content: "This preparation was cancelled before runtime admission.",
                    mode: .ask, clientMessageId: messageID))
        }
        let held = await gate.waitUntilHeld(during: post)
        if !held { await gate.release(); _ = try await post.value }
        try #require(held)
        #expect(await script.requests.isEmpty)
        if callerCancellation { post.cancel() }
        else {
            _ = try await service.controlAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(action: .interrupt, requestedBy: "fixture", interruptPendingInput: true))
        }
        await gate.release()
        do { _ = try await post.value } catch { /* Cancellation may reject an input before canonical admission. */ }
        #expect(await script.requests.isEmpty)
        #expect(await script.legacyCalls == 0)
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        #expect(!detail.events.contains { $0.runtimeMetadata?.executionPhase == .started })
        #expect(!detail.events.contains { $0.runStatus?.stage == .done })
    }

    @Test
    func partialInterruptTreeFailureCannotReleaseTheStoppedParentsQueue() async throws {
        let modelGate = SessionStepGate()
        let controlGate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: modelGate)
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer {
            try? FileManager.default.removeItem(at: fixture.file)
            Task { await modelGate.release(); await controlGate.release() }
        }
        let orchestrator = await service.sessionOrchestrator
        let child = try await orchestrator.createSession(agentID: fixture.agentID,
            request: .init(title: "Control failure child", parentSessionId: fixture.session.id))
        let store = await service.sessionStore
        let childFile = URL(fileURLWithPath: try store.sessionFilePath(agentID: fixture.agentID, sessionID: child.id))
        let backup = childFile.deletingLastPathComponent().appendingPathComponent("fault-" + UUID().uuidString.prefix(8))
        let messageID = UUID().uuidString
        let queuedID = UUID().uuidString
        let initial = Task {
            try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(userId: "fixture", content: "Interrupt this active parent.", mode: .ask, clientMessageId: messageID))
        }
        let held = await modelGate.waitUntilHeld(during: initial)
        if !held { await modelGate.release(); _ = try await initial.value }
        try #require(held)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "Cancel this parent's queued task even if the child fails.",
                mode: .ask, clientMessageId: queuedID))
        await service.setControlAdmissionForLoopTests { await controlGate.hold() }
        let control = Task {
            try await service.controlAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(action: .interruptTree, requestedBy: "fixture", interruptPendingInput: true))
        }
        let controlHeld = await controlGate.waitUntilHeld(during: control)
        if !controlHeld { await modelGate.release(); _ = try? await initial.value; _ = try await control.value }
        try #require(controlHeld)
        try FileManager.default.moveItem(at: childFile, to: backup)
        try FileManager.default.createDirectory(at: childFile, withIntermediateDirectories: false)
        defer {
            if (try? FileManager.default.contentsOfDirectory(atPath: childFile.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: childFile)
                try? FileManager.default.moveItem(at: backup, to: childFile)
            }
        }
        await controlGate.release()
        var failed = false
        do { _ = try await control.value } catch { failed = true }
        #expect(failed)
        await modelGate.release()
        _ = try? await initial.value
        if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        #expect(detail.events.contains { $0.runControl?.action == .interruptTree })
        #expect(!(await script.requests).contains { $0.userTurnId == queuedID })
        #expect(try await service.inboxEntryForLoopTests(queuedID)?.state == .failed)
    }

    @Test(arguments: [false, true])
    func interruptControlBlocksQueuedWorkUntilItsScopeSettles(laterInput: Bool) async throws {
        let modelGate = SessionStepGate()
        let controlGate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: modelGate)
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer {
            try? FileManager.default.removeItem(at: fixture.file)
            Task { await modelGate.release(); await controlGate.release() }
        }
        let initialID = UUID().uuidString
        let queuedID = UUID().uuidString
        let laterID = UUID().uuidString
        let initial = Task {
            try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(userId: "fixture", content: "Read the file for the original task.", mode: .ask,
                    clientMessageId: initialID))
        }
        let started = await modelGate.waitUntilHeld(during: initial)
        if !started { await modelGate.release(); _ = try await initial.value }
        try #require(started)
        _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: "This queued task must be cancelled by the pending interrupt.",
                mode: .ask, clientMessageId: queuedID))
        await service.setControlAdmissionForLoopTests { await controlGate.hold() }
        let control = Task {
            try await service.controlAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(action: .interrupt, requestedBy: "fixture", interruptPendingInput: true))
        }
        let held = await controlGate.waitUntilHeld(during: control)
        if !held { await modelGate.release(); _ = try await initial.value; _ = try await control.value }
        try #require(held)
        await modelGate.release()
        _ = try await initial.value
        if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        #expect(await script.requests.count == 2)
        if laterInput {
            _ = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(userId: "fixture", content: "This later task belongs after the control boundary.",
                    mode: .ask, clientMessageId: laterID))
            #expect(await script.requests.count == 2)
            #expect(await service.pendingSessionMessageIDs(agentID: fixture.agentID, sessionID: fixture.session.id).contains(laterID))
        }
        await controlGate.release()
        _ = try await control.value
        if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        let requests = await script.requests
        #expect(requests.count == (laterInput ? 4 : 2))
        #expect(!requests.contains { $0.userTurnId == queuedID })
        #expect(try await service.inboxEntryForLoopTests(queuedID)?.state == .failed)
        if laterInput {
            #expect(requests.filter { $0.userTurnId == laterID }.count == 2)
            #expect(try await service.inboxEntryForLoopTests(laterID)?.state == .delivered)
        }
        #expect(await script.legacyCalls == 0)
    }


    @Test(arguments: [SessionRecoveryWindow.acceptance, .acceptancePrefix, .prePersistedAcceptancePrefix, .prePersistedAcceptanceCheckpoint, .prePersistedResult, .settled, .settledWithoutStepProvider, .completionWithoutStepProvider, .completionResultWithoutStepProvider, .completionFinalizingWithoutStepProvider, .completionWithDurableInterrupt, .completionWithLegacyInterrupt])
    fileprivate func acceptedInputRecoversOtherDurableBoundaries(window: SessionRecoveryWindow) async throws {
        let withCheckpoint = window == .prePersistedAcceptanceCheckpoint
        let isPrefix = window == .acceptancePrefix || window == .prePersistedAcceptancePrefix || withCheckpoint
        let isAcceptance = window == .acceptance || isPrefix
        let isPrePersisted = window == .prePersistedResult || window == .prePersistedAcceptancePrefix || withCheckpoint
        let durableInterrupt = window == .completionWithDurableInterrupt
        let legacyInterrupt = window == .completionWithLegacyInterrupt
        let interrupted = durableInterrupt || legacyInterrupt
        let finalizingCheckpoint = window == .completionFinalizingWithoutStepProvider
        let completionTail = window == .completionResultWithoutStepProvider || finalizingCheckpoint || interrupted
        let usesCompletion = window == .completionWithoutStepProvider || completionTail
        let isSettled = window == .settled || window == .settledWithoutStepProvider || window == .completionWithoutStepProvider
        let completedWork = isSettled || completionTail
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let script = SessionStepScript(finishWithCompletion: usesCompletion)
        await service.overrideModelProviderForTests(SessionStepFactory(script: script), defaultModel: models[0].id)
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let agentID = "native-resume-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native resume fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native resume fixture"))
        let store = await service.sessionStore
        let journalURL = URL(fileURLWithPath: try store.sessionFilePath(agentID: agentID, sessionID: session.id))
        let crash = SessionResultCrash(journal: journalURL, trigger: finalizingCheckpoint ? .finalizing :
            (completionTail ? .completionResult :
                (isPrefix ? .acceptancePrefix : (isAcceptance ? .acceptance : (isSettled ? .settled : .result)))))
        await orchestrator.updateEventAppendObserver { _, _, _, events in await crash.observe(events) }
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        let originalContent = "durable original contents " + String(repeating: "full result ", count: 80)
        try originalContent.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let messageID = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Read session-target.txt.",
            mode: .ask, clientMessageId: messageID)
        if isPrePersisted {
            _ = try await service.persistSessionInboxMessage(.init(id: messageID, agentId: agentID,
                sessionId: session.id, request: request, origin: nil))
        }
        do { _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: request, userMessageAlreadyPersisted: isPrePersisted) }
        catch { /* A subsequent canonical append fails at the selected durable boundary. */ }
        try await crash.restore()
        #expect(await crash.tripped)
        let faultSetupFailure = await crash.failure
        #expect(faultSetupFailure == nil)
        #expect(await script.requests.count == (isAcceptance ? 0 : (completedWork ? 2 : 1)))
        let recoveredStore = AgentSessionFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let faultDetail = try recoveredStore.loadSession(agentID: agentID, sessionID: session.id)
        let savedState = faultDetail.events.last(where: { $0.runtimeMetadata?.runState != nil })?.runtimeMetadata
        #expect(savedState != nil)
        if completionTail, let raw = savedState?.runState {
            #expect(try JSONValueCoder.decode(RunStateSnapshot.self, from: raw).phase != .settled)
        }
        let stateMetadata = try #require(savedState ?? faultDetail.events.first(where: {
            $0.runtimeMetadata?.requestFingerprint != nil
        })?.runtimeMetadata)
        #expect(faultDetail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == (isAcceptance ? 0 : (usesCompletion ? 2 : 1)))
        try "changed contents must not replace the settled result".write(to: file, atomically: true, encoding: .utf8)

        let checkpointContext = "Retain this original standalone scoped context through compaction."
        if withCheckpoint {
            let instruction = AgentRunInstruction(kind: .turnContext, text: checkpointContext)
            let legacyContext = AgentSessionEvent(id: instruction.id, version: 2, agentId: agentID,
                sessionId: session.id, type: .runStatus,
                runtimeMetadata: .init(runId: stateMetadata.runId, userTurnId: stateMetadata.userTurnId,
                    generation: stateMetadata.generation, instruction: instruction))
            _ = try recoveredStore.appendEvents(agentID: agentID, sessionID: session.id, events: [legacyContext])
            let checkpoint = SessionProjectionCheckpoint(coveredCursor: UInt64(try Data(contentsOf: journalURL).count),
                coveredThroughEventId: legacyContext.id, summary: "Earlier presentation summarized.", retainedEventIds: [])
            _ = try recoveredStore.appendEvents(agentID: agentID, sessionID: session.id, events: [
                .init(version: 2, agentId: agentID, sessionId: session.id, type: .memoryCheckpoint,
                    runtimeMetadata: .init(runId: stateMetadata.runId, userTurnId: stateMetadata.userTurnId,
                        generation: stateMetadata.generation, checkpoint: checkpoint))
            ])
        }
        if interrupted {
            let controls: [AgentSessionEvent]
            if legacyInterrupt {
                controls = [
                    .init(agentId: agentID, sessionId: session.id, type: .runControl,
                        runControl: .init(action: .interrupt, requestedBy: "fixture", reason: "Cancel accepted input")),
                    .init(agentId: agentID, sessionId: session.id, type: .runStatus,
                        runStatus: .init(stage: .interrupted, label: "Interrupted"))
                ]
                _ = try recoveredStore.appendEvents(agentID: agentID, sessionID: session.id, events: controls)
            } else {
                let cancellation = try await service.controlAgentSession(agentID: agentID, sessionID: session.id,
                    request: .init(action: .interrupt, requestedBy: "fixture", reason: "Cancel accepted input", interruptPendingInput: true))
                controls = cancellation.appendedEvents
                let stopped = controls.first { $0.type == .runControl }?.runtimeMetadata
                #expect(stopped?.runId == stateMetadata.runId)
                #expect(stopped?.userTurnId == stateMetadata.userTurnId)
                #expect(stopped?.generation == stateMetadata.generation + 1)
                #expect(stopped?.runState != nil)
                if let raw = stopped?.runState {
                    #expect(try JSONValueCoder.decode(RunStateSnapshot.self, from: raw).phase == .stopping)
                }
            }
            #expect(controls.contains { $0.runControl?.action == .interrupt })
        }
        try await service.exitPreservingCrashImageForLoopTests()
        let resumedService = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await resumedService.waitForStartup(dispatchReadyTasks: false)
        let resumedScript = SessionStepScript(initialIndex: isAcceptance ? 0 : 1)
        await resumedService.overrideModelProviderForTests(SessionStepFactory(script: resumedScript, allowsModelSteps: window != .settledWithoutStepProvider && !usesCompletion), defaultModel: models[0].id)
        let resumedOrchestrator = await resumedService.sessionOrchestrator
        await resumedOrchestrator.updateAvailableModels(models)
        var response: AgentSessionMessageResponse?
        var failure: Error?
        do { response = try await resumedService.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request) }
        catch { failure = error }
        #expect(failure == nil)
        if interrupted {
            #expect(response?.appendedEvents.contains { $0.runStatus?.stage == .interrupted } == true)
            #expect(response?.appendedEvents.contains { $0.runStatus?.stage == .done } == false)
            #expect(response?.appendedEvents.contains { $0.message?.segments.first?.text == "Read result reported." } == false)
        } else {
            #expect(response?.appendedEvents.contains {
                $0.message?.role == .assistant && $0.message?.segments.first?.text == "Read result reported."
            } == true)
        }
        let resumedRequests = await resumedScript.requests
        #expect(resumedRequests.count == (completedWork ? 0 : (isAcceptance ? 2 : 1)))
        if !completedWork {
            if isPrefix {
                var context = await crash.acceptedContext
                if withCheckpoint { context.append(checkpointContext) }
                #expect(!context.isEmpty)
                for text in context {
                    #expect(resumedRequests.first?.messages.filter { $0.text == text }.count == 1)
                }
            }
            #expect(resumedRequests.first?.runId == stateMetadata.runId)
            #expect(resumedRequests.first?.userTurnId == stateMetadata.userTurnId)
            #expect(resumedRequests.first?.messages.filter { $0.role == .user && $0.text == request.content }.count == 1)
            let expectedContent = isAcceptance ? "changed contents must not replace the settled result" : originalContent
            #expect(resumedRequests.last?.messages.contains {
                $0.role == .tool && $0.toolOutput?.content.contains(expectedContent) == true
            } == true)
        }
        let detail = try await resumedService.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(detail.summary.userTurnCount == (durableInterrupt ? faultDetail.summary.userTurnCount : 1))
        #expect(detail.events.filter { $0.message?.id == messageID }.count == 1)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == (usesCompletion ? 2 : 1))
        #expect(await resumedScript.legacyCalls == 0)
    }


    @Test
    func acceptedInputResumesFromTheDurableResultWithoutAnotherUserTurn() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let script = SessionStepScript()
        await service.overrideModelProviderForTests(SessionStepFactory(script: script), defaultModel: models[0].id)
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let agentID = "native-resume-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native resume fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native resume fixture"))
        let store = await service.sessionStore
        let journalURL = URL(fileURLWithPath: try store.sessionFilePath(agentID: agentID, sessionID: session.id))
        let crash = SessionResultCrash(journal: journalURL)
        await orchestrator.updateEventAppendObserver { _, _, _, events in await crash.observe(events) }
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        let originalContent = "durable original contents " + String(repeating: "full result ", count: 80)
        try originalContent.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let messageID = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Read session-target.txt.",
            mode: .ask, clientMessageId: messageID)
        do { _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request) }
        catch { /* The durable result survived; subsequent journal appends fail. */ }
        try await crash.restore()
        #expect(await crash.tripped)
        #expect(await crash.failure == nil)
        #expect(await script.requests.count == 1)
        let recoveredStore = AgentSessionFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let faultDetail = try recoveredStore.loadSession(agentID: agentID, sessionID: session.id)
        let stateMetadata = try #require(faultDetail.events.last(where: { $0.runtimeMetadata?.runState != nil })?.runtimeMetadata)
        #expect(faultDetail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        try "changed contents must not replace the settled result".write(to: file, atomically: true, encoding: .utf8)

        try await service.exitPreservingCrashImageForLoopTests()
        let resumedService = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await resumedService.waitForStartup(dispatchReadyTasks: false)
        let resumedScript = SessionStepScript(initialIndex: 1)
        await resumedService.overrideModelProviderForTests(SessionStepFactory(script: resumedScript), defaultModel: models[0].id)
        let resumedOrchestrator = await resumedService.sessionOrchestrator
        await resumedOrchestrator.updateAvailableModels(models)
        var response: AgentSessionMessageResponse?
        var failure: Error?
        do { response = try await resumedService.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request) }
        catch { failure = error }
        #expect(failure == nil)
        #expect(response?.appendedEvents.contains {
            $0.message?.role == .assistant && $0.message?.segments.first?.text == "Read result reported."
        } == true)
        let resumedRequests = await resumedScript.requests
        #expect(resumedRequests.count == 1)
        #expect(resumedRequests.first?.runId == stateMetadata.runId)
        #expect(resumedRequests.first?.userTurnId == stateMetadata.userTurnId)
        #expect(resumedRequests.first?.messages.contains { $0.role == .tool && $0.toolOutput?.content.contains(originalContent) == true } == true)
        #expect(resumedRequests.first?.messages.filter { $0.role == .user && $0.text == request.content }.count == 1)
        let detail = try await resumedService.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(detail.summary.userTurnCount == 1)
        #expect(detail.events.filter { $0.message?.id == messageID }.count == 1)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        #expect(await resumedScript.legacyCalls == 0)
    }


    @Test(arguments: [false, true])
    func retryOfDeliveredClientMessageDoesNotExecuteAnotherTurn(reopen: Bool) async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let script = SessionStepScript()
        await service.overrideModelProviderForTests(SessionStepFactory(script: script), defaultModel: models[0].id)
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let agentID = "native-retry-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native retry fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native retry fixture"))
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        try "original version".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let messageID = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Read session-target.txt.",
            mode: .ask, clientMessageId: messageID)
        _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request)
        let firstStore = await service.sessionStore
        let journal = URL(fileURLWithPath: try firstStore.sessionFilePath(agentID: agentID, sessionID: session.id))
        let before = try Data(contentsOf: journal)
        try "new version must not be read by a delivery retry".write(to: file, atomically: true, encoding: .utf8)
        if reopen { try await service.exitPreservingCrashImageForLoopTests() }
        let retryService = reopen ? CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder()) : service
        let retryScript = reopen ? SessionStepScript() : script
        if reopen {
            await retryService.waitForStartup(dispatchReadyTasks: false)
            await retryService.overrideModelProviderForTests(SessionStepFactory(script: retryScript), defaultModel: models[0].id)
            let retryOrchestrator = await retryService.sessionOrchestrator
            await retryOrchestrator.updateAvailableModels(models)
        }
        let retried = try await retryService.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request)
        #expect(retried.replayed == true)
        #expect(retried.appendedEvents.contains {
            $0.message?.role == .assistant && $0.message?.segments.first?.text == "Read result reported."
        })
        #expect(await retryScript.requests.count == (reopen ? 0 : 2))
        #expect(try Data(contentsOf: journal) == before)
        var conflict = false
        do {
            _ = try await retryService.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: "A different task cannot reuse this ID.", mode: .ask, clientMessageId: messageID))
        } catch { conflict = true }
        #expect(conflict)
        #expect(try Data(contentsOf: journal) == before)
        let detail = try await retryService.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(detail.summary.userTurnCount == 1)
        #expect(detail.events.filter { $0.message?.id == messageID }.count == 1)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        #expect(await retryScript.legacyCalls == 0)
    }

    @Test
    func activeEngineStaysPinnedAndLegacySelectorKeepsUsingTheCommonOwner() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        await service.overrideModelProviderForTests(SessionStepFactory(script: script, allowsLegacy: true), defaultModel: models[0].id)
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let agentID = "native-rollback-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native rollback fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native rollback fixture"))
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        try "pinned engine content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let taskText = "Read session-target.txt before completing this pinned turn."
        let initial = Task {
            try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: taskText, mode: .ask, clientMessageId: UUID().uuidString))
        }
        let didStart = await gate.waitUntilHeld(during: initial)
        if !didStart { await gate.release(); _ = try await initial.value }
        try #require(didStart)
        do {
            _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
                selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false,
                runtime: .init(sharedMemoryEnabled: false, nativeEngine: .legacy)), availableModels: models)
        } catch {
            await gate.release()
            _ = try? await initial.value
            throw error
        }
        await gate.release()
        let response = try await initial.value
        #expect(response.appendedEvents.contains {
            $0.message?.role == .assistant && $0.message?.segments.first?.text == "Read result reported."
        })
        let requests = await script.requests
        #expect(requests.count == 2)
        if let last = requests.last, requests.count == 2 {
            #expect(last.messages.map(\.text).joined(separator: "\n").components(separatedBy: taskText).count - 1 == 1)
            #expect(last.messages.last?.toolOutput?.content.contains("pinned engine content") == true)
        }
        #expect(await script.legacyCalls == 0)
        _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Continue using the compatible legacy selector.", mode: .ask))
        let fresh = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Compatible selector fixture"))
        let common = try await service.postAgentSessionMessage(agentID: agentID, sessionID: fresh.id,
            request: .init(userId: "fixture", content: "Read the file in a new conversation.", mode: .ask))
        #expect(common.appendedEvents.contains {
            $0.message?.role == .assistant && $0.message?.segments.first?.text == "Read result reported."
        })
        #expect(await script.requests.count == 6)
        #expect(await script.legacyCalls == 0)
    }

    @Test(arguments: [true, false])
    func retryOfAnActiveInputDoesNotQueueOrHideTheOriginalTask(clientSuppliedID: Bool) async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        await service.overrideModelProviderForTests(SessionStepFactory(script: script), defaultModel: models[0].id)
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let agentID = "native-inbox-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native inbox fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native inbox fixture"))
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        try "inbox fixture content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let suppliedID = UUID().uuidString
        let queuedText = "Read session-target.txt."
        let initial = Task {
            try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: "Read session-target.txt.", mode: .ask, clientMessageId: clientSuppliedID ? suppliedID : nil))
        }
        defer { Task { await gate.release() } }
        let didStart = await gate.waitUntilHeld(during: initial)
        if !didStart { await gate.release(); _ = try await initial.value }
        try #require(didStart)
        let accepted = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        let initialID = try #require(accepted.events.first { !$0.isHistorical && $0.message?.role == .user }?.message?.id)
        let queuedID = initialID
        let fileStore = await service.sessionStore
        let journalURL = URL(fileURLWithPath: try fileStore.sessionFilePath(agentID: agentID, sessionID: session.id))
        let beforeRetry = try Data(contentsOf: journalURL)
        let receipt: AgentSessionMessageResponse
        do {
            receipt = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: queuedText, mode: .ask, clientMessageId: queuedID))
        } catch {
            await gate.release()
            _ = try? await initial.value
            throw error
        }
        #expect(receipt.replayed == true)
        #expect(!(await service.pendingSessionMessageIDs(agentID: agentID, sessionID: session.id)).contains(initialID))
        #expect(try Data(contentsOf: journalURL) == beforeRetry)
        var conflictingPayloadWasRejected = false
        do {
            _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: "A changed task cannot acquire the active ID.",
                    mode: .ask, clientMessageId: initialID))
        } catch { conflictingPayloadWasRejected = true }
        #expect(conflictingPayloadWasRejected)
        await gate.release()
        _ = try await initial.value
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { frame in
            frame.messages.filter { $0.role == .user && $0.text == queuedText }.count == 1
        })
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(detail.summary.userTurnCount == 1)
        #expect(detail.events.filter { $0.message?.id == initialID }.count == 1)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        #expect(await script.legacyCalls == 0)
    }

    @Test(arguments: ["retained", "missing", "corrupt"])
    func queuedFollowUpCannotSupersedeAnUnfinishedInputAfterRestart(cacheState: String) async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        await service.overrideModelProviderForTests(SessionStepFactory(script: script), defaultModel: models[0].id)
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let agentID = "native-inbox-resume-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native inbox recovery fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native inbox recovery"))
        let store = await service.sessionStore
        let journalURL = URL(fileURLWithPath: try store.sessionFilePath(agentID: agentID, sessionID: session.id))
        let crash = SessionResultCrash(journal: journalURL)
        await orchestrator.updateEventAppendObserver { _, _, _, events in await crash.observe(events) }
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        let originalContent = "This result must survive before the queued follow-up runs."
        try originalContent.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let initialID = UUID().uuidString
        let queuedID = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Read session-target.txt.",
            mode: .ask, clientMessageId: initialID)
        let queuedText = "This follow-up belongs to the next user turn."
        let initial = Task {
            try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request)
        }
        let didStart = await gate.waitUntilHeld(during: initial)
        if !didStart { await gate.release(); _ = try await initial.value }
        try #require(didStart)
        do {
            _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: queuedText, mode: .ask, clientMessageId: queuedID))
        } catch {
            await gate.release()
            _ = try? await initial.value
            throw error
        }
        // Stop the old inbox owner before simulating the process loss; no old service may drain B.
        await service.stopInboxDispatchForLoopTests()
        await gate.release()
        _ = try? await initial.value
        if let runner = await service.sessionMessageRunners[session.id] { await runner.value }
        try await crash.restore()
        #expect(await crash.tripped)
        #expect(await crash.failure == nil)
        #expect(await script.requests.count == 1)
        try "New contents must not replace A's durable result.".write(to: file, atomically: true, encoding: .utf8)

        let cacheURL = config.resolvedWorkspaceRootURL().appendingPathComponent("session-messages/inbox.json")
        if cacheState == "missing" { try FileManager.default.removeItem(at: cacheURL) }
        if cacheState == "corrupt" { try Data("corrupt disposable queue cache".utf8).write(to: cacheURL, options: .atomic) }
        if cacheState == "unavailable" {
            let root = config.resolvedWorkspaceRootURL().standardizedFileURL
            let directory = cacheURL.deletingLastPathComponent().standardizedFileURL
            let preserved = root.appendingPathComponent("preserved-session-messages-" + UUID().uuidString).standardizedFileURL
            try #require(directory.path.hasPrefix(root.path + "/") && preserved.path.hasPrefix(root.path + "/"))
            try FileManager.default.moveItem(at: directory, to: preserved)
            try Data("The cache directory is temporarily unavailable".utf8).write(to: directory, options: .atomic)
        }

        try await service.exitPreservingCrashImageForLoopTests()
        let resumed = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let resumedScript = SessionStepScript(initialIndex: 1)
        await resumed.overrideModelProviderForTests(SessionStepFactory(script: resumedScript), defaultModel: models[0].id)
        let resumedOrchestrator = await resumed.sessionOrchestrator
        await resumedOrchestrator.updateAvailableModels(models)
        await resumed.waitForStartup(dispatchReadyTasks: false)
        if let runner = await resumed.sessionMessageRunners[session.id] { await runner.value }
        #expect(await resumed.pendingSessionMessageIDs(agentID: agentID, sessionID: session.id).contains(queuedID))
        #expect(await resumedScript.requests.isEmpty)
        var response: AgentSessionMessageResponse?
        var failure: Error?
        do { response = try await resumed.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request) }
        catch { failure = error }
        #expect(failure == nil)
        #expect(response?.appendedEvents.contains { $0.message?.role == .assistant } == true)
        if let runner = await resumed.sessionMessageRunners[session.id] { await runner.value }
        let requests = await resumedScript.requests
        #expect(requests.count == 3)
        #expect(requests.first?.userTurnId == initialID)
        #expect(requests.first?.messages.contains {
            $0.role == .tool && $0.toolOutput?.content.contains(originalContent) == true
        } == true)
        #expect(requests.first?.messages.contains { $0.text.contains(queuedText) } == false)
        #expect(requests.dropFirst().allSatisfy { $0.userTurnId == queuedID })
        let detail = try await resumed.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(detail.events.filter { $0.message?.id == initialID }.count == 1)
        #expect(detail.events.filter { $0.message?.id == queuedID }.count == 1)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 2)
        #expect(detail.summary.userTurnCount == 2)
        #expect(try SessionInputLifecycle.states(in: detail.events)[queuedID]?.latest.delivery == .delivered)
        #expect(try await resumed.inboxEntryForLoopTests(queuedID)?.state == .delivered)
        if cacheState != "unavailable" {
            let inbox = try SessionMessageInboxFileStore(root: config.resolvedWorkspaceRootURL())
            #expect(inbox.entries.first { $0.id == queuedID }?.state == .delivered)
        }
        #expect(await resumedScript.legacyCalls == 0)
    }

    @Test
    func canonicalIngressAcceptsNewInputWithoutAWritableCache() async throws {
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        let fixture = try await SessionIdentityFixture.make(script: script)
        let service = fixture.service
        defer { try? FileManager.default.removeItem(at: fixture.file); Task { await gate.release() } }
        let initialID = UUID().uuidString
        let queuedID = UUID().uuidString
        let queuedText = "Accept this follow-up through the canonical journal."
        let initial = Task {
            try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(userId: "fixture", content: "Read session-target.txt.", mode: .ask, clientMessageId: initialID))
        }
        let didStart = await gate.waitUntilHeld(during: initial)
        if !didStart { await gate.release(); _ = try await initial.value }
        try #require(didStart)
        let root = await service.workspaceRootURL.standardizedFileURL
        let directory = root.appendingPathComponent("session-messages").standardizedFileURL
        let preserved = root.appendingPathComponent("preserved-inbox-" + UUID().uuidString).standardizedFileURL
        try #require(directory.path.hasPrefix(root.path + "/") && preserved.path.hasPrefix(root.path + "/"))
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.moveItem(at: directory, to: preserved)
        }
        try Data("Temporarily blocked cache directory".utf8).write(to: directory, options: .atomic)
        var receipt: AgentSessionMessageResponse?
        var failure: Error?
        do {
            receipt = try await service.postAgentSessionMessage(agentID: fixture.agentID, sessionID: fixture.session.id,
                request: .init(userId: "fixture", content: queuedText, mode: .ask, clientMessageId: queuedID))
        } catch { failure = error }
        #expect(failure == nil)
        #expect(receipt?.appendedEvents.contains { $0.message?.id == queuedID && $0.inputTransitions?.first?.context != nil } == true)
        #expect(await service.pendingSessionMessageIDs(agentID: fixture.agentID, sessionID: fixture.session.id).contains(queuedID))
        await gate.release()
        _ = try await initial.value
        if let runner = await service.sessionMessageRunners[fixture.session.id] { await runner.value }
        let requests = await script.requests
        #expect(requests.count == 4)
        #expect(requests.prefix(2).allSatisfy { $0.userTurnId == initialID && !$0.messages.contains { $0.text.contains(queuedText) } })
        #expect(requests.dropFirst(2).allSatisfy { $0.userTurnId == queuedID })
        let detail = try await service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.session.id)
        #expect(detail.events.filter { $0.message?.id == queuedID }.count == 1)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 2)
        #expect(detail.summary.userTurnCount == 2)
        #expect(try SessionInputLifecycle.states(in: detail.events)[queuedID]?.latest.delivery == .delivered)
        #expect(try await service.inboxEntryForLoopTests(queuedID)?.state == .delivered)
        #expect(await script.legacyCalls == 0)
    }


    @Test
    func canonicalQueueContinuesWithAnUnavailableCacheDirectory() async throws {
        try await queuedFollowUpCannotSupersedeAnUnfinishedInputAfterRestart(cacheState: "unavailable")
    }

    @Test
    func queuedFollowUpWaitsForItsOwnTurnInTheRealCoreInbox() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        await service.overrideModelProviderForTests(SessionStepFactory(script: script), defaultModel: models[0].id)
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let agentID = "native-inbox-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native inbox fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, automaticModelRouting: false,
            runtime: .init(nativeEngine: .unified)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(title: "Native inbox fixture"))
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        try "inbox fixture content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let initialID = UUID().uuidString
        let queuedID = UUID().uuidString
        let queuedText = "This queued follow-up must wait for its own turn."
        let initial = Task {
            try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: "Read session-target.txt.", mode: .ask, clientMessageId: initialID))
        }
        let didStart = await gate.waitUntilHeld(during: initial)
        if !didStart { await gate.release(); do { _ = try await initial.value } catch { throw SessionFixtureFailure.original(error) } }
        try #require(didStart)
        let receipt: AgentSessionMessageResponse
        do {
            receipt = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
                request: .init(userId: "fixture", content: queuedText, mode: .ask, clientMessageId: queuedID))
        } catch {
            await gate.release()
            _ = try? await initial.value
            throw SessionFixtureFailure.receipt(error)
        }
        #expect(receipt.appendedEvents.contains { $0.message?.id == queuedID })
        #expect(await service.pendingSessionMessageIDs(agentID: agentID, sessionID: session.id).contains(queuedID))
        await gate.release()
        do { _ = try await initial.value } catch { throw SessionFixtureFailure.original(error) }
        if let runner = await service.sessionMessageRunners[session.id] { await runner.value }
        let requests = await script.requests
        #expect(requests.count == 4)
        #expect(requests.prefix(2).allSatisfy { frame in
            !frame.messages.contains { $0.text.contains(queuedText) }
        })
        if requests.count >= 3 {
            let next = requests[2]
            #expect(next.userTurnId == queuedID)
            #expect(next.messages.map(\.text).joined(separator: "\n").components(separatedBy: queuedText).count - 1 == 1)
            let queuedIndex = try #require(next.messages.firstIndex { $0.text == queuedText })
            let previousAnswer = try #require(next.messages.lastIndex { $0.role == .assistant && $0.text == "Read result reported." })
            #expect(previousAnswer < queuedIndex)
            let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
            let scopedContext = try #require(detail.events.first { $0.runtimeMetadata?.inputMessageId == queuedID &&
                $0.runtimeMetadata?.admissionInstructions != nil }?.runtimeMetadata?.admissionInstructions)
            #expect(!scopedContext.isEmpty)
            #expect(Array(next.messages.dropFirst(queuedIndex + 1).prefix(scopedContext.count)).map(\.text) == scopedContext.map(\.text))

            // A later run may compact the previous queue turn while retaining both answers.
            let store = await service.sessionStore
            let aFinal = try #require(detail.events.last { $0.runtimeMetadata?.userTurnId == initialID && $0.runtimeMetadata?.modelResponse != nil })
            let bFinal = try #require(detail.events.last { $0.runtimeMetadata?.userTurnId == queuedID && $0.runtimeMetadata?.modelResponse != nil })
            let covered = try store.loadJournal(agentID: agentID, sessionID: session.id)
            let lastID = try #require(covered.records.last?.event.id)
            let laterRun = UUID().uuidString
            let laterTurn = UUID().uuidString
            let checkpoint = SessionProjectionCheckpoint(coveredCursor: covered.cursor, coveredThroughEventId: lastID,
                summary: "Previous work summarized for the next task.", retainedEventIds: [aFinal.id, bFinal.id])
            _ = try store.appendEvents(agentID: agentID, sessionID: session.id, events: [
                .init(version: 2, agentId: agentID, sessionId: session.id, type: .memoryCheckpoint,
                    runtimeMetadata: .init(runId: laterRun, userTurnId: laterTurn, checkpoint: checkpoint))
            ])
            let projected = try SessionProjection.load(store: store, agentID: agentID, sessionID: session.id)
            let laterRequest = ModelStepRequest(runId: laterRun, userTurnId: laterTurn,
                stepId: UUID().uuidString, attemptId: UUID().uuidString, model: models[0].id,
                projectionRevision: "", cacheScope: session.id, messages: [])
            let messages = try projected.modelMessages(for: laterRequest)
            let aIndex = try #require(messages.firstIndex { $0.id == aFinal.id })
            let bInputIndex = try #require(messages.firstIndex { $0.text == queuedText })
            let bIndex = try #require(messages.firstIndex { $0.id == bFinal.id })
            #expect(aIndex < bInputIndex)
            #expect(bInputIndex < bIndex)
            #expect(messages.filter { $0.text == queuedText }.count == 1)
        }
        #expect(await script.legacyCalls == 0)
    }

    @Test(arguments: [false, true])
    func sessionUsesRealCoreToolsAndCanonicalHistoryAcrossTurns(reopen: Bool) async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let catalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
        let store = await service.sessionStore
        let models = [ProviderModelOption(id: "openai-api:gpt-5.4-mini", title: "Fixture", capabilities: ["tools"])]
        let agentID = "native-session-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native session fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role,
            selectedModel: models[0].id, documents: original.documents, runtime: .init(nativeEngine: .unified)), availableModels: models)
        let calls = SessionNativeCalls()
        let firstScript = SessionStepScript()
        func makeOrchestrator(script: SessionStepScript, fileStore: AgentSessionFileStore) -> AgentSessionOrchestrator {
            let runtime = RuntimeSystem(modelProvider: SessionStepFactory(script: script), defaultModel: models[0].id)
            let ownedCatalog = AgentCatalogFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents"))
            return AgentSessionOrchestrator(runtime: runtime, sessionStore: fileStore, agentCatalogStore: ownedCatalog,
                availableModels: models, persistedModelContext: (config, false),
                nativeToolInvoker: { agent, session, request, mode, context in
                    await calls.record()
                    return await service.invokeNativeTool(agentID: agent, sessionID: session, request: request,
                        context: context, chatMode: mode)
                })
        }
        let first = makeOrchestrator(script: firstScript, fileStore: store)
        let session = try await first.createSession(agentID: agentID, request: .init(title: "Native fixture"))
        let priorTask = "A prior persisted user turn."
        _ = try store.appendEvents(agentID: agentID, sessionID: session.id, events: [
            .init(agentId: agentID, sessionId: session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: priorTask)]))
        ])
        let file = await service.workspaceRootURL.appendingPathComponent("session-target.txt")
        try "first complete content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let task = "Read session-target.txt and report its current complete content."
        var response: AgentSessionMessageResponse?
        do { response = try await first.postMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: task, mode: .ask, clientMessageId: UUID().uuidString)) }
        catch { }
        #expect(response != nil)
        #expect(await calls.count == 1)
        #expect(await firstScript.legacyCalls == 0)
        let firstRequests = await firstScript.requests
        #expect(firstRequests.count == 2)
        #expect(firstRequests.last?.messages.last?.toolOutput?.content.contains("first complete content") == true)
        if let frame = firstRequests.first {
            let joined = frame.messages.map(\.text).joined(separator: "\n")
            #expect(joined.components(separatedBy: task).count - 1 == 1)
            #expect(joined.components(separatedBy: priorTask).count - 1 == 1)
        }
        try "second complete content".write(to: file, atomically: true, encoding: .utf8)
        let secondScript = reopen ? SessionStepScript() : firstScript
        let secondStore = reopen ? AgentSessionFileStore(agentsRootURL: config.resolvedWorkspaceRootURL().appendingPathComponent("agents")) : store
        let second = reopen ? makeOrchestrator(script: secondScript, fileStore: secondStore) : first
        var followUp: AgentSessionMessageResponse?
        do { followUp = try await second.postMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Read the file again from its current version.", mode: .ask,
                clientMessageId: UUID().uuidString)) }
        catch { }
        #expect(followUp != nil)
        #expect(await calls.count == 2)
        #expect(await secondScript.legacyCalls == 0)
        let secondRequests = await secondScript.requests
        #expect(secondRequests.last?.messages.last?.toolOutput?.content.contains("second complete content") == true)
        let detail = try secondStore.loadSession(agentID: agentID, sessionID: session.id)
        let toolCalls = detail.events.filter { $0.type == .toolCall }
        #expect(toolCalls.count == 2)
        #expect(toolCalls.allSatisfy { $0.runtimeMetadata?.providerCallId != nil && $0.runtimeMetadata?.callEventId == $0.id })
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 2)
        #expect(detail.events.filter { $0.message?.role == .assistant && $0.message?.segments.first?.text == "Read result reported." }.count == 2)
        #expect(SessionToolRecovery.unknownEffectCallIDs(in: detail.events).isEmpty)
    }

    @Test
    func forkedNativeHistoryCannotOwnTheForkedSession() async throws {
        let script = SessionStepScript()
        let fixture = try await SessionIdentityFixture.make(script: script)
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let service = fixture.service
        let agentID = fixture.agentID
        let sourceID = fixture.session.id
        let originalID = UUID().uuidString
        let originalTask = "Read session-target.txt."
        _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: sourceID,
            request: .init(userId: "fixture", content: originalTask, mode: .ask, clientMessageId: originalID))
        let source = try await service.getAgentSession(agentID: agentID, sessionID: sourceID)
        let originalUser = try #require(source.events.first { $0.message?.id == originalID })
        let fork = try await service.createAgentSession(agentID: agentID,
            request: .init(title: "Independent native fork", forkFromSessionId: sourceID))
        let before = try await service.getAgentSession(agentID: agentID, sessionID: fork.id)
        #expect(NativeSessionDelivery.firstUnfinishedInput(in: before) == nil)
        #expect(SessionToolRecovery.unknownEffectCallIDs(in: before.events).isEmpty)
        let copiedUser = try #require(before.events.first { $0.forkOrigin?.sourceEventId == originalUser.id })
        let copiedMessage = try #require(copiedUser.message)
        #expect(copiedMessage.id != originalID)
        let encoded = try JSONValueCoder.encode(copiedUser).asObject
        #expect(encoded?["forkOrigin"]?.asObject?["sourceAgentId"]?.asString == agentID)
        #expect(encoded?["forkOrigin"]?.asObject?["sourceSessionId"]?.asString == sourceID)
        #expect(encoded?["forkOrigin"]?.asObject?["sourceEventId"]?.asString == originalUser.id)
        let newID = UUID().uuidString
        let answer = try await service.postAgentSessionMessage(agentID: agentID, sessionID: fork.id,
            request: .init(userId: "fixture", content: "Read the file again in this independent session.",
                mode: .ask, clientMessageId: newID))
        if let runner = await service.sessionMessageRunners[fork.id] { await runner.value }
        #expect(answer.appendedEvents.contains { $0.message?.role == .assistant })
        #expect(!(await service.pendingSessionMessageIDs(agentID: agentID, sessionID: fork.id)).contains(newID))
        let requests = await script.requests
        #expect(requests.count == 4)
        let first = requests.dropFirst(2).first
        #expect(first?.userTurnId == newID)
        #expect(first?.runId != requests.first?.runId)
        #expect(first?.messages.filter { $0.role == .user && $0.text == originalTask }.count == 1)
        #expect(first?.messages.contains { $0.role == .assistant && $0.text == "Read result reported." } == true)
        #expect(first?.messages.contains { $0.text.contains("historical read content") } == true)
        #expect(first?.messages.contains { $0.role == .tool } == false)
        let after = try await service.getAgentSession(agentID: agentID, sessionID: fork.id)
        #expect(after.summary.userTurnCount == 1)
        #expect(await script.legacyCalls == 0)
    }

    @Test
    func deliveredInputRetryCannotEnterAnotherActiveTurnsQueue() async throws {
        let gate = SessionStepGate()
        // Requires adding a defaulted gateIndex test-fixture option before the new Red.
        let script = SessionStepScript(firstRequestGate: gate, gateIndex: 2)
        let fixture = try await SessionIdentityFixture.make(script: script)
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let service = fixture.service
        let agentID = fixture.agentID
        let sessionID = fixture.session.id
        let originalID = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Read session-target.txt.",
            mode: .ask, clientMessageId: originalID)
        _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: sessionID, request: request)
        let nextID = UUID().uuidString
        let next = Task {
            try await service.postAgentSessionMessage(agentID: agentID, sessionID: sessionID,
                request: .init(userId: "fixture", content: "Read the current file for my second task.",
                    mode: .ask, clientMessageId: nextID))
        }
        defer { Task { await gate.release() } }
        let started = await gate.waitUntilHeld(during: next)
        try #require(started)
        let store = await service.sessionStore
        let path = try store.sessionFilePath(agentID: agentID, sessionID: sessionID)
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        let replay: AgentSessionMessageResponse
        do { replay = try await service.postAgentSessionMessage(agentID: agentID, sessionID: sessionID, request: request) }
        catch { await gate.release(); _ = try? await next.value; throw error }
        #expect(replay.replayed == true)
        #expect(!(await service.pendingSessionMessageIDs(agentID: agentID, sessionID: sessionID)).contains(originalID))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
        await gate.release()
        _ = try await next.value
        if let runner = await service.sessionMessageRunners[sessionID] { await runner.value }
        let requests = await script.requests
        #expect(requests.count == 4)
        #expect(requests.suffix(2).allSatisfy { frame in
            frame.messages.filter { $0.role == .user && $0.text == request.content }.count == 1
        })
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: sessionID)
        #expect(detail.summary.userTurnCount == 2)
        #expect(detail.events.filter { $0.message?.id == originalID }.count == 1)
        #expect(detail.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 2)
        #expect(await script.legacyCalls == 0)
    }

    @Test
    func queuedInputIdentityIncludesTheEntireEffectivePayload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-inbox-identity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Read the approved file.",
            mode: .ask, clientMessageId: id)
        let store = try SessionMessageInboxFileStore(root: root)
        let entry = SessionMessageInboxFileStore.Entry(id: id, agentId: "fixture", sessionId: "session",
            request: request, origin: nil)
        _ = try store.enqueue(entry)
        let path = root.appendingPathComponent("session-messages/inbox.json")
        let bytes = try Data(contentsOf: path)
        let reopened = try SessionMessageInboxFileStore(root: root)
        _ = try reopened.enqueue(entry)
        #expect(try Data(contentsOf: path) == bytes)
        var variants: [AgentSessionPostMessageRequest] = []
        var changed = request; changed.mode = .build; variants.append(changed)
        changed = request; changed.userId = "another-user"; variants.append(changed)
        changed = request; changed.selectedModel = "openai-api:another-model"; variants.append(changed)
        changed = request; changed.reasoningEffort = .high; variants.append(changed)
        changed = request; changed.supportsA2UI = true; variants.append(changed)
        changed = request; changed.sessionReferences = [.init(agentId: "other", sessionId: "other")]; variants.append(changed)
        changed = request; changed.attachments = [.init(name: "input.txt", mimeType: "text/plain", sizeBytes: 1, contentBase64: "eA==")]; variants.append(changed)
        for variant in variants {
            var rejected = false
            do {
                _ = try reopened.enqueue(.init(id: id, agentId: "fixture", sessionId: "session", request: variant, origin: nil))
            } catch let error as PeerSessionMessageError {
                rejected = error.code == "message_id_conflict"
            }
            #expect(rejected)
            #expect(try Data(contentsOf: path) == bytes)
        }
    }

    @Test
    func forkHistoryCannotSetRoutingOrWorkerAuthority() async throws {
        let fixture = try await SessionIdentityFixture.make(script: SessionStepScript())
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let service = fixture.service
        let sourceID = fixture.session.id
        let agentID = fixture.agentID
        let completion = AgentSessionEvent(agentId: agentID, sessionId: sourceID, type: .toolResult,
            toolResult: .init(tool: "session.complete", ok: true, data: .object(["status": .string("completed")])))
        let route = AgentSessionEvent(agentId: agentID, sessionId: sourceID, type: .toolResult,
            toolResult: .init(tool: "planning.select_route", ok: true, data: .object(["mode": .string("build")])))
        let worker = AgentSessionEvent(agentId: agentID, sessionId: sourceID, type: .toolResult,
            toolResult: .init(tool: "agent_delegate.finish", ok: true, data: .object(["summary": .string("Original worker finished.")])))
        let store = await service.sessionStore
        _ = try store.appendEvents(agentID: agentID, sessionID: sourceID, events: [completion, route, worker])
        let source = try await service.getAgentSession(agentID: agentID, sessionID: sourceID)
        #expect(AgentSessionOrchestrator.unfinishedAutoRouteMode(events: source.events) == .build)
        #expect(await service.isPeerCommunicationSession(source))
        let fork = try await service.createAgentSession(agentID: agentID,
            request: .init(title: "Independent policy context", forkFromSessionId: sourceID))
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: fork.id)
        #expect(AgentSessionOrchestrator.unfinishedAutoRouteMode(events: detail.events) == nil)
        #expect(!(await service.isPeerCommunicationSession(detail)))
        let historicalCompletion = try #require(detail.events.first { $0.toolResult?.tool == "session.complete" })
        let liveRoute = AgentSessionEvent(agentId: agentID, sessionId: fork.id, type: .toolResult,
            toolResult: .init(tool: "planning.select_route", ok: true, data: .object(["mode": .string("build")])))
        #expect(AgentSessionOrchestrator.unfinishedAutoRouteMode(events: [liveRoute, historicalCompletion]) == .build)
    }

    @Test
    func historicalUUIDCannotConsumeOrHideALiveQueuedInput() async throws {
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate, gateIndex: 2)
        let fixture = try await SessionIdentityFixture.make(script: script)
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let service = fixture.service
        let agentID = fixture.agentID
        let originalID = UUID().uuidString
        let originalText = "Read session-target.txt."
        _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: fixture.session.id,
            request: .init(userId: "fixture", content: originalText, mode: .ask, clientMessageId: originalID))
        let fork = try await service.createAgentSession(agentID: agentID,
            request: .init(title: "Queued identity collision", forkFromSessionId: fixture.session.id))
        let activeID = UUID().uuidString
        let active = Task {
            try await service.postAgentSessionMessage(agentID: agentID, sessionID: fork.id,
                request: .init(userId: "fixture", content: "Read the file for this fork's current task.",
                    mode: .ask, clientMessageId: activeID))
        }
        defer { Task { await gate.release() } }
        let started = await gate.waitUntilHeld(during: active)
        try #require(started)
        let newText = "This is a new authorized task under the copied historical UUID. Read the file again."
        let receipt: AgentSessionMessageResponse
        do {
            receipt = try await service.postAgentSessionMessage(agentID: agentID, sessionID: fork.id,
                request: .init(userId: "fixture", content: newText, mode: .ask, clientMessageId: originalID))
        } catch { await gate.release(); _ = try? await active.value; throw error }
        #expect(receipt.appendedEvents.contains {
            !$0.isHistorical && $0.message?.id == originalID && $0.message?.segments.first?.text == newText
        })
        let queued = try await service.getAgentSession(agentID: agentID, sessionID: fork.id)
        #expect(queued.events.filter { !$0.isHistorical && $0.message?.id == originalID }.count == 1)
        await gate.release()
        _ = try await active.value
        if let runner = await service.sessionMessageRunners[fork.id] { await runner.value }
        let requests = await script.requests
        #expect(requests.count == 6)
        #expect(requests.dropFirst(2).prefix(2).allSatisfy { frame in
            frame.messages.filter { $0.role == .user && $0.text == originalText }.count == 1
        })
        #expect(requests.suffix(2).allSatisfy { frame in
            frame.messages.filter { $0.role == .user && $0.text == newText }.count == 1
        })
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: fork.id)
        #expect(detail.events.filter { !$0.isHistorical && $0.message?.id == originalID }.count == 1)
        #expect(detail.events.filter {
            $0.isHistorical && $0.message?.role == .user && $0.message?.segments.first?.text == originalText
        }.count == 1)
        let messageIDs = detail.events.compactMap(\.message).map(\.id)
        #expect(Set(messageIDs).count == messageIDs.count)
        let through = try await service.createAgentSession(agentID: agentID,
            request: .init(title: "Through the live input", forkFromSessionId: fork.id, forkThroughMessageId: originalID))
        let throughDetail = try await service.getAgentSession(agentID: agentID, sessionID: through.id)
        #expect(throughDetail.events.contains { $0.message?.segments.first?.text == newText })
        let before = try await service.createAgentSession(agentID: agentID,
            request: .init(title: "Before the live input", forkFromSessionId: fork.id, forkBeforeMessageId: originalID))
        let beforeDetail = try await service.getAgentSession(agentID: agentID, sessionID: before.id)
        #expect(beforeDetail.events.contains { $0.message?.segments.first?.text == "Read the file for this fork's current task." })
        #expect(!beforeDetail.events.contains { $0.message?.segments.first?.text == newText })
        #expect(detail.summary.userTurnCount == 2)
        #expect(await script.legacyCalls == 0)
    }

    @Test(arguments: [SessionHistorySubmission.direct, .peer, .ui])
    fileprivate func historicalPresentationIDsCannotBeClaimedByNewSubmissions(kind: SessionHistorySubmission) async throws {
        let gate = SessionStepGate()
        let script = SessionStepScript(firstRequestGate: gate)
        let fixture = try await SessionIdentityFixture.make(script: script)
        defer { try? FileManager.default.removeItem(at: fixture.file) }
        let service = fixture.service
        let agentID = fixture.agentID
        let store = await service.sessionStore
        _ = try store.appendEvents(agentID: agentID, sessionID: fixture.session.id, events: [
            .init(agentId: agentID, sessionId: fixture.session.id, type: .message,
                message: .init(role: .user, segments: [.init(kind: .text, text: "Original historical task.")], userId: "fixture"))
        ])
        let fork = try await service.createAgentSession(agentID: agentID,
            request: .init(title: "Reserved presentation identity", forkFromSessionId: fixture.session.id))
        let history = try await service.getAgentSession(agentID: agentID, sessionID: fork.id)
        let reservedID = try #require(history.events.first { $0.isHistorical && $0.message?.role == .user }?.message?.id)
        #expect(UUID(uuidString: reservedID) != nil)
        let active = Task {
            try await service.postAgentSessionMessage(agentID: agentID, sessionID: fork.id,
                request: .init(userId: "fixture", content: "Read session-target.txt.", mode: .ask, clientMessageId: UUID().uuidString))
        }
        defer { Task { await gate.release() } }
        try #require(await gate.waitUntilHeld(during: active))
        let journal = URL(fileURLWithPath: try store.sessionFilePath(agentID: agentID, sessionID: fork.id))
        let bytes = try Data(contentsOf: journal)
        var rejected = false
        switch kind {
        case .direct:
            do {
                _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: fork.id,
                    request: .init(userId: "fixture", content: "A copied presentation ID cannot identify this new input.",
                        mode: .ask, clientMessageId: reservedID))
            } catch CoreService.AgentSessionError.invalidPayload { rejected = true }
        case .peer:
            do {
                _ = try await service.sendPeerSessionMessage(senderAgentID: agentID, senderSessionID: fixture.session.id,
                    targetAgentID: agentID, targetSessionID: fork.id, content: "A copied ID cannot identify a peer input.", messageID: reservedID)
            } catch PeerSessionMessageError.conflict { rejected = true }
        case .ui:
            let submission = try JSONValueCoder.decode(AgentUISubmission.self, from: .object([
                "actionId": .string(reservedID), "componentId": .string("submit"), "revision": .number(1), "values": .object([:])
            ]))
            do {
                _ = try await service.submitAgentUIAction(agentID: agentID, sessionID: fork.id,
                    surfaceID: "not-a-live-surface", submission: submission, userID: "fixture")
            } catch CoreService.AgentUIError.actionConflict { rejected = true }
            catch CoreService.AgentUIError.invalidAction { }
        }
        #expect(rejected)
        #expect(try Data(contentsOf: journal) == bytes)
        #expect(!(await service.pendingSessionMessageIDs(agentID: agentID, sessionID: fork.id)).contains(reservedID))
        await gate.release()
        _ = try await active.value
        if let runner = await service.sessionMessageRunners[fork.id] { await runner.value }
        #expect(await script.requests.count == 2)
        #expect(await script.legacyCalls == 0)
    }
}
