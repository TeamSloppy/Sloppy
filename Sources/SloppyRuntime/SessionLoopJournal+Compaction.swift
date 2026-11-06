import Foundation
import AgentRuntime
import PluginSDK
import Protocols

extension SessionLoopJournal {
    public func makeCompactionPlan(for request: ModelStepRequest, inputBudget: Int) async throws -> AgentLoopCompactionPlan? {
        try authorizeWriter()
        // A derived run projects only its own records. Its separate compactor must not
        // borrow the ordinary conversation merely because both share the same file.
        guard derivedSource == nil, inputBudget > 1_024 else { return nil }
        let journal = try store.loadJournal(agentID: agentID, sessionID: sessionID)
        let eligible = Set(SessionInputLifecycle.modelContextEvents(journal.detail.events).map(\.id))
        let estimator = TokenPressureEstimator()
        let maximumHistoryTokens = inputBudget - inputBudget / 4
        var lines: [String] = []
        var tokens = 128
        var boundary: AgentSessionJournalRecord?
        var coveredLineCount = 0
        var retained: Set<String> = []
        var artifactRefs: Set<String> = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Only whole historical transactions may enter a checkpoint. The live owner and
        // unresolved effects remain reconstructable from canonical records and retained IDs.
        for record in journal.records {
            let event = record.event
            if let metadata = event.runtimeMetadata,
               metadata.runId == request.runId || metadata.userTurnId == request.userTurnId { break }
            if event.runtimeMetadata?.derivedSource != nil { retained.insert(event.id); continue }
            var text: String?
            if let message = event.message {
                if message.uiAction != nil || message.segments.contains(where: { $0.kind != .text }) { retained.insert(event.id) }
                if eligible.contains(event.id), event.runtimeMetadata?.modelResponse == nil {
                    text = "[\(message.role.rawValue)] " + message.segments.compactMap(\.text).joined(separator: "\n")
                }
            }
            if let raw = event.runtimeMetadata?.modelResponse, event.runtimeMetadata?.auxiliaryPurpose == nil {
                let response = try JSONValueCoder.decode(ModelStepResponse.self, from: raw)
                text = "[assistant] " + response.text + response.toolCalls.map {
                    "\n[call \($0.id) \($0.name)] " + $0.rawArguments
                }.joined()
            }
            if let call = event.toolCall, event.runtimeMetadata?.providerCallId == nil {
                text = "[call \(event.id) \(call.tool)] " + String(decoding: try encoder.encode(call.arguments), as: UTF8.self)
            }
            if let output = event.toolResult {
                if let artifact = event.runtimeMetadata?.toolOutputArtifact, validateArtifact(artifact) {
                    artifactRefs.insert(artifact.downloadPath)
                    text = "[tool \(output.callEventId ?? event.id)] " + String(decoding: try encoder.encode(artifact), as: UTF8.self)
                } else {
                    text = "[tool \(output.callEventId ?? event.id)] " + String(decoding: try encoder.encode(output), as: UTF8.self)
                }
            }
            if let text {
                let cost = estimator.estimateTextTokens(text) + 16
                guard cost <= maximumHistoryTokens - tokens else { break }
                lines.append(text); tokens += cost
            }
            if event.runtimeMetadata == nil, event.toolCall == nil, event.toolResult == nil,
               event.inputRequest == nil, event.inputResponse == nil, event.inputTransitions == nil, event.runControl == nil {
                boundary = record
                coveredLineCount = lines.count
            } else if let raw = event.runtimeMetadata?.runState,
                      let snapshot = try? JSONValueCoder.decode(RunStateSnapshot.self, from: raw),
                      snapshot.phase == .settled {
                try snapshot.validate()
                boundary = record
                coveredLineCount = lines.count
            }
        }
        guard coveredLineCount >= 4, let boundary else { return nil }
        let prefix = journal.records.prefix { $0.endCursor <= boundary.endCursor }.map(\.event)
        retained.formIntersection(Set(prefix.map(\.id)))
        artifactRefs = Set(prefix.compactMap { $0.runtimeMetadata?.toolOutputArtifact?.downloadPath }).intersection(artifactRefs)
        let messages = try SessionProjection.project(journal, imageLoader: imageSegment)
            .modelMessages(imageLoader: imageSegment, artifactValidator: validateArtifact, for: request)
        return .init(checkpoint: .init(coveredCursor: boundary.endCursor, coveredThroughEventId: boundary.event.id,
                summary: "", retainedEventIds: retained.sorted(), artifactRefs: artifactRefs.sorted()), history: lines.prefix(coveredLineCount).joined(separator: "\n\n"),
            sourceDigest: ContentDigest.sha256(try encoder.encode(prefix)),
            projectedMessageIDs: Set(messages.map(\.id)),
            owner: .init(runId: request.runId, userTurnId: request.userTurnId, generation: request.generation),
            inputBudget: inputBudget)
    }

    public func commitCompaction(_ plan: AgentLoopCompactionPlan, summary: String,
        request: ModelStepRequest) async throws -> ModelStepRequest {
        try Task.checkCancellation()
        try authorizeWriter()
        guard plan.owner == .init(runId: request.runId, userTurnId: request.userTurnId, generation: request.generation),
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw compactionFailure() }
        let journal = try store.loadJournal(agentID: agentID, sessionID: sessionID)
        guard let boundary = journal.records.firstIndex(where: {
            $0.endCursor == plan.checkpoint.coveredCursor && $0.event.id == plan.checkpoint.coveredThroughEventId
        }) else { throw compactionFailure() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard ContentDigest.sha256(try encoder.encode(journal.records[...boundary].map(\.event))) == plan.sourceDigest else {
            throw compactionFailure()
        }
        var checkpoint = plan.checkpoint
        checkpoint.summary = summary
        var metadata = AgentRunMetadata(runId: request.runId, userTurnId: request.userTurnId,
            generation: request.generation, checkpoint: checkpoint)
        metadata.derivedSource = derivedSource
        let event = AgentSessionEvent(version: 2, agentId: agentID, sessionId: sessionID, type: .runStatus,
            runtimeMetadata: metadata)
        var candidate = journal
        candidate.detail.events.append(event)
        candidate.records.append(.init(startCursor: journal.cursor, endCursor: journal.cursor + 1, event: event))
        let projection = SessionProjection.project(candidate, imageLoader: imageSegment)
        var prepared = request
        let supplemental = request.messages.filter { $0.role != .system && !plan.projectedMessageIDs.contains($0.id) }
        prepared.messages = request.messages.filter { $0.role == .system } +
            (try projection.modelMessages(imageLoader: imageSegment, artifactValidator: validateArtifact, for: request)) + supplemental
        guard prepared.messages.flatMap(\.images) == request.messages.flatMap(\.images) else { throw compactionFailure() }
        guard try ModelStepContextBudget.estimate(prepared) <= plan.inputBudget else { throw compactionFailure() }
        // No marker is committed until the complete protected candidate fits. A failed summary
        // leaves the prior projection intact; all original records remain canonical either way.
        try Task.checkCancellation()
        try authorizeWriter()
        let persisted = try store.appendEvents(agentID: agentID, sessionID: sessionID, events: [event])
        await onPersisted?(persisted, [event])
        prepared.projectionRevision = String(try store.loadJournal(agentID: agentID, sessionID: sessionID).cursor)
        return prepared
    }

    private func compactionFailure() -> ModelStepFailure {
        .init(category: .context, code: "context_compaction_unavailable",
            message: "A bounded summary could not preserve the protected context. The previous projection was retained.",
            stage: .preparation)
    }
}
