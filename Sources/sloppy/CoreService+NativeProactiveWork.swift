import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime

extension CoreService {
    private static func proactiveConfigDigest(_ config: AgentConfigDetail) -> String {
        ContentDigest.sha256(Data((String(config.documents.userMarkdown.utf8.count) + ":" + config.documents.userMarkdown +
            config.documents.heartbeatMarkdown).utf8))
    }

    func runNativeProactiveReview(agentID: String, snapshots: [ProactiveSnapshot], model: String, prompt: String,
        config: AgentConfigDetail) async throws -> ProactiveAnalysisBatch {
        guard !nativeDerivedWorkIsStopping, let ownershipLease = await toolApprovalService.currentOwnershipLease() else {
            throw ProactiveHeartbeatError.modelUnavailable
        }
        defer { withExtendedLifetime(ownershipLease) {} }
        let ids = snapshots.map { $0.source.id }.sorted()
        guard ids.count == Set(ids).count else { throw ProactiveHeartbeatError.invalidReport }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let configDigest = Self.proactiveConfigDigest(config)
        let digest = ContentDigest.sha256(try encoder.encode(JSONValue.object(["snapshots": try JSONValueCoder.encode(snapshots),
            "model": .string(model), "config": .string(configDigest)])))
        let job = RunRequestSettings.ProactiveJob(sourceIDs: ids, sourceDigest: digest, configDigest: configDigest)
        let key = "proactive/" + agentID + "/" + digest
        let completed = await withNativeProactiveReservation(key: key) { [weak self] in
            guard let self else { return false }
            return await self.prepareAndRunNativeProactiveJob(agentID: agentID, model: model, prompt: prompt, job: job)
        }
        guard completed, let saved = try savedNativeProactiveJob(agentID: agentID, job: job, config: config) else {
            throw ProactiveHeartbeatError.modelUnavailable
        }
        let reports = try Self.savedProactiveReports(saved.detail, snapshot: saved.snapshot)
        guard reports.count == ids.count else { throw ProactiveHeartbeatError.missingReport }
        return .init(sessionID: saved.detail.summary.id, reports: reports)
    }

    private func withNativeProactiveReservation(key: String, operation: @escaping @Sendable () async -> Bool) async -> Bool {
        if let running = nativeDerivedReservations[key] { return await running.value }
        let task = Task { await operation() }
        nativeDerivedReservations[key] = task
        defer { nativeDerivedReservations.removeValue(forKey: key) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func resumeNativeProactiveJob(agentID: String, sessionID: String, snapshot: RunStateSnapshot) async -> Bool {
        guard let job = snapshot.requestSettings?.proactiveJob else { return false }
        return await withNativeProactiveReservation(key: "proactive/" + agentID + "/" + job.sourceDigest) { [weak self] in
            guard let self else { return false }
            return await self.executeNativeProactiveJob(agentID: agentID, sessionID: sessionID, snapshot: snapshot)
        }
    }

    private func savedNativeProactiveJob(agentID: String, job: RunRequestSettings.ProactiveJob, config: AgentConfigDetail)
        throws -> (detail: AgentSessionDetail, snapshot: RunStateSnapshot)? {
        for session in try sessionStore.listSessions(agentID: agentID, includeHeartbeat: true).filter({ $0.kind == .heartbeat }) {
            let detail = try sessionStore.loadSession(agentID: agentID, sessionID: session.id)
            guard let raw = detail.events.last(where: { !$0.isHistorical && $0.runtimeMetadata?.runState != nil })?.runtimeMetadata?.runState,
                  raw.asObject?["requestSettings"]?.asObject?["proactiveJob"] != nil else { continue }
            let snapshot = try JSONValueCoder.decode(RunStateSnapshot.self, from: raw)
            try snapshot.validate()
            guard snapshot.requestSettings?.proactiveJob == job else { continue }
            if !SessionToolRecovery.unknownEffectCallIDs(in: detail.events).isEmpty { return (detail, snapshot) }
            if snapshot.phase != .settled && snapshot.phase != .stopping { return (detail, snapshot) }
            if snapshot.canResumeProviderFailure { return (detail, snapshot) }
            // A stopped source remains owned; it must not seed a fresh job that repeats reports.
            if snapshot.toolStop != nil || snapshot.phase == .stopping { return (detail, snapshot) }
            let age = Date().timeIntervalSince(snapshot.savedAt)
            if snapshot.phase == .settled, snapshot.toolStop == nil, age >= 0,
               age < Double(max(5, config.heartbeat.intervalMinutes)) * 60,
               try Self.savedProactiveReports(detail, snapshot: snapshot).count == job.sourceIDs.count { return (detail, snapshot) }
        }
        return nil
    }

    private func prepareAndRunNativeProactiveJob(agentID: String, model: String, prompt: String,
        job: RunRequestSettings.ProactiveJob) async -> Bool {
        do {
            let config = try getAgentConfig(agentID: agentID)
            if let saved = try savedNativeProactiveJob(agentID: agentID, job: job, config: config) {
                return await executeNativeProactiveJob(agentID: agentID, sessionID: saved.detail.summary.id, snapshot: saved.snapshot)
            }
            try agentCatalogStore.protectUnifiedJournalStorage(agentID: agentID, availableModels: availableAgentModels(), minimumJournalVersion: 7)
            let session = try await createAgentSession(agentID: agentID, request: .init(title: "Attention review", kind: .heartbeat))
            let authority = await toolContextForSession(sessionID: session.id, sessionTitle: session.title, projectID: nil, taskID: nil)
            var settings = await runtime.resolvedAgentLoopRequestSettings(reasoningEffort: nil)
            settings.toolScope = ["heartbeat.report"]
            settings.delegatedAuthority = .init(policy: try await toolsAuthorization.policy(agentID: agentID),
                workingDirectory: authority.workingDirectory, extraRoots: authority.extraRoots)
            settings.proactiveJob = job
            var loopConfig = NativeAgentLoopConfig(maxToolRounds: 24, maxOutputTokens: 8_192, engine: .unified, requiresExplicitCompletion: false)
            loopConfig.completionContract = .session; loopConfig.activeMode = .ask
            let snapshot = RunStateSnapshot(schemaVersion: 2, runID: UUID().uuidString, userTurnID: UUID().uuidString,
                loopConfig: loopConfig, model: model, requestSettings: settings)
            try snapshot.validate()
            let writer = NativeJournalWriterGuard(directory: try agentCatalogStore.directoryURL(agentID: agentID))
            try writer.authorize(minimumJournalVersion: 7)
            let metadata = AgentRunMetadata(runId: snapshot.runID, userTurnId: snapshot.userTurnID,
                runState: try JSONValueCoder.encode(snapshot), admissionInstructions: AgentSessionOrchestrator.turnContextInstructions(prompt))
            _ = try sessionStore.appendEvents(agentID: agentID, sessionID: session.id, events: [
                .init(version: 2, agentId: agentID, sessionId: session.id, type: .runStatus, runtimeMetadata: metadata)
            ])
            return await executeNativeProactiveJob(agentID: agentID, sessionID: session.id, snapshot: snapshot)
        } catch {
            logger.warning("proactive.native_admission_failed", metadata: ["error": .string(String(describing: error))])
            return false
        }
    }

    private func nativeProactiveJobIsCurrent(agentID: String, sessionID: String, snapshot: RunStateSnapshot) -> Bool {
        guard !nativeDerivedWorkIsStopping, !Task.isCancelled, toolApprovalService.hasExclusivePersistenceOwnership, let job = snapshot.requestSettings?.proactiveJob,
              let config = try? getAgentConfig(agentID: agentID), config.runtime.type == .native,
              config.heartbeat.enabled, config.heartbeat.mode == .proactive,
              Self.proactiveConfigDigest(config) == job.configDigest,
              let detail = try? sessionStore.loadSession(agentID: agentID, sessionID: sessionID),
              !detail.events.contains(where: { !$0.isHistorical && ($0.runControl != nil || $0.inputTransitions != nil) }) else { return false }
        return true
    }

    private static func savedProactiveReports(_ detail: AgentSessionDetail, snapshot: RunStateSnapshot) throws -> [ProactiveReport] {
        guard let job = snapshot.requestSettings?.proactiveJob else { throw ProactiveHeartbeatError.invalidReport }
        let events = detail.events.filter { !$0.isHistorical && $0.runtimeMetadata?.runId == snapshot.runID }
        var results: [String: AgentSessionEvent] = [:]
        for event in events { if let id = event.toolResult?.callEventId { results[id] = event } }
        var reports: [String: ProactiveReport] = [:]
        for event in events {
            guard let call = event.toolCall, call.tool == "heartbeat.report", let result = results[event.id],
                  result.toolResult?.ok == true, result.toolResult?.executionOutcome?.state == .completed,
                  result.runtimeMetadata?.observationOnly != true else { continue }
            let report = try HeartbeatReportTool.decode(call.arguments)
            guard job.sourceIDs.contains(report.sourceID), reports[report.sourceID] == nil || reports[report.sourceID] == report else {
                throw ProactiveHeartbeatError.invalidReport
            }
            reports[report.sourceID] = report
        }
        return job.sourceIDs.compactMap { reports[$0] }
    }

    private func executeNativeProactiveJob(agentID: String, sessionID: String, snapshot: RunStateSnapshot) async -> Bool {
        guard let ownershipLease = await toolApprovalService.currentOwnershipLease() else { return false }
        defer { withExtendedLifetime(ownershipLease) {} }
        do {
            try snapshot.validate()
            guard nativeProactiveJobIsCurrent(agentID: agentID, sessionID: sessionID, snapshot: snapshot),
                  let job = snapshot.requestSettings?.proactiveJob, let authority = snapshot.requestSettings?.delegatedAuthority,
                  let config = snapshot.loopConfig, let model = snapshot.model else { return false }
            let writer = NativeJournalWriterGuard(directory: try agentCatalogStore.directoryURL(agentID: agentID))
            try writer.authorize(minimumJournalVersion: 7)
            let reader = SessionLoopJournal(store: sessionStore, agentID: agentID, sessionID: sessionID,
                authorizeWriter: { try writer.authorize(minimumJournalVersion: 7) }, includeResponseMessages: false)
            guard let state = try await reader.restoreRunState(userTurnID: snapshot.userTurnID) else { return false }
            var current = await state.snapshot()
            let detail = try sessionStore.loadSession(agentID: agentID, sessionID: sessionID)
            guard SessionToolRecovery.unknownEffectCallIDs(in: detail.events).isEmpty else { return false }
            if current.canResumeProviderFailure {
                try await state.resumeAfterProviderFailure()
                current = await state.snapshot()
                let frame = ModelStepRequest(runId: current.runID, userTurnId: current.userTurnID,
                    stepId: UUID().uuidString, attemptId: UUID().uuidString, model: model,
                    projectionRevision: "", cacheScope: "proactive/" + current.runID,
                    messages: [], tools: [], generation: current.generation)
                try await reader.appendRunState(current, request: frame)
            }
            let recorder = ProactiveReportRecorder(sourceIDs: Set(job.sourceIDs))
            for report in try Self.savedProactiveReports(detail, snapshot: current) {
                var args: [String: JSONValue] = ["sourceId": .string(report.sourceID), "outcome": .string(report.outcome.rawValue)]
                args["reason"] = .string(report.reason); args["evidence"] = .string(report.evidence); args["nextStep"] = .string(report.nextStep)
                guard await recorder.invoke(.init(tool: "heartbeat.report", arguments: args)).ok else { return false }
            }
            if current.phase == .settled {
                let reports = try await recorder.result()
                guard reports.count == job.sourceIDs.count, current.toolStop == nil, !current.hitToolRoundLimit else { return false }
                persistNativeProactivePresentation(agentID: agentID, sessionID: sessionID, snapshot: current, reports: reports)
                return true
            }
            guard current.phase != .stopping else { return false }
            nativeDerivedRunsBySession[sessionID, default: [:]][state.runID] = state
            defer {
                nativeDerivedRunsBySession[sessionID]?.removeValue(forKey: state.runID)
                if nativeDerivedRunsBySession[sessionID]?.isEmpty == true { nativeDerivedRunsBySession.removeValue(forKey: sessionID) }
            }
            let journal = SessionLoopJournal(store: sessionStore, agentID: agentID, sessionID: sessionID,
                authorizeWriter: { try writer.authorize(minimumJournalVersion: 7) }, includeResponseMessages: false, beforeRequest: { [weak self] in
                    guard let self, await self.nativeProactiveJobIsCurrent(agentID: agentID, sessionID: sessionID, snapshot: snapshot) else {
                        await state.cancel(); throw CancellationError()
                    }
                })
            let executor = AgentLoopToolExecutor(execute: { [weak self] call, definition, arguments, start in
                guard let self, let metadata = call.runtimeMetadata, let stepID = metadata.stepId,
                      let attemptID = metadata.attemptId, definition.toolId == "heartbeat.report" else { throw CancellationError() }
                let frame = ModelStepRequest(runId: state.runID, userTurnId: state.userTurnID, stepId: stepID,
                    attemptId: attemptID, model: model, projectionRevision: "", cacheScope: "proactive/" + state.runID,
                    messages: [], tools: [definition], generation: metadata.generation)
                let context = NativeToolExecutionContext(delegatedAuthority: authority, delegatedToolScope: ["heartbeat.report"],
                    metadata: metadata, definition: definition, beforeEffect: { [weak self] in
                        guard let self, await self.nativeProactiveJobIsCurrent(agentID: agentID, sessionID: sessionID, snapshot: snapshot) else { throw CancellationError() }
                        try await start()
                    }, proactiveReporter: { await recorder.invoke($0) }, recordLateResult: {
                        try await journal.appendResult($0, call: call, request: frame)
                    })
                return await self.invokeNativeTool(agentID: agentID, sessionID: sessionID,
                    request: .init(tool: definition.toolId, arguments: arguments), context: context, chatMode: .ask)
            })
            let channel = "agent:\(agentID):session:\(sessionID):proactivity:" + state.runID
            await runtime.setChannelToolScope(channelId: channel, toolIDs: ["heartbeat.report"])
            await runtime.setChannelBootstrap(channelId: channel, content: "Read the saved attention snapshots and report only with heartbeat.report. Do not perform other actions.")
            let hasDeclaration = modelProvider?.tools.contains { $0.name == "heartbeat.report" } == true
            _ = await runtime.postMessage(channelId: channel, request: .init(userId: "system_proactivity", content: "Continue the saved source review.", model: model),
                onResponseChunk: { _ in true }, forceInlineResponse: true, nativeLoopConfig: config, runState: state,
                agentLoopServices: .init(journal: journal, executor: executor, additionalTools: hasDeclaration ? [] : [Self.nativeProactiveReportDefinition]))
            await runtime.discardEphemeralCheckpointChannel(channelId: channel)
            let final = await state.snapshot()
            guard final.phase == .settled, final.toolStop == nil, !final.hitToolRoundLimit else { return false }
            let reports = try await recorder.result()
            guard reports.count == job.sourceIDs.count,
                  nativeProactiveJobIsCurrent(agentID: agentID, sessionID: sessionID, snapshot: snapshot) else { return false }
            persistNativeProactivePresentation(agentID: agentID, sessionID: sessionID, snapshot: final, reports: reports)
            return true
        } catch {
            logger.warning("proactive.native_run_failed", metadata: ["error": .string(String(describing: error))])
            return false
        }
    }

    private func persistNativeProactivePresentation(agentID: String, sessionID: String, snapshot: RunStateSnapshot, reports: [ProactiveReport]) {
        let id = "proactive-presentation-" + snapshot.runID
        guard let detail = try? sessionStore.loadSession(agentID: agentID, sessionID: sessionID),
              !detail.events.contains(where: { $0.id == id }) else { return }
        let text = reports.filter { $0.outcome != .quiet }.map { "\($0.reason)\n\($0.evidence)\n\($0.nextStep)" }.joined(separator: "\n\n")
        appendProactiveSessionEvents(agentID: agentID, sessionID: sessionID, events: [
            .init(id: id, version: 2, agentId: agentID, sessionId: sessionID, type: .message,
                runtimeMetadata: .init(runId: snapshot.runID, userTurnId: snapshot.userTurnID,
                    generation: snapshot.generation, presentationOnly: true),
                message: .init(role: .assistant, segments: [.init(kind: .text, text: text.isEmpty ? "No action needed." : text)]))
        ])
    }

    private static var nativeProactiveReportDefinition: ModelStepToolDefinition {
        let properties = Dictionary(uniqueKeysWithValues: ["sourceId", "outcome", "reason", "evidence", "nextStep"].map {
            ($0, JSONValue.object(["type": .string("string")]))
        })
        return .init(name: "heartbeat_report", toolId: "heartbeat.report", description: "Report one supplied source without taking other actions.",
            parameters: .object(["type": .string("object"), "properties": .object(properties),
                "required": .array([.string("sourceId"), .string("outcome")]), "additionalProperties": .bool(false)]))
    }
}
