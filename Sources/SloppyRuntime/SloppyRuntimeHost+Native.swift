import Foundation
import AgentRuntime
import PluginSDK
import Protocols

/// The embedded host has no Core catalog. Its new format lives outside the legacy store.
private struct EmbeddedJournalFormat: Codable, Equatable {
    var version = 1
    var journalVersion = 4

    static func authorize(_ marker: URL, writing: Bool = true) throws {
        let saved = try JSONDecoder().decode(Self.self, from: Data(contentsOf: marker))
        guard saved.version == 1, writing ? saved.journalVersion == 4 : (3...4).contains(saved.journalVersion) else {
            throw SloppyRuntimeHost.HostError.runtimeFailure("Unsupported embedded journal format.")
        }
    }
}

enum EmbeddedCallbackContext {
    @TaskLocal static var conversations: Set<String> = []
    static func call<T: Sendable>(_ key: String, operation: @Sendable () async throws -> T) async rethrows -> T {
        try await $conversations.withValue(conversations.union([key]), operation: operation)
    }
}

extension SloppyRuntimeHost {
    func agentsRootURL(workspaceURL: URL, upgrading: Bool = false) throws -> URL {
        guard nativeEngine == .unified else {
            return workspaceURL.appendingPathComponent(".ada/workspace/agents", isDirectory: true)
        }
        let directory = workspaceURL.appendingPathComponent(".ada/workspace/native-agent-v1", isDirectory: true)
        let marker = directory.appendingPathComponent("format.json")
        if !FileManager.default.fileExists(atPath: marker.path) {
            if FileManager.default.fileExists(atPath: directory.path),
               !(try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty {
                throw HostError.runtimeFailure("The embedded journal compatibility marker is missing.")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(EmbeddedJournalFormat()).write(to: marker, options: .atomic)
            let handle = try FileHandle(forWritingTo: marker)
            defer { try? handle.close() }
            try handle.synchronize()
        }
        try EmbeddedJournalFormat.authorize(marker, writing: false)
        if upgrading {
            try JSONEncoder().encode(EmbeddedJournalFormat()).write(to: marker, options: .atomic)
            let handle = try FileHandle(forWritingTo: marker)
            try handle.synchronize(); try handle.close()
        }
        return directory.appendingPathComponent("agents", isDirectory: true)
    }

    func sendNative(prompt: String, channelID: String, workspaceURL: URL,
        build: @escaping @Sendable () async -> SloppyBuildResult,
        onText: @escaping @Sendable (String) async -> Void,
        onActivity: @escaping @Sendable (SloppyAgentActivity) async -> Void,
        additionalToolHandler: (@Sendable (ToolInvocationRequest) async -> ToolInvocationResult)?,
        maxToolRounds: Int, images: [SloppyImageInput], persistedSessionID: String?, clientMessageID: String?,
        deliveryIntent: AgentInputDeliveryIntent?) async throws -> String {
        try Task.checkCancellation()
        let workspaceRoot = workspaceURL.standardizedFileURL.resolvingSymlinksInPath()
        let setupLease = try FileOwnershipLease.acquire(at: workspaceRoot.appendingPathComponent(".ada/workspace/native-agent-setup.lock"))
        let prepared: (AgentSessionFileStore, String)
        do {
            _ = try agentsRootURL(workspaceURL: workspaceRoot, upgrading: true)
            prepared = try prepareStoredSession(channelID: channelID, workspaceURL: workspaceRoot,
                persistedSessionID: persistedSessionID)
        } catch { setupLease.release(); throw error }
        setupLease.release()
        let (store, sessionID) = prepared
        let key = workspaceRoot.path + "\n" + sessionID
        guard !EmbeddedCallbackContext.conversations.contains(key) else { throw HostError.reentrantSend }
        let runtimeChannelID = "embedded:" + ContentDigest.sha256(Data(workspaceRoot.path.utf8)) + ":session:" + sessionID
        let marker = workspaceRoot.appendingPathComponent(".ada/workspace/native-agent-v1/format.json")
        let authorize: @Sendable () throws -> Void = { try EmbeddedJournalFormat.authorize(marker) }
        let journal = SessionLoopJournal(store: store, agentID: "mobile", sessionID: sessionID, authorizeWriter: authorize)
        let sessionLease: FileOwnershipLease
        if var held = nativeSessionLeases[key] {
            held.callers += 1; nativeSessionLeases[key] = held; sessionLease = held.lease
        } else {
            let path = URL(fileURLWithPath: try store.sessionFilePath(agentID: "mobile", sessionID: sessionID))
            sessionLease = try FileOwnershipLease.acquire(at: path.appendingPathExtension("owner.lock"))
            nativeSessionLeases[key] = (sessionLease, 1)
        }
        defer {
            if var held = nativeSessionLeases[key], held.callers > 1 {
                held.callers -= 1; nativeSessionLeases[key] = held
            } else {
                nativeSessionLeases.removeValue(forKey: key)
                Task { _ = try? self.cleanupToolOutputs(workspaceURL: workspaceRoot, persistedSessionID: sessionID,
                    olderThan: Date().addingTimeInterval(-86_400)) }
            }
        }
        let inputID = clientMessageID ?? UUID().uuidString
        guard UUID(uuidString: inputID) != nil else { throw HostError.runtimeFailure("Invalid embedded message identity.") }
        let uploads = images.enumerated().map { index, image in
            AgentAttachmentUpload(name: "image-\(index).png", mimeType: image.mimeType, sizeBytes: image.data.count,
                contentBase64: image.data.base64EncodedString())
        }
        var submission = AgentSessionPostMessageRequest(userId: "user", content: prompt,
            attachments: uploads, mode: deliveryIntent == .steering ? nil : .ask, clientMessageId: inputID)
        submission.deliveryIntent = deliveryIntent == .steering ? .steering : nil
        let fingerprint = try SessionInputCapture.fingerprint(submission, peerOrigin: nil)
        // The actor serializes enqueue with selection. The journal is authoritative even if
        // the app exits while this caller is waiting for the preceding turn.
        let received = try store.loadSession(agentID: "mobile", sessionID: sessionID)
        let receivedInputs = try SessionInputLifecycle.states(in: received.events)
        if let previous = receivedInputs[inputID] {
            guard previous.latest.fingerprint == fingerprint else {
                throw HostError.runtimeFailure("The saved embedded input does not match this retry.")
            }
        } else {
            // An interrupted effect must be reconciled before accepting more work. Live
            // starts belong to the active owner and settle before the queue is selected.
            if !activeNativeChannels.contains(key), !SessionToolRecovery.unknownEffectCallIDs(in: received.events).isEmpty {
                throw HostError.reconciliationRequired
            }
            guard modelID != nil else { throw HostError.missingCredentials }
            let attachments = try store.persistAttachments(agentID: "mobile", sessionID: sessionID, uploads: uploads)
            let context = try SessionInputCapture.capture(submission, messageID: inputID, attachments: attachments, peerOrigin: nil)
            try authorize()
            _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: [
                .init(id: inputID, version: 3, agentId: "mobile", sessionId: sessionID, type: .message,
                    inputTransitions: [.init(messageId: inputID, fingerprint: fingerprint, disposition: .queued, context: context)],
                    message: .init(id: inputID, role: .user, segments: [.init(kind: .text, text: prompt)] + attachments.map {
                        .init(kind: .attachment, attachment: $0)
                    }, userId: "user"))
            ])
        }
        let callerKey = key + "\n" + inputID
        nativeInputCallers[callerKey, default: 0] += 1
        var acquired = false
        defer {
            if acquired { releaseNativeTurn(key: key) }
            if nativeInputCallers[callerKey] == 1 { nativeInputCallers.removeValue(forKey: callerKey) }
            else { nativeInputCallers[callerKey, default: 1] -= 1 }
        }
        do {
            try await acquireNativeTurn(key: key)
            acquired = true
            try Task.checkCancellation()
        } catch {
            if error is CancellationError, nativeInputCallers[callerKey] == 1,
               let saved = try SessionInputLifecycle.states(in: store.loadSession(agentID: "mobile", sessionID: sessionID).events)[inputID],
               saved.latest.disposition == .queued, saved.owner == nil {
                try authorize()
                _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: [
                    .init(version: 3, agentId: "mobile", sessionId: sessionID, type: .runStatus,
                        inputTransitions: [.init(messageId: inputID, fingerprint: fingerprint, disposition: .cancelled, delivery: .delivered)])
                ])
            }
            throw error
        }
        let detail = try store.loadSession(agentID: "mobile", sessionID: sessionID)
        guard SessionToolRecovery.unknownEffectCallIDs(in: detail.events).isEmpty else {
            throw HostError.reconciliationRequired
        }
        let inputs = try SessionInputLifecycle.states(in: detail.events)
        let state: RunState
        if let previous = inputs[inputID], previous.owner != nil {
            guard previous.latest.fingerprint == fingerprint, let owner = previous.owner,
                  let restored = try await journal.restoreRunState(userTurnID: owner.userTurnId),
                  restored.runID == owner.runId else {
                throw HostError.runtimeFailure("The saved embedded input does not match this retry.")
            }
            let saved = await restored.snapshot()
            if saved.phase == .settled {
                guard let raw = detail.events.last(where: { !$0.isHistorical &&
                    $0.runtimeMetadata?.runId == owner.runId && $0.runtimeMetadata?.userTurnId == owner.userTurnId &&
                    $0.runtimeMetadata?.presentationOnly != true && $0.runtimeMetadata?.modelResponse != nil })?.runtimeMetadata?.modelResponse else {
                    throw HostError.runtimeFailure("The saved embedded response is unavailable.")
                }
                let response = try JSONValueCoder.decode(ModelStepResponse.self, from: raw)
                guard response.stopReason == .endTurn, response.toolCalls.isEmpty else {
                    throw HostError.runtimeFailure("The saved embedded response is incomplete.")
                }
                if previous.latest.delivery != .delivered {
                    try Self.appendEmbeddedDelivery(store: store, sessionID: sessionID, inputID: inputID,
                        fingerprint: fingerprint, owner: owner, generation: saved.generation, authorize: authorize)
                }
                await EmbeddedCallbackContext.call(key) { await onText(response.text) }
                return response.text
            }
            guard saved.phase != .stopping else {
                throw HostError.runtimeFailure(saved.toolStop?.message ?? "The saved embedded turn was interrupted.")
            }
            state = restored
        } else {
            guard inputs[inputID]?.latest.disposition == .queued else {
                throw HostError.runtimeFailure("This embedded input is no longer eligible for admission.")
            }
            let queuedIDs = detail.events.compactMap { event -> String? in
                guard !event.isHistorical, let id = event.message?.id,
                      inputs[id]?.latest.disposition == .queued else { return nil }
                return id
            }
            guard queuedIDs.first == inputID else {
                throw HostError.runtimeFailure("Resume the earlier queued embedded input before this follow-up.")
            }
            for input in inputs.values where input.owner != nil && input.latest.delivery != .delivered {
                if let owner = input.owner, let previous = try await journal.restoreRunState(userTurnID: owner.userTurnId),
                   await previous.phase != .settled, await previous.phase != .stopping {
                    throw HostError.runtimeFailure("Resume the unfinished embedded turn using its client message identity.")
                }
            }
            guard let modelID else { throw HostError.missingCredentials }
            var config = NativeAgentLoopConfig(maxToolRounds: max(1, min(maxToolRounds, 200)),
                engine: .unified, requiresExplicitCompletion: false)
            config.completionContract = .session
            var settings = await runtime.resolvedAgentLoopRequestSettings(reasoningEffort: nil)
            settings.toolScope = Set(["files.list", "files.read", "files.write", "editor.build"] + additionalTools.map(\.name)).sorted()
            settings.delegatedAuthority = .init(policy: .init(), workingDirectory: workspaceRoot.path, extraRoots: [workspaceRoot.path])
            let snapshot = RunStateSnapshot(schemaVersion: 2, runID: UUID().uuidString, userTurnID: inputID,
                loopConfig: config, model: modelID, requestSettings: settings)
            state = try RunState(snapshot: snapshot)
            let context = inputs[inputID]?.context
            guard let context else { throw HostError.runtimeFailure("The queued embedded input is unavailable.") }
            _ = try SessionInputCapture.materialize(context, store: store, agentID: "mobile", sessionID: sessionID)
            let metadata = AgentRunMetadata(runId: state.runID, userTurnId: inputID,
                runState: try JSONValueCoder.encode(snapshot),
                admissionInstructions: [.init(kind: .turnContext, text: Self.embeddedWorkspaceInstructions)],
                inputMessageId: inputID, requestFingerprint: fingerprint)
            try authorize()
            _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: [
                .init(version: 3, agentId: "mobile", sessionId: sessionID, type: .runStatus,
                    runtimeMetadata: metadata, inputTransitions: [.init(messageId: inputID, fingerprint: fingerprint,
                        disposition: .admitted, owner: .init(runId: state.runID, userTurnId: inputID, generation: 0))])
            ])
        }
        let pinned = await state.snapshot()
        guard let config = pinned.loopConfig, let model = pinned.model,
              let authority = pinned.requestSettings?.delegatedAuthority,
              authority.workingDirectory == workspaceRoot.path, authority.extraRoots == [workspaceRoot.path] else {
            throw HostError.runtimeFailure("The saved embedded workspace authority is incompatible.")
        }
        let wrappedHandler: (@Sendable (ToolInvocationRequest) async -> ToolInvocationResult)?
        if let handler = additionalToolHandler {
            wrappedHandler = { request in await EmbeddedCallbackContext.call(key) { await handler(request) } }
        } else { wrappedHandler = nil }
        let workspace = SloppyWorkspaceToolExecutor(rootURL: workspaceRoot,
            build: { await EmbeddedCallbackContext.call(key) { await build() } },
            additionalToolNames: Set(additionalTools.map(\.name)), additionalToolHandler: wrappedHandler)
        let executor = AgentLoopToolExecutor(execute: { call, definition, arguments, beforeEffect in
            guard let metadata = call.runtimeMetadata, let step = metadata.stepId, let attempt = metadata.attemptId else {
                throw HostError.runtimeFailure("Missing persisted embedded invocation identity.")
            }
            let frame = ModelStepRequest(runId: state.runID, userTurnId: state.userTurnID, stepId: step,
                attemptId: attempt, model: model, projectionRevision: "", cacheScope: runtimeChannelID, messages: [],
                tools: [definition], generation: metadata.generation)
            return await ToolEffectRunner.run(toolID: definition.toolId, timeoutMilliseconds: 0,
                onLateResult: { result in
                    defer { withExtendedLifetime(sessionLease) {} }
                    // Preserve a factual late result even after the caller's generation was cancelled.
                    do { try await journal.appendResult(result, call: call, request: frame) }
                    catch { NSLog("Embedded late outcome persistence failed: %@", String(describing: error)) }
                }, operation: {
                    do { try Task.checkCancellation(); try await beforeEffect(); try Task.checkCancellation() }
                    catch { return .init(result: .init(tool: definition.toolId, ok: false,
                        error: .init(code: "effect_start_failed", message: String(describing: error), retryable: false))) }
                    return .init(result: await workspace.invoke(.init(tool: definition.toolId, arguments: arguments)))
                })
        })
        await runtime.setChannelBootstrap(channelId: runtimeChannelID, content: "Follow the saved embedded project instructions and tool results.")
        let outcome = EmbeddedHostOutcome()
        _ = await runtime.postMessage(channelId: runtimeChannelID, request: .init(userId: "user", content: prompt, model: model),
            onResponseChunk: { text in await EmbeddedCallbackContext.call(key) { await onText(text) }; return true }, observationHandler: { observation in
                switch observation {
                case .thinking: await EmbeddedCallbackContext.call(key) { await onActivity(.thinking) }
                case .toolCall(let request): await EmbeddedCallbackContext.call(key) { await onActivity(.toolStarted(request.tool)) }
                case .toolResult(let result): await EmbeddedCallbackContext.call(key) { await onActivity(.toolFinished(result.tool, succeeded: result.ok)) }
                case .usage: break
                }
            }, forceInlineResponse: true, nativeLoopConfig: config,
            nativeLoopOutcomeHandler: { await outcome.finish($0) }, runState: state,
            agentLoopServices: .init(journal: journal, executor: executor))
        guard let result = await outcome.value, result.finishedNaturally, result.turnExitReason == .completed,
              !result.lastAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HostError.runtimeFailure(await outcome.value?.lastAssistantText ?? "Embedded execution did not complete.")
        }
        try Self.appendEmbeddedDelivery(store: store, sessionID: sessionID, inputID: inputID, fingerprint: fingerprint,
            owner: inputs[inputID]?.owner ?? .init(runId: state.runID, userTurnId: inputID, generation: 0),
            generation: await state.generation, authorize: authorize)
        return result.lastAssistantText
    }

    private func acquireNativeTurn(key: String) async throws {
        try Task.checkCancellation()
        if activeNativeChannels.insert(key).inserted { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { nativeTurnWaiters[key, default: []].append(.init(id: id, continuation: continuation)) }
            }
        } onCancel: {
            Task { await self.cancelNativeTurnWaiter(key: key, id: id) }
        }
    }

    private func cancelNativeTurnWaiter(key: String, id: UUID) {
        guard let index = nativeTurnWaiters[key]?.firstIndex(where: { $0.id == id }),
              let waiter = nativeTurnWaiters[key]?.remove(at: index) else { return }
        if nativeTurnWaiters[key]?.isEmpty == true { nativeTurnWaiters.removeValue(forKey: key) }
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseNativeTurn(key: String) {
        if var waiting = nativeTurnWaiters.removeValue(forKey: key), !waiting.isEmpty {
            let next = waiting.removeFirst()
            if !waiting.isEmpty { nativeTurnWaiters[key] = waiting }
            next.continuation.resume()
        } else { activeNativeChannels.remove(key) }
    }

    private static func appendEmbeddedDelivery(store: AgentSessionFileStore, sessionID: String,
        inputID: String, fingerprint: String, owner: AgentInputOwner, generation: Int,
        authorize: @Sendable () throws -> Void) throws {
        try authorize()
        let terminalMetadata = AgentRunMetadata(runId: owner.runId, userTurnId: owner.userTurnId,
            generation: generation, inputMessageId: inputID, requestFingerprint: fingerprint)
        _ = try store.appendEvents(agentID: "mobile", sessionID: sessionID, events: [
            .init(version: 3, agentId: "mobile", sessionId: sessionID, type: .runStatus,
                runtimeMetadata: terminalMetadata,
                inputTransitions: [.init(messageId: inputID, fingerprint: fingerprint, disposition: .admitted,
                    delivery: .delivered, owner: owner)])
        ])
    }

    private static let embeddedWorkspaceInstructions = """
    You are an AdaScript game creation agent. This is a portable AdaScript project, not a SwiftPM project.
    Read .ada/project.json for configuration; edit Sources/*.ada and Assets/Scenes/*.ascn using files.list,
    files.read, and files.write. Keep changes inside the project. Use editor.build after changes; fix errors
    it reports before finishing. Summarize changed files and the actual build result.
    """
}

private actor EmbeddedHostOutcome {
    private(set) var value: NativeAgentLoopOutcome?
    func finish(_ outcome: NativeAgentLoopOutcome) { value = outcome }
}
