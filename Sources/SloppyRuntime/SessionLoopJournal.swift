import Foundation
import AgentRuntime
import AnyLanguageModel
import PluginSDK
import Protocols

/// Core supplies its verified downgrade guard; standalone must supply an isolated compatible store.
/// Construction alone does not grant write access. Authorization is checked on every operation.
public struct SessionLoopJournal: AgentLoopStateJournal, AgentLoopInstructionJournal, AgentLoopOutcomeJournal, AgentLoopUsageJournal, AgentLoopProjectionJournal, AgentLoopInputJournal, AgentLoopPendingToolJournal {
    public let store: AgentSessionFileStore
    public let agentID: String
    public let sessionID: String
    public let includeResponseMessages: Bool
    public let derivedSource: AgentDerivedWorkSource?
    public let beforeRequest: (@Sendable () async throws -> Void)?
    public let onPersisted: (@Sendable (AgentSessionSummary, [AgentSessionEvent]) async -> Void)?
    public let authorizeWriter: @Sendable () throws -> Void

    private let externalizeToolOutputs: Bool
    public init(store: AgentSessionFileStore, agentID: String, sessionID: String,
                authorizeWriter: @escaping @Sendable () throws -> Void,
                includeResponseMessages: Bool = true,
                derivedSource: AgentDerivedWorkSource? = nil,
                beforeRequest: (@Sendable () async throws -> Void)? = nil,
                externalizeToolOutputs: Bool = true,
                onPersisted: (@Sendable (AgentSessionSummary, [AgentSessionEvent]) async -> Void)? = nil) {
        self.externalizeToolOutputs = externalizeToolOutputs
        self.store = store
        self.agentID = agentID
        self.sessionID = sessionID
        self.authorizeWriter = authorizeWriter
        self.includeResponseMessages = includeResponseMessages
        self.derivedSource = derivedSource
        self.beforeRequest = beforeRequest
        self.onPersisted = onPersisted
    }

    public func prepareRequest(_ request: ModelStepRequest) async throws -> ModelStepRequest {
        try await beforeRequest?()
        try authorizeWriter()
        let journal = try store.loadJournal(agentID: agentID, sessionID: sessionID)
        return try await prepareRequest(request, journal: journal, excludingUserMessageIDs: [])
    }

    public func prepareRequest(_ request: ModelStepRequest, journal: AgentSessionJournalSnapshot,
        excludingUserMessageIDs: Set<String>) async throws -> ModelStepRequest {
        try authorizeWriter()
        guard journal.detail.summary.agentId == agentID.trimmingCharacters(in: .whitespacesAndNewlines),
              journal.detail.summary.id == sessionID.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AgentSessionFileStore.StoreError.invalidPayload
        }
        let imageLoader: (AgentAttachment) -> Transcript.ImageSegment? = imageSegment
        let projection = SessionProjection.project(journal, imageLoader: imageLoader)
        var prepared = request
        prepared.messages = request.messages.filter { $0.role == .system } + (try projection.modelMessages(imageLoader: imageLoader,
            artifactValidator: validateArtifact, for: request, excludingUserMessageIDs: excludingUserMessageIDs))
        prepared.projectionRevision = String(projection.journal.cursor)
        prepared.reconciliationCallEventIDs = SessionToolRecovery.unknownEffectCallIDs(in: projection.journal.detail.events)
        prepared.requiresReconciliation = !prepared.reconciliationCallEventIDs.isEmpty
        return prepared
    }

    func imageSegment(_ attachment: AgentAttachment) -> Transcript.ImageSegment? {
        guard let url = try? store.resolveAttachmentFileURL(agentID: agentID, attachment: attachment),
              let data = try? Data(contentsOf: url) else { return nil }
        return .init(data: data, mimeType: attachment.mimeType)
    }

    func validateArtifact(_ artifact: AgentToolOutputArtifact) -> Bool {
        guard artifact.agentId == agentID, artifact.sessionId == sessionID else { return false }
        return (try? store.verifyToolOutputArtifact(artifact)) != nil
    }

    public func pendingToolBatch(for request: ModelStepRequest) async throws -> AgentLoopPendingTools? {
        try authorizeWriter()
        let events = try store.loadSession(agentID: agentID, sessionID: sessionID).events.filter { !$0.isHistorical }
        guard let responseEvent = events.last(where: { $0.runtimeMetadata?.runId == request.runId &&
            $0.runtimeMetadata?.userTurnId == request.userTurnId && $0.runtimeMetadata?.generation == request.generation &&
            $0.runtimeMetadata?.derivedSource == derivedSource && $0.runtimeMetadata?.modelResponse != nil &&
            $0.runtimeMetadata?.auxiliaryPurpose == nil }),
              let metadata = responseEvent.runtimeMetadata, let raw = metadata.modelResponse,
              let step = metadata.stepId, let attempt = metadata.attemptId else { return nil }
        let response = try JSONValueCoder.decode(ModelStepResponse.self, from: raw)
        guard response.stopReason == .toolCalls, !response.toolCalls.isEmpty else { return nil }
        let starts = Set(events.filter { $0.runtimeMetadata?.executionPhase == .started }.compactMap(\.runtimeMetadata?.callEventId))
        let results = Set(events.compactMap(\.toolResult?.callEventId))
        var calls: [AgentLoopCall] = []
        for (index, call) in response.toolCalls.enumerated() {
            guard let original = events.first(where: { $0.type == .toolCall && $0.runtimeMetadata?.executionPhase == .requested &&
                $0.runtimeMetadata?.runId == request.runId && $0.runtimeMetadata?.userTurnId == request.userTurnId &&
                $0.runtimeMetadata?.generation == request.generation && $0.runtimeMetadata?.stepId == step &&
                $0.runtimeMetadata?.attemptId == attempt && $0.runtimeMetadata?.sourceOrder == index &&
                $0.runtimeMetadata?.providerCallId == call.id && $0.runtimeMetadata?.callEventId == $0.id }),
                  !starts.contains(original.id), !results.contains(original.id) else { continue }
            calls.append(.init(eventID: original.id, sourceOrder: index, call: call, runtimeMetadata: original.runtimeMetadata))
        }
        guard !calls.isEmpty else { return nil }
        var frame = request
        frame.stepId = step; frame.attemptId = attempt; frame.purpose = .work
        return .init(request: frame, response: response, calls: calls)
    }

    public func appendRunState(_ snapshot: RunStateSnapshot, request: ModelStepRequest) async throws {
        try snapshot.validate()
        var metadata = metadata(request)
        metadata.generation = snapshot.generation
        if snapshot.phase == .stopping || snapshot.phase == .settled {
            // Terminal checkpoints belong to the run, including a pre-start cancellation
            // or a restored completion that does not issue another model step.
            metadata.stepId = nil
            metadata.attemptId = nil
        }
        metadata.runState = try JSONValueCoder.encode(snapshot)
        var events: [AgentSessionEvent] = [.init(version: 2, agentId: agentID, sessionId: sessionID, type: .runStatus, runtimeMetadata: metadata)]
        if derivedSource == nil, snapshot.phase == .settled || snapshot.phase == .stopping {
            let inputs = try SessionInputLifecycle.states(in: store.loadSession(agentID: agentID, sessionID: sessionID).events)
            for id in inputs.keys.sorted() {
                guard let input = inputs[id], let owner = input.owner,
                      input.context.request.deliveryIntent == .steering, input.latest.delivery != .delivered,
                      owner.runId == snapshot.runID, owner.userTurnId == snapshot.userTurnID else { continue }
                var receipt = AgentRunMetadata(runId: snapshot.runID, userTurnId: snapshot.userTurnID, generation: snapshot.generation)
                receipt.inputMessageId = id; receipt.requestFingerprint = input.latest.fingerprint
                events.append(.init(version: 3, agentId: agentID, sessionId: sessionID, type: .runStatus,
                    runtimeMetadata: receipt, inputTransitions: [.init(messageId: id, fingerprint: input.latest.fingerprint,
                        disposition: .admitted, delivery: .delivered, owner: owner)]))
            }
        }
        try await append(events)
        if snapshot.phase == .settled, externalizeToolOutputs {
            _ = try? store.cleanupToolOutputArtifacts(agentID: agentID, sessionID: sessionID,
                olderThan: Date().addingTimeInterval(-86_400))
        }
    }

    public func admitSteering(_ request: ModelStepRequest, state: RunState) async throws -> Bool {
        guard derivedSource == nil else { return false }
        return try await state.atInputBoundary(generation: request.generation) { snapshot in
            try authorizeWriter()
            let detail = try store.loadSession(agentID: agentID, sessionID: sessionID)
            let inputs = try SessionInputLifecycle.states(in: detail.events)
            var events: [AgentSessionEvent] = []
            for event in detail.events where !event.isHistorical {
                guard let id = event.message?.id, let input = inputs[id], input.latest.disposition == .queued,
                      input.context.request.deliveryIntent == .steering else { continue }
                // Steering changes the task context, never model/configuration or delegated authority.
                guard input.context.peerOrigin == nil, input.context.uiSubmission == nil,
                      input.context.request.selectedModel == nil, input.context.request.mode == nil,
                      input.context.request.reasoningEffort == nil else {
                    events.append(.init(version: 3, agentId: agentID, sessionId: sessionID, type: .runStatus,
                        inputTransitions: [.init(messageId: id, fingerprint: input.latest.fingerprint,
                            disposition: .failed, delivery: .delivered)]))
                    continue
                }
                _ = try SessionInputCapture.materialize(input.context, store: store, agentID: agentID, sessionID: sessionID)
                var metadata = AgentRunMetadata(runId: snapshot.runID, userTurnId: snapshot.userTurnID,
                    generation: snapshot.generation, inputMessageId: id, requestFingerprint: input.latest.fingerprint)
                metadata.runState = try JSONValueCoder.encode(snapshot)
                events.append(.init(version: 3, agentId: agentID, sessionId: sessionID, type: .runStatus,
                    runtimeMetadata: metadata, inputTransitions: [.init(messageId: id, fingerprint: input.latest.fingerprint,
                        disposition: .admitted, owner: .init(runId: snapshot.runID, userTurnId: snapshot.userTurnID,
                            generation: snapshot.generation))]))
            }
            guard !events.isEmpty else { return false }
            _ = try store.appendEvents(agentID: agentID, sessionID: sessionID, events: events)
            return events.contains { $0.runtimeMetadata != nil }
        }
    }

    public func appendInstruction(_ instruction: AgentRunInstruction, request: ModelStepRequest) async throws {
        var metadata = metadata(request)
        metadata.instruction = instruction
        try await append([.init(id: instruction.id, version: 2, agentId: agentID, sessionId: sessionID,
            type: .runStatus, runtimeMetadata: metadata)])
    }

    public func restoreRunState(userTurnID: String? = nil) async throws -> RunState? {
        try authorizeWriter()
        let journal = try store.loadJournal(agentID: agentID, sessionID: sessionID)
        guard let index = journal.records.lastIndex(where: {
            !$0.event.isHistorical && $0.event.runtimeMetadata?.runState != nil &&
                $0.event.runtimeMetadata?.derivedSource == derivedSource &&
                (userTurnID == nil || $0.event.runtimeMetadata?.userTurnId == userTurnID)
        }), let metadata = journal.records[index].event.runtimeMetadata, let raw = metadata.runState else { return nil }
        let snapshot = try JSONValueCoder.decode(RunStateSnapshot.self, from: raw)
        let state = try RunState(snapshot: snapshot)
        if Self.hasDurableInterrupt(for: snapshot, records: journal.records) {
            await state.cancel()
            return state
        }
        guard snapshot.completion == nil, snapshot.phase != .stopping, snapshot.phase != .settled else { return state }
        let tail = journal.records.dropFirst(index + 1).map(\.event).filter {
            !$0.isHistorical && $0.runtimeMetadata?.runId == snapshot.runID &&
                $0.runtimeMetadata?.userTurnId == snapshot.userTurnID && $0.runtimeMetadata?.generation == snapshot.generation
        }
        for event in tail where event.runtimeMetadata?.executionPhase == .started {
            if let revision = event.runtimeMetadata?.workScopeRevision { try await state.restoreWorkRevision(revision) }
        }
        var latestResults: [String: String] = [:]
        for event in tail {
            if let callID = event.toolResult?.callEventId { latestResults[callID] = event.id }
        }
        // A late scalar observation may resolve an unknown effect, but cannot erase the
        // original run's policy stop or grant product verification authority.
        var latestAuthoritativeResults: [String: String] = [:]
        for event in tail where event.runtimeMetadata?.observationOnly == false {
            if let callID = event.toolResult?.callEventId { latestAuthoritativeResults[callID] = event.id }
        }
        for event in tail {
            guard let result = event.toolResult, let callID = result.callEventId,
                  latestAuthoritativeResults[callID] == event.id else { continue }
            let started = try hasCommittedStart(event, records: journal.records)
            try await state.restoreSettledObservation(.init(tool: result.tool, ok: result.ok,
                data: result.data, error: result.error, durationMs: result.durationMs ?? 0),
                callID: callID, generation: snapshot.generation)
            if started, result.ok, result.tool == "planning.select_route",
               result.executionOutcome?.state == .completed,
               let rawMode = result.data?.asObject?["mode"]?.asString {
                let mode: AgentChatMode
                if rawMode == "skill" { mode = .auto }
                else if let saved = AgentChatMode(rawValue: rawMode) { mode = saved }
                else { throw AgentSessionFileStore.StoreError.invalidPayload }
                try await state.selectMode(mode, generation: snapshot.generation)
            }
            for rawEvidence in event.runtimeMetadata?.verificationEvidence ?? [] {
                guard started, result.ok, result.executionOutcome?.state == .completed else {
                    throw AgentSessionFileStore.StoreError.invalidPayload
                }
                let evidence = try JSONValueCoder.decode(VerificationEvidence.self, from: rawEvidence)
                if let existing = await state.verificationEvidence.first(where: { $0.id == evidence.id }) {
                    guard existing == evidence else { throw AgentSessionFileStore.StoreError.invalidPayload }
                } else {
                    guard await state.recordEvidence(evidence).id == evidence.id else {
                        throw AgentSessionFileStore.StoreError.invalidPayload
                    }
                }
            }
        }
        for event in tail {
            guard let candidateMetadata = event.runtimeMetadata, let rawCandidate = candidateMetadata.completionCandidate else { continue }
            guard let result = event.toolResult, result.ok, result.executionOutcome?.state == .completed,
                  let callID = result.callEventId, candidateMetadata.callEventId == callID,
                  candidateMetadata.executionPhase == .settled, candidateMetadata.observationOnly != true,
                  candidateMetadata.completionPolicyVersion == 1, latestResults[callID] == event.id,
                  snapshot.loopConfig?.finalizerToolNames.contains(result.tool) == true,
                  let resultIndex = journal.records.firstIndex(where: { $0.event.id == event.id }),
                  let requestedIndex = journal.records[..<resultIndex].lastIndex(where: {
                      $0.event.id == callID && !$0.event.isHistorical && $0.event.type == .toolCall &&
                          $0.event.toolCall?.tool == result.tool && $0.event.runtimeMetadata?.executionPhase == .requested &&
                          sameInvocation($0.event.runtimeMetadata, candidateMetadata)
                  }), journal.records[(requestedIndex + 1)..<resultIndex].contains(where: {
                      !$0.event.isHistorical && $0.event.runtimeMetadata?.executionPhase == .started &&
                          sameInvocation($0.event.runtimeMetadata, candidateMetadata)
                  }) else { throw AgentSessionFileStore.StoreError.invalidPayload }
            let candidate = try JSONValueCoder.decode(RunCompletion.self, from: rawCandidate)
            guard !candidate.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  await state.acceptCompletion(candidate, generation: snapshot.generation) else {
                throw AgentSessionFileStore.StoreError.invalidPayload
            }
            break
        }
        return state
    }

    /// Older controls have no runtime envelope. Their typed position binds them to the
    /// live accepted input at that point; queued user receipts do not change that owner.
    private static func hasDurableInterrupt(for snapshot: RunStateSnapshot,
        records: [AgentSessionJournalRecord]) -> Bool {
        var currentRun: String?
        var currentTurn: String?
        for record in records where !record.event.isHistorical {
            let event = record.event
            if let metadata = event.runtimeMetadata, metadata.requestFingerprint != nil {
                currentRun = metadata.runId
                currentTurn = metadata.userTurnId
            }
            guard event.type == .runControl, let control = event.runControl,
                  control.action == .interrupt || control.action == .interruptTree else { continue }
            if let metadata = event.runtimeMetadata {
                if metadata.runId == snapshot.runID, metadata.userTurnId == snapshot.userTurnID { return true }
            } else if currentRun == snapshot.runID, currentTurn == snapshot.userTurnID { return true }
        }
        return false
    }

    private func hasCommittedStart(_ event: AgentSessionEvent, records: [AgentSessionJournalRecord]) throws -> Bool {
        guard event.type == .toolResult, let metadata = event.runtimeMetadata, metadata.executionPhase == .settled,
              metadata.observationOnly == false, let result = event.toolResult,
              let callID = result.callEventId, metadata.callEventId == callID,
              let resultIndex = records.firstIndex(where: { $0.event.id == event.id }),
              let requestedIndex = records[..<resultIndex].lastIndex(where: {
                  !$0.event.isHistorical && $0.event.id == callID && $0.event.type == .toolCall &&
                      $0.event.toolCall?.tool == result.tool && $0.event.runtimeMetadata?.executionPhase == .requested &&
                      sameInvocation($0.event.runtimeMetadata, metadata)
              }) else { throw AgentSessionFileStore.StoreError.invalidPayload }
        return records[(requestedIndex + 1)..<resultIndex].contains(where: {
            !$0.event.isHistorical && $0.event.runtimeMetadata?.executionPhase == .started &&
                sameInvocation($0.event.runtimeMetadata, metadata)
        })
    }

    private func sameInvocation(_ lhs: AgentRunMetadata?, _ rhs: AgentRunMetadata) -> Bool {
        guard let lhs, lhs.stepId != nil, lhs.attemptId != nil, lhs.sourceOrder != nil,
              lhs.providerCallId?.isEmpty == false, lhs.callEventId != nil else { return false }
        return lhs.runId == rhs.runId && lhs.userTurnId == rhs.userTurnId && lhs.generation == rhs.generation &&
            lhs.stepId == rhs.stepId && lhs.attemptId == rhs.attemptId && lhs.sourceOrder == rhs.sourceOrder &&
            lhs.providerCallId == rhs.providerCallId && lhs.callEventId == rhs.callEventId
    }
    public func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) async throws {
        try await appendModelResponse(response, request: request, usageRequest: nil)
    }

    public func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest, usageRequest: UsageRequestRecord) async throws {
        guard usageRequest.agentId == nil || usageRequest.agentId == agentID,
              usageRequest.sessionId == nil || usageRequest.sessionId == sessionID else { throw AgentSessionFileStore.StoreError.invalidPayload }
        var record = usageRequest
        record.agentId = agentID
        record.sessionId = sessionID
        try await appendModelResponse(response, request: request, usageRequest: record)
    }

    private func appendModelResponse(_ response: ModelStepResponse, request: ModelStepRequest, usageRequest: UsageRequestRecord?) async throws {
        var metadata = metadata(request)
        metadata.modelResponse = try JSONValueCoder.encode(response)
        if let usageRequest {
            metadata.schemaVersion = 2
            metadata.usageRequest = usageRequest
        }
        let planning = request.purpose == .planning
        if planning || request.purpose == .reportReview || request.purpose == .compaction {
            metadata.presentationOnly = true
            metadata.auxiliaryPurpose = planning ? .planning : (request.purpose == .compaction ? .compaction : .reportReview)
        }
        var events: [AgentSessionEvent] = [.init(id: "model-response-" + request.stepId, version: 2, agentId: agentID, sessionId: sessionID,
            type: includeResponseMessages ? .message : .runStatus, runtimeMetadata: metadata,
            message: includeResponseMessages ? .init(role: .assistant, segments: [.init(kind: .text, text: response.text)]) : nil)]
        if planning, response.stopReason == .endTurn, response.toolCalls.isEmpty,
           !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let instruction = Self.plannerInstruction(response.text, runID: request.runId)
            var context = self.metadata(request)
            context.instruction = instruction
            events.append(.init(id: instruction.id, version: 2, agentId: agentID, sessionId: sessionID,
                type: .runStatus, runtimeMetadata: context))
        }
        try await append(events)
    }

    public static func plannerInstruction(_ text: String, runID: String) -> AgentRunInstruction {
        .init(id: "planner-output-" + runID, kind: .turnContext,
            text: "[Planner output]\n" + String(decoding: text.utf8.prefix(6_000), as: UTF8.self))
    }
    public func appendRequested(_ calls: [AgentLoopCall], request: ModelStepRequest) async throws {
        try await append(calls.map { call in
            var metadata = metadata(request, call: call)
            metadata.executionPhase = .requested
            let arguments = call.call.rawArguments.data(using: .utf8).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }?.asObject
            return .init(id: call.eventID, version: 2, agentId: agentID, sessionId: sessionID,
                type: .toolCall, runtimeMetadata: metadata,
                toolCall: .init(tool: nativeToolID(call, request: request), arguments: arguments ?? [:]))
        })
    }
    public func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) async throws {
        var metadata = metadata(request, call: call)
        metadata.executionPhase = .started
        try await append([.init(version: 2, agentId: agentID, sessionId: sessionID, type: .runStatus, runtimeMetadata: metadata)])
    }
    public func appendOutcome(_ outcome: AgentLoopToolOutcome, call: AgentLoopCall, request: ModelStepRequest) async throws {
        try await appendToolResult(outcome.result, completion: outcome.completion,
            evidence: outcome.verificationEvidence, observationOnly: false, call: call, request: request)
    }

    public func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) async throws {
        try await appendToolResult(result, completion: nil, evidence: nil, observationOnly: true, call: call, request: request)
    }

    private func appendToolResult(_ result: ToolInvocationResult, completion: RunCompletion?, evidence: [VerificationEvidence]?, observationOnly: Bool,
        call: AgentLoopCall, request: ModelStepRequest) async throws {
        var metadata = metadata(request, call: call)
        metadata.executionPhase = .settled
        metadata.observationOnly = observationOnly
        metadata.completionCandidate = try completion.map { try JSONValueCoder.encode($0) }
        metadata.verificationEvidence = try evidence.map { try $0.map { try JSONValueCoder.encode($0) } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let outputBytes = try encoder.encode(result)
        if outputBytes.count > 16_384, externalizeToolOutputs {
            try authorizeWriter()
            metadata.toolOutputArtifact = try store.persistToolOutputArtifact(agentID: agentID, sessionID: sessionID,
                callEventID: call.eventID, bytes: outputBytes)
        } else if outputBytes.count > 16_384, outputBytes.count <= 25 * 1_024 * 1_024,
           completion == nil, evidence?.isEmpty != false {
            try authorizeWriter()
            let attachments = try store.persistAttachments(agentID: agentID, sessionID: sessionID, uploads: [
                .init(name: "tool-output.json", mimeType: "application/json", sizeBytes: outputBytes.count,
                    contentBase64: outputBytes.base64EncodedString())
            ])
            guard let attachment = attachments.first else { throw AgentSessionFileStore.StoreError.invalidPayload }
            metadata.toolOutputArtifact = .init(agentId: agentID, sessionId: sessionID, callEventId: call.eventID,
                attachment: attachment, sha256: ContentDigest.sha256(outputBytes))
        }
        let unknown = result.error?.code == "tool_execution_interrupted"
        let event = AgentSessionEvent(version: 2, agentId: agentID, sessionId: sessionID, type: .toolResult,
            runtimeMetadata: metadata, toolResult: .init(tool: nativeToolID(call, request: request), ok: result.ok,
                data: result.data, error: result.error, durationMs: result.durationMs, callEventId: call.eventID,
                executionOutcome: .init(state: unknown ? .interrupted : (result.ok ? .completed : .failed),
                    category: unknown ? .unknown : (result.ok ? nil : .tool), code: result.error?.code,
                    requiresReconciliation: unknown)))
        try authorizeWriter()
        if let summary = try store.appendRuntimeToolResult(agentID: agentID, sessionID: sessionID, event: event) {
            await onPersisted?(summary, [event])
        }
    }

    private func metadata(_ request: ModelStepRequest, call: AgentLoopCall? = nil) -> AgentRunMetadata {
        var metadata = AgentRunMetadata(runId: request.runId, userTurnId: request.userTurnId, stepId: request.stepId,
            attemptId: request.attemptId, generation: request.generation, sourceOrder: call?.sourceOrder,
            providerCallId: call?.call.id, callEventId: call?.eventID)
        metadata.derivedSource = derivedSource
        metadata.workScopeRevision = call?.runtimeMetadata?.workScopeRevision
        return metadata
    }

    private func nativeToolID(_ call: AgentLoopCall, request: ModelStepRequest) -> String {
        request.tools.first(where: { $0.name == call.call.name })?.toolId ?? call.call.name
    }

    private func append(_ events: [AgentSessionEvent]) async throws {
        try authorizeWriter()
        let summary = try store.appendEvents(agentID: agentID, sessionID: sessionID, events: events)
        await onPersisted?(summary, events)
    }
}
