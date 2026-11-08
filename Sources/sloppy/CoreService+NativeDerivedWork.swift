import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime

/// A background action borrows a completed source; a later user task cannot inherit that permit.
typealias NativeDerivedWorkSource = AgentDerivedWorkSource

enum NativeDerivedWorkResolution {
    case legacy
    case blocked
    case owned(NativeDerivedWorkSource)
}

extension CoreService {
    /// Startup discovers work from the same canonical journal used by the normal
    /// schedulers. No prompt, authority, model or budget is reconstructed from defaults.
    func startNativeDerivedRecoveryIfNeeded() {
        guard nativeDerivedRecoveryTask == nil, !nativeDerivedWorkIsStopping,
              toolApprovalService.hasExclusivePersistenceOwnership else { return }
        nativeDerivedRecoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.resumeOutstandingNativeDerivedRuns()
        }
    }

    private func resumeOutstandingNativeDerivedRuns() async {
        do {
            for agent in try agentCatalogStore.listAgents() {
                for session in try sessionStore.listSessions(agentID: agent.id, includeHeartbeat: true) {
                    guard !Task.isCancelled, !nativeDerivedWorkIsStopping else { return }
                    do {
                        let detail = try sessionStore.loadSession(agentID: agent.id, sessionID: session.id)
                        if let raw = detail.events.last(where: { !$0.isHistorical && $0.runtimeMetadata?.runState != nil })?.runtimeMetadata?.runState,
                           raw.asObject?["requestSettings"]?.asObject?["proactiveJob"] != nil {
                            let snapshot = try JSONValueCoder.decode(RunStateSnapshot.self, from: raw)
                            try snapshot.validate()
                            if (snapshot.phase != .settled && snapshot.phase != .stopping) || snapshot.canResumeProviderFailure {
                                _ = await resumeNativeProactiveJob(agentID: agent.id, sessionID: session.id, snapshot: snapshot)
                            }
                        }
                        var latest: [String: AgentRunMetadata] = [:]
                        for event in detail.events where !event.isHistorical {
                            if let metadata = event.runtimeMetadata, let source = metadata.derivedSource, metadata.runState != nil {
                                latest[source.kind.rawValue] = metadata
                            }
                        }
                        for key in latest.keys.sorted() {
                            guard let metadata = latest[key], let source = metadata.derivedSource, let raw = metadata.runState else { continue }
                            let snapshot = try JSONValueCoder.decode(RunStateSnapshot.self, from: raw)
                            try snapshot.validate()
                            guard ((snapshot.phase != .settled && snapshot.phase != .stopping) || snapshot.canResumeProviderFailure), snapshot.completion == nil,
                                  snapshot.requestSettings?.derivedSource == source,
                                  let settings = snapshot.requestSettings, let scope = settings.toolScope,
                                  let model = snapshot.model, nativeDerivedWorkSourceIsCurrent(source) else { continue }
                            let admission = detail.events.first { !$0.isHistorical && $0.runtimeMetadata?.runId == snapshot.runID &&
                                $0.runtimeMetadata?.admissionInstructions != nil }?.runtimeMetadata?.admissionInstructions
                            guard let admission, !admission.isEmpty else { continue }
                            _ = await runNativeDerivedJob(source: source, model: model,
                                bootstrap: admission.map(\.text).joined(separator: "\n\n"), prompt: "Resume the saved internal task.",
                                toolScope: Set(scope), additionalTools: source.kind == .selfImprovementProposal ? [Self.nativeProposalToolDefinition] : [],
                                maxToolRounds: snapshot.loopConfig?.maxToolRounds ?? 0,
                                failureReview: settings.proposalFailureReview ?? false, record: { _ in })
                        }
                    } catch {
                        logger.warning("native.derived.startup_session_failed", metadata: ["session_id": .string(session.id),
                            "error": .string(String(describing: error))])
                    }
                }
            }
        } catch { logger.warning("native.derived.startup_scan_failed", metadata: ["error": .string(String(describing: error))]) }
    }

    func nativeDerivedWorkSource(agentID: String, sessionID: String, ignoringDerivedRunID: String? = nil) throws -> NativeDerivedWorkResolution {
        let detail = try sessionStore.loadSession(agentID: agentID, sessionID: sessionID)
        let events = detail.events.filter { !$0.isHistorical && $0.runtimeMetadata?.derivedSource == nil }
        let status = events.last { $0.runStatus != nil }
        guard let metadata = status?.runtimeMetadata else {
            let config = try agentCatalogStore.getAgentRuntimeConfig(agentID: agentID)
            return config.type == .native && config.effectiveNativeEngine == .unified ? .blocked : .legacy
        }
        guard status?.runStatus?.stage == .done,
              let statusIndex = events.lastIndex(where: { $0.id == status?.id }),
              !events.dropFirst(statusIndex + 1).contains(where: { $0.runControl != nil || $0.message?.role == .user }),
              let raw = events.last(where: { $0.runtimeMetadata?.runState != nil &&
                  $0.runtimeMetadata?.runId == metadata.runId && $0.runtimeMetadata?.userTurnId == metadata.userTurnId })?.runtimeMetadata?.runState else { return .blocked }
        let snapshot = try JSONValueCoder.decode(RunStateSnapshot.self, from: raw)
        try snapshot.validate()
        guard snapshot.loopConfig?.engine == .unified, snapshot.runID == metadata.runId,
              snapshot.userTurnID == metadata.userTurnId, snapshot.generation == metadata.generation,
              snapshot.phase == .settled, snapshot.toolStop == nil,
              snapshot.completion == nil || snapshot.completion?.disposition == .completed,
              snapshot.requestSettings?.coordinatorNotification != true,
              !sessionHasPendingInput(detail),
              !(try SessionInputLifecycle.states(in: events).values.contains { $0.latest.disposition == .queued }),
              SessionToolRecovery.unknownEffectCallIDs(in: detail.events.filter {
                  ignoringDerivedRunID == nil || $0.runtimeMetadata?.runId != ignoringDerivedRunID
              }).isEmpty,
              let model = snapshot.model, let terminalID = status?.id else { return .blocked }
        return .owned(.init(agentID: agentID, sessionID: sessionID,
            owner: .init(runId: snapshot.runID, userTurnId: snapshot.userTurnID, generation: snapshot.generation),
            terminalEventID: terminalID, model: model, projectID: detail.summary.projectId, taskID: detail.summary.taskId))
    }

    func cancelNativeDerivedRuns(sessionID: String) async {
        let states = nativeDerivedRunsBySession.removeValue(forKey: sessionID) ?? [:]
        for state in states.values {
            await state.cancel()
        }
    }

    func runNativeMemoryCheckpoint(source: NativeDerivedWorkSource, channelID: String, model: String?,
        bootstrap: String, prompt: String, recorder: MemoryCheckpointActionRecorder) async -> Bool {
        await runNativeDerivedJob(source: source, model: model, bootstrap: bootstrap, prompt: prompt,
            toolScope: Self.memoryCheckpointToolAllowlist, record: { await recorder.record($0) })
    }

    func runNativeDerivedJob(source: NativeDerivedWorkSource, model: String?, bootstrap: String, prompt: String,
        toolScope: Set<String>, additionalTools: [ModelStepToolDefinition] = [], maxToolRounds: Int = 60,
        failureReview: Bool = false, record: @escaping @Sendable (ToolInvocationResult) async -> Void) async -> Bool {
        let reservation = source.sessionID + "/" + source.kind.rawValue + "/" + source.owner.runId + "/" + source.terminalEventID
        if let running = nativeDerivedReservations[reservation] {
            let result = await running.value
            if result, let detail = try? sessionStore.loadSession(agentID: source.agentID, sessionID: source.sessionID),
               let runID = detail.events.last(where: { $0.runtimeMetadata?.derivedSource == source && $0.runtimeMetadata?.runState != nil })?.runtimeMetadata?.runId {
                for event in detail.events where !event.isHistorical && event.runtimeMetadata?.runId == runID {
                    if let output = event.toolResult { await record(.init(tool: output.tool, ok: output.ok, data: output.data, error: output.error)) }
                }
            }
            return result
        }
        let operation = Task { [weak self] in
            guard let self else { return false }
            return await self.executeNativeDerivedJob(source: source, model: model, bootstrap: bootstrap, prompt: prompt,
                toolScope: toolScope, additionalTools: additionalTools, maxToolRounds: maxToolRounds, failureReview: failureReview, record: record)
        }
        nativeDerivedReservations[reservation] = operation
        defer { nativeDerivedReservations.removeValue(forKey: reservation) }
        return await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
    }

    private func executeNativeDerivedJob(source: NativeDerivedWorkSource, model: String?, bootstrap: String, prompt: String,
        toolScope: Set<String>, additionalTools: [ModelStepToolDefinition], maxToolRounds: Int,
        failureReview: Bool, record: @escaping @Sendable (ToolInvocationResult) async -> Void) async -> Bool {
        guard let ownershipLease = await toolApprovalService.currentOwnershipLease() else { return false }
        defer { withExtendedLifetime(ownershipLease) {} }
        do {
            guard nativeDerivedWorkSourceIsCurrent(source) else { return false }
            let minimumJournalVersion = source.kind == .memoryCheckpoint ? 4 : 5
            try agentCatalogStore.protectUnifiedJournalStorage(agentID: source.agentID,
                availableModels: availableAgentModels(), minimumJournalVersion: minimumJournalVersion)
            let writer = NativeJournalWriterGuard(directory: try agentCatalogStore.directoryURL(agentID: source.agentID))
            try writer.authorize(minimumJournalVersion: minimumJournalVersion)
            let detail = try sessionStore.loadSession(agentID: source.agentID, sessionID: source.sessionID)
            let reader = SessionLoopJournal(store: sessionStore, agentID: source.agentID, sessionID: source.sessionID,
                authorizeWriter: { try writer.authorize(minimumJournalVersion: minimumJournalVersion) }, includeResponseMessages: false,
                derivedSource: source)
            let state: RunState
            if let metadata = detail.events.last(where: { !$0.isHistorical &&
                $0.runtimeMetadata?.derivedSource == source && $0.runtimeMetadata?.runState != nil })?.runtimeMetadata {
                guard let restored = try await reader.restoreRunState(userTurnID: metadata.userTurnId),
                      restored.runID == metadata.runId else { return false }
                state = restored
                let saved = await state.snapshot()
                guard SessionToolRecovery.unknownEffectCallIDs(in: detail.events).isEmpty else { return false }
                if saved.canResumeProviderFailure {
                    try await state.resumeAfterProviderFailure()
                    let resumed = await state.snapshot()
                    guard let pinnedModel = resumed.model else { return false }
                    let frame = ModelStepRequest(runId: resumed.runID, userTurnId: resumed.userTurnID,
                        stepId: UUID().uuidString, attemptId: UUID().uuidString, model: pinnedModel,
                        projectionRevision: "", cacheScope: resumed.runID, messages: [], tools: [], generation: resumed.generation)
                    try await reader.appendRunState(resumed, request: frame)
                } else if saved.phase == .settled {
                    guard saved.toolStop == nil, !saved.hitToolRoundLimit,
                          saved.requestSettings?.derivedSource == source else { return false }
                    for event in detail.events where !event.isHistorical && event.runtimeMetadata?.runId == saved.runID {
                        if let result = event.toolResult {
                            await record(.init(tool: result.tool, ok: result.ok, data: result.data, error: result.error))
                        }
                    }
                    return true
                } else if saved.phase == .stopping || saved.completion != nil { return false }
            } else {
                state = try await admitNativeDerivedRun(source: source, detail: detail, model: model ?? source.model, bootstrap: bootstrap,
                    prompt: prompt, writer: writer, toolScope: toolScope, maxToolRounds: maxToolRounds, failureReview: failureReview)
            }
            let pinned = await state.snapshot()
            guard let config = pinned.loopConfig, config.completionContract == .background,
                  let pinnedSettings = pinned.requestSettings, pinnedSettings.derivedSource == source,
                  pinnedSettings.toolScope == toolScope.sorted(),
                  let pinnedModel = pinned.model, nativeDerivedWorkSourceIsCurrent(source) else { return false }
            // Affinity belongs to the durable internal run, including a fresh-process continuation.
            let ownedChannelID = sessionChannelID(agentID: source.agentID, sessionID: source.sessionID) +
                (source.kind == .memoryCheckpoint ? ":memory-checkpoint:" : ":proposal-review:") + state.runID.lowercased()
            nativeDerivedRunsBySession[source.sessionID, default: [:]][state.runID] = state
            defer {
                nativeDerivedRunsBySession[source.sessionID]?.removeValue(forKey: state.runID)
                if nativeDerivedRunsBySession[source.sessionID]?.isEmpty == true { nativeDerivedRunsBySession.removeValue(forKey: source.sessionID) }
            }
            let journal = SessionLoopJournal(store: sessionStore, agentID: source.agentID, sessionID: source.sessionID,
                authorizeWriter: { try writer.authorize(minimumJournalVersion: minimumJournalVersion) }, includeResponseMessages: false,
                derivedSource: source, beforeRequest: { [weak self] in
                    guard let self, await self.nativeDerivedWorkSourceIsCurrent(source) else {
                        await state.cancel()
                        throw CancellationError()
                    }
                })
            let executor = AgentLoopToolExecutor(execute: { [weak self] call, definition, arguments, beforeEffect in
                guard let self, var metadata = call.runtimeMetadata,
                      let step = metadata.stepId, let attempt = metadata.attemptId else { throw CancellationError() }
                metadata.derivedSource = source
                let frame = ModelStepRequest(runId: state.runID, userTurnId: state.userTurnID,
                    stepId: step, attemptId: attempt, model: pinnedModel, projectionRevision: "", cacheScope: ownedChannelID,
                    messages: [], tools: [definition], generation: metadata.generation)
                let native = NativeToolExecutionContext(delegatedAuthority: pinnedSettings.delegatedAuthority,
                    delegatedToolScope: pinnedSettings.toolScope, metadata: metadata, definition: definition,
                    beforeEffect: beforeEffect, recordLateResult: { result in
                        try await journal.appendResult(result, call: call, request: frame)
                    })
                let request = ToolInvocationRequest(tool: definition.toolId, arguments: arguments)
                let outcome: AgentLoopToolOutcome
                if source.kind == .selfImprovementProposal {
                    outcome = await self.invokeNativeProposalTool(source: source, request: request, context: native,
                        initialPolicy: pinnedSettings.delegatedAuthority?.policy, failureReview: pinnedSettings.proposalFailureReview ?? false,
                        journal: journal, call: call, frame: frame)
                } else {
                    outcome = await self.invokeNativeTool(agentID: source.agentID, sessionID: source.sessionID,
                        request: request, context: native)
                }
                await record(outcome.result)
                return outcome
            })
            await runtime.setChannelToolScope(channelId: ownedChannelID, toolIDs: toolScope)
            await runtime.setChannelBootstrap(channelId: ownedChannelID,
                content: "Perform the saved internal background task with the restricted tool scope. Do not address the end user.")
            _ = await runtime.postMessage(channelId: ownedChannelID,
                request: .init(userId: source.kind.rawValue, content: prompt, model: pinnedModel),
                onResponseChunk: { _ in true }, forceInlineResponse: true, nativeLoopConfig: config,
                runState: state, agentLoopServices: .init(journal: journal, executor: executor, additionalTools: additionalTools))
            await runtime.discardEphemeralCheckpointChannel(channelId: ownedChannelID)
            let terminal = await state.snapshot()
            return terminal.phase == .settled && terminal.toolStop == nil && !terminal.hitToolRoundLimit &&
                nativeDerivedWorkSourceIsCurrent(source)
        } catch {
            logger.warning("memory.checkpoint.native_failed", metadata: ["error": .string(String(describing: error))])
            return false
        }
    }

    private func admitNativeDerivedRun(source: NativeDerivedWorkSource, detail: AgentSessionDetail, model: String,
        bootstrap: String, prompt: String, writer: NativeJournalWriterGuard, toolScope: Set<String>, maxToolRounds: Int,
        failureReview: Bool) async throws -> RunState {
        let policy = try await toolsAuthorization.policy(agentID: source.agentID)
        let context = await toolContextForSession(sessionID: source.sessionID, sessionTitle: detail.summary.title,
            projectID: source.projectID, taskID: source.taskID)
        var settings = await runtime.resolvedAgentLoopRequestSettings(reasoningEffort: nil)
        settings.toolScope = toolScope.sorted()
        settings.delegatedAuthority = .init(policy: policy, workingDirectory: context.workingDirectory, extraRoots: context.extraRoots)
        settings.derivedSource = source
        if source.kind == .selfImprovementProposal { settings.proposalFailureReview = failureReview }
        var config = NativeAgentLoopConfig(maxToolRounds: maxToolRounds, engine: .unified, requiresExplicitCompletion: false)
        config.completionContract = .background
        let snapshot = RunStateSnapshot(schemaVersion: 2, runID: UUID().uuidString, userTurnID: UUID().uuidString,
            loopConfig: config, model: model, requestSettings: settings)
        let state = try RunState(snapshot: snapshot)
        guard nativeDerivedWorkSourceIsCurrent(source) else { throw CancellationError() }
        try writer.authorize(minimumJournalVersion: 4)
        var admission = AgentRunMetadata(runId: state.runID, userTurnId: state.userTurnID,
            runState: try JSONValueCoder.encode(snapshot),
            admissionInstructions: AgentSessionOrchestrator.turnContextInstructions(bootstrap + "\n\n" + prompt))
        admission.derivedSource = source
        _ = try sessionStore.appendEvents(agentID: source.agentID, sessionID: source.sessionID, events: [
            .init(version: 2, agentId: source.agentID, sessionId: source.sessionID, type: .runStatus, runtimeMetadata: admission)
        ])
        return state
    }

    func nativeDerivedWorkSourceIsCurrent(_ source: NativeDerivedWorkSource, ignoringDerivedRunID: String? = nil) -> Bool {
        guard !nativeDerivedWorkIsStopping, !Task.isCancelled, toolApprovalService.hasExclusivePersistenceOwnership else { return false }
        guard let resolution = try? nativeDerivedWorkSource(agentID: source.agentID, sessionID: source.sessionID,
            ignoringDerivedRunID: ignoringDerivedRunID),
              case .owned(var current) = resolution else { return false }
        current.kind = source.kind
        return current == source
    }

    private func invokeNativeProposalTool(source: NativeDerivedWorkSource, request: ToolInvocationRequest,
        context: NativeToolExecutionContext, initialPolicy: AgentToolsPolicy?, failureReview: Bool,
        journal: SessionLoopJournal, call: AgentLoopCall, frame: ModelStepRequest) async -> AgentLoopToolOutcome {
        guard let projectID = source.projectID, let initialPolicy,
              Self.selfImprovementProposalToolAllowlist.contains(request.tool), initialPolicy.tools[request.tool] != false else {
            return .init(result: .init(tool: request.tool, ok: false,
                error: .init(code: "proposal_tool_not_allowed", message: "The saved proposal scope does not authorize this tool.", retryable: false)))
        }
        let ownershipLease = await toolApprovalService.currentOwnershipLease()
        return await ToolEffectRunner.run(toolID: request.tool, timeoutMilliseconds: 0,
            onLateResult: { result in
                defer { withExtendedLifetime(ownershipLease) {} }
                do { try await journal.appendResult(result, call: call, request: frame) }
                catch { self.logger.error("proposal.native_late_result_failed", metadata: ["error": .string(String(describing: error))]) }
            }, operation: {
                defer { withExtendedLifetime(ownershipLease) {} }
                do {
                    try Task.checkCancellation()
                    guard await self.validateDerivedEffect(source: source, request: request,
                        initialPolicy: initialPolicy, runID: context.metadata.runId) else { throw CancellationError() }
                    let events = try await self.sessionStore.loadSession(agentID: source.agentID, sessionID: source.sessionID).events
                    guard context.matches(request, events: events) else { throw CancellationError() }
                    try await context.beforeEffect()
                    try Task.checkCancellation()
                } catch {
                    return .init(result: .init(tool: request.tool, ok: false,
                        error: .init(code: "not_executed_cancelled", message: "The proposal source or policy is no longer current.", retryable: false)))
                }
                var effective = request
                if request.tool == "self_improvement.proposal_submit", failureReview { effective.arguments["failureReview"] = .bool(true) }
                return .init(result: await self.invokeSelfImprovementProposalTool(agentID: source.agentID, sessionID: source.sessionID,
                    projectID: projectID, request: effective))
            })
    }

    func invokeToolFromDerivedRuntime(source: NativeDerivedWorkSource, request: ToolInvocationRequest) async -> ToolInvocationResult {
        await invokeSessionTool(agentID: source.agentID, sessionID: source.sessionID, request: request,
            recordSessionEvents: false, requireApproval: false, chatMode: nil, nativeContext: nil, derivedSource: source).result
    }

    func validateDerivedEffect(source: NativeDerivedWorkSource, request: ToolInvocationRequest,
        initialPolicy: AgentToolsPolicy, runID: String? = nil) async -> Bool {
        guard let current = try? await toolsAuthorization.policy(agentID: source.agentID),
              NativeToolExecutionContext.authorityMatches(initialPolicy, current),
              nativeDerivedWorkSourceIsCurrent(source, ignoringDerivedRunID: runID) else { return false }
        if let scope = sessionSubagentToolAllowList[source.sessionID], !scope.contains(request.tool) { return false }
        return !Task.isCancelled
    }
}
