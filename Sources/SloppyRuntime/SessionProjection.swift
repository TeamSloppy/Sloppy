import Foundation
import AnyLanguageModel
import PluginSDK
import Protocols

public struct AgentSessionJournalRecord: Sendable, Equatable {
    public var startCursor: UInt64
    public var endCursor: UInt64
    public var event: AgentSessionEvent

    public init(startCursor: UInt64, endCursor: UInt64, event: AgentSessionEvent) {
        self.startCursor = startCursor
        self.endCursor = endCursor
        self.event = event
    }
}

public struct AgentSessionJournalSnapshot: Sendable {
    public var detail: AgentSessionDetail
    public var records: [AgentSessionJournalRecord]
    public var cursor: UInt64

    public init(detail: AgentSessionDetail, records: [AgentSessionJournalRecord], cursor: UInt64) {
        self.detail = detail
        self.records = records
        self.cursor = cursor
    }
}

/// A disposable model view reconstructed from the journal. Legacy journals use the existing builder.
public struct SessionProjection: Sendable {
    public var journal: AgentSessionJournalSnapshot
    public var projectedEvents: [AgentSessionEvent]
    public var transcript: Transcript

    /// Model history is rebuilt from durable final responses, never from streamed presentation text.
    public func modelMessages(imageLoader: ((AgentAttachment) -> Transcript.ImageSegment?)? = nil,
                              artifactValidator: ((AgentToolOutputArtifact) -> Bool)? = nil,
                              for request: ModelStepRequest? = nil,
                              excludingUserMessageIDs: Set<String> = []) throws -> [ModelStepMessage] {
        let derivedSource = request.flatMap { request in
            journal.detail.events.first { !$0.isHistorical && $0.runtimeMetadata?.runId == request.runId &&
                $0.runtimeMetadata?.userTurnId == request.userTurnId && $0.runtimeMetadata?.derivedSource != nil }?.runtimeMetadata?.derivedSource
        }
        let scopedEvents = projectedEvents.filter { event in
            if let derivedSource, let request {
                return !event.isHistorical && event.runtimeMetadata?.derivedSource == derivedSource &&
                    event.runtimeMetadata?.runId == request.runId && event.runtimeMetadata?.userTurnId == request.userTurnId
            }
            return event.runtimeMetadata?.derivedSource == nil
        }
        let events = Self.orderAcceptedInputs(SessionInputLifecycle.modelContextEvents(scopedEvents, canonical: journal.detail.events).filter { event in
            // These IDs describe pending live inputs, not the copied history of another session.
            guard !event.isHistorical, let message = event.message, message.role == .user else { return true }
            return !excludingUserMessageIDs.contains(message.id)
        })
        // The next model step must see the full current observation. An artifact can replace
        // it only after a later work response proves the model has consumed that tool batch.
        let currentResponseID = events.last(where: { $0.runtimeMetadata?.modelResponse != nil &&
            $0.runtimeMetadata?.auxiliaryPurpose == nil })?.id
        let recovered = events + SessionToolRecovery.interruptionEvents(for: journal.detail)
        var latestResults: [String: AgentToolResultEvent] = [:]
        var artifacts: [String: AgentToolOutputArtifact] = [:]
        var requested: [CallKey: AgentSessionEvent] = [:]
        for event in recovered where !event.isHistorical {
            if let result = event.toolResult, let id = result.callEventId {
                latestResults[id] = result
                if event.runtimeMetadata?.completionCandidate == nil,
                   event.runtimeMetadata?.verificationEvidence?.isEmpty != false {
                    artifacts[id] = event.runtimeMetadata?.toolOutputArtifact
                }
            }
            if event.type == .toolCall, let metadata = event.runtimeMetadata, let step = metadata.stepId,
               let providerCall = metadata.providerCallId {
                requested[CallKey(run: metadata.runId, step: step, call: providerCall)] = event
            }
        }
        var result: [ModelStepMessage] = []
        let outputEncoder = JSONEncoder()
        outputEncoder.outputFormatting = [.sortedKeys]
        var legacy: [AgentSessionEvent] = []
        func flushLegacy() {
            guard !legacy.isEmpty else { return }
            var detail = journal.detail
            detail.events = legacy
            let transcript = AgentSessionTranscriptBuilder.buildRecoveryTranscript(current: detail, imageLoader: imageLoader)
            let prefix = "legacy-" + legacy[0].id
            for (index, entry) in transcript.enumerated() {
                let id = "\(prefix)-\(index)"
                switch entry {
                case .instructions: break
                case .prompt(let prompt): result.append(Self.message(id: id, role: .user, segments: prompt.segments))
                case .response(let response): result.append(Self.message(id: id, role: .assistant, segments: response.segments))
                case .toolCalls(let calls):
                    result.append(.init(id: id, role: .assistant, toolCalls: calls.map {
                        .init(id: $0.id, name: $0.toolName, rawArguments: $0.arguments.jsonString)
                    }))
                case .toolOutput(let output):
                    result.append(.init(id: id, role: .tool, toolOutput: .init(callId: output.id,
                        name: output.toolName, content: Self.message(id: id, role: .tool, segments: output.segments).text,
                        isError: latestResults[output.id].map { !$0.ok })))
                }
            }
            legacy.removeAll(keepingCapacity: true)
        }
        for event in events {
            if !event.isHistorical, event.runtimeMetadata?.presentationOnly == true { continue }
            if !event.isHistorical, let metadata = event.runtimeMetadata, let instruction = metadata.instruction {
                flushLegacy()
                if let request, metadata.runId == request.runId, metadata.userTurnId == request.userTurnId,
                   metadata.generation == request.generation {
                    result.append(.init(id: instruction.id, role: .user, text: instruction.text))
                }
            } else if !event.isHistorical, let metadata = event.runtimeMetadata, let raw = metadata.modelResponse {
                flushLegacy()
                let response = try JSONValueCoder.decode(ModelStepResponse.self, from: raw)
                result.append(.init(id: event.id, role: .assistant, text: response.text,
                    toolCalls: response.toolCalls, continuation: response.continuation))
                // Disk completion order remains untouched. Model order follows the original assistant batch.
                for call in response.toolCalls {
                    let requestedEvent = metadata.stepId.flatMap { requested[CallKey(run: metadata.runId, step: $0, call: call.id)] }
                    var output = requestedEvent.flatMap { latestResults[$0.id] } ?? AgentToolResultEvent(
                        tool: call.name, ok: false, error: .init(code: "tool_not_started",
                            message: "The assistant response was saved, but this invocation was never requested or started.", retryable: true))
                    if event.id != currentResponseID, let id = requestedEvent?.id, let artifact = artifacts[id], artifact.callEventId == id,
                       artifactValidator?(artifact) == true {
                        var reference = try JSONValueCoder.encode(artifact).asObject ?? [:]
                        reference["downloadPath"] = .string(artifact.downloadPath)
                        output.data = .object(["outputArchived": .bool(true), "artifact": .object(reference)])
                    }
                    result.append(.init(id: "model-output-" + (requestedEvent?.id ?? event.id + "-" + call.id), role: .tool,
                        toolOutput: .init(callId: call.id, name: call.name,
                            content: String(decoding: try outputEncoder.encode(output), as: UTF8.self), isError: !output.ok)))
                }
            } else if !event.isHistorical, event.runtimeMetadata?.stepId != nil,
                      event.type == .toolCall || event.type == .toolResult || event.runtimeMetadata?.executionPhase != nil {
                continue
            } else {
                legacy.append(event)
            }
            if !event.isHistorical, let metadata = event.runtimeMetadata,
               let instructions = metadata.admissionInstructions, let request,
               metadata.runId == request.runId, metadata.userTurnId == request.userTurnId,
               metadata.generation == request.generation {
                // The user row must precede its scoped context, including after prefix recovery.
                flushLegacy()
                result += instructions.map { .init(id: $0.id, role: .user, text: $0.text) }
            }
        }
        flushLegacy()
        return result
    }

    /// Queue receipt order stays on disk; model history introduces each accepted input
    /// at its admission boundary, after the previous task's responses and results.
    private static func orderAcceptedInputs(_ events: [AgentSessionEvent]) -> [AgentSessionEvent] {
        var users: [String: Int] = [:]
        var admissions: [String: Int] = [:]
        for (index, event) in events.enumerated() where !event.isHistorical {
            if let message = event.message, message.role == .user, users[message.id] == nil {
                users[message.id] = index
            }
            if let metadata = event.runtimeMetadata, metadata.requestFingerprint != nil {
                let inputID = metadata.inputMessageId ?? metadata.userTurnId
                if admissions[inputID] == nil { admissions[inputID] = index }
            }
        }
        var deferred: Set<Int> = []
        var atAdmission: [Int: AgentSessionEvent] = [:]
        for (inputID, admission) in admissions {
            guard let user = users[inputID], user < admission else { continue }
            let original = events[user].runtimeMetadata
            let accepted = events[admission].runtimeMetadata
            guard original == nil || (original?.runId == accepted?.runId &&
                original?.userTurnId == accepted?.userTurnId) else { continue }
            deferred.insert(user)
            atAdmission[admission] = events[user]
        }
        guard !deferred.isEmpty else { return events }
        var ordered: [AgentSessionEvent] = []
        ordered.reserveCapacity(events.count)
        for (index, event) in events.enumerated() {
            if let user = atAdmission[index] { ordered.append(user) }
            if !deferred.contains(index) { ordered.append(event) }
        }
        return ordered
    }

    private struct CallKey: Hashable {
        var run: String
        var step: String
        var call: String
    }

    private static func message(id: String, role: ModelStepMessage.Role, segments: [Transcript.Segment]) -> ModelStepMessage {
        var text: [String] = []
        var images: [ModelStepImage] = []
        for segment in segments {
            switch segment {
            case .text(let value): text.append(value.content)
            case .structure(let value): text.append(value.content.jsonString)
            case .image(let image):
                switch image.source {
                case .data(let data, let mime): images.append(.init(mimeType: mime, data: data))
                case .url(let url): images.append(.init(mimeType: "", url: url))
                }
            }
        }
        return .init(id: id, role: role, text: text.joined(separator: "\n"), images: images)
    }

    public static func load(
        store: AgentSessionFileStore,
        agentID: String,
        sessionID: String,
        imageLoader: ((AgentAttachment) -> Transcript.ImageSegment?)? = nil
    ) throws -> SessionProjection {
        let journal = try store.loadJournal(agentID: agentID, sessionID: sessionID)
        return project(journal, imageLoader: imageLoader)
    }

    /// Projects one byte-bound snapshot; later appends cannot enter this model request.
    public static func project(_ journal: AgentSessionJournalSnapshot,
        imageLoader: ((AgentAttachment) -> Transcript.ImageSegment?)? = nil) -> SessionProjection {
        let events = SessionInputLifecycle.contextEvents(projectedEvents(in: journal), canonical: journal.detail.events)
        var projected = journal.detail
        projected.events = events
        return SessionProjection(journal: journal, projectedEvents: events,
            transcript: AgentSessionTranscriptBuilder.buildRecoveryTranscript(current: projected, imageLoader: imageLoader))
    }

    private static func projectedEvents(in journal: AgentSessionJournalSnapshot) -> [AgentSessionEvent] {
        for marker in journal.records.reversed() {
            guard !marker.event.isHistorical, let metadata = marker.event.runtimeMetadata, let checkpoint = metadata.checkpoint,
                  checkpoint.projectionVersion == 1, !checkpoint.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  checkpoint.coveredCursor <= marker.startCursor,
                  let covered = journal.records.firstIndex(where: {
                      $0.event.id == checkpoint.coveredThroughEventId && $0.endCursor == checkpoint.coveredCursor
                  }) else { continue }
            let prefix = Array(journal.records[...covered].map(\.event))
            let prefixIDs = Set(prefix.map(\.id))
            guard Set(checkpoint.retainedEventIds).isSubset(of: prefixIDs) else { continue }
            var retained = Set(checkpoint.retainedEventIds)
            let users = prefix.filter { $0.message?.role == .user }
            if let original = users.first { retained.insert(original.id) }
            retained.formUnion(users.suffix(8).map(\.id))
            retained.formUnion(prefix.filter {
                $0.runtimeMetadata?.userTurnId == metadata.userTurnId &&
                    ($0.message?.role == .user || $0.inputRequest != nil || $0.inputResponse != nil ||
                        $0.toolResult?.data?.asObject?["verificationEvidence"] != nil)
            }.map(\.id))
            retained.formUnion(prefix.filter {
                !$0.isHistorical && $0.runtimeMetadata?.runId == metadata.runId &&
                    $0.runtimeMetadata?.userTurnId == metadata.userTurnId &&
                    ($0.runtimeMetadata?.instruction != nil || $0.runtimeMetadata?.admissionInstructions != nil)
            }.map(\.id))
            // A retained queued user needs its admission boundary even after that run ends.
            let retainedInputs = Set(prefix.compactMap { event -> String? in
                guard retained.contains(event.id), !event.isHistorical,
                      let message = event.message, message.role == .user else { return nil }
                return message.id
            })
            retained.formUnion(prefix.filter { event in
                !event.isHistorical && (event.inputTransitions?.contains { retainedInputs.contains($0.messageId) } ?? false)
            }.map(\.id))
            var anchoredInputs: Set<String> = []
            for event in prefix where !event.isHistorical {
                guard let acceptance = event.runtimeMetadata, acceptance.requestFingerprint != nil else { continue }
                let inputID = acceptance.inputMessageId ?? acceptance.userTurnId
                if retainedInputs.contains(inputID), anchoredInputs.insert(inputID).inserted { retained.insert(event.id) }
            }
            retained.formUnion(SessionToolRecovery.unresolvedCalls(in: prefix).map(\.id))
            let answered = Set(prefix.compactMap(\.inputResponse?.requestId))
            retained.formUnion(prefix.filter { event in
                event.inputRequest.map { !answered.contains($0.id) } ?? false
            }.map(\.id))
            var lastResults: [String: AgentSessionEvent] = [:]
            for event in prefix {
                if let callID = event.toolResult?.callEventId { lastResults[callID] = event }
            }
            retained.formUnion(lastResults.values.filter {
                $0.toolResult?.executionOutcome?.requiresReconciliation == true
            }.map(\.id))
            // Retain call/result/start provenance together; no output may become an orphan.
            var changed = true
            while changed {
                let previous = retained
                let retainedSteps = Set(prefix.filter { retained.contains($0.id) }.compactMap { event -> CallKey? in
                    guard let metadata = event.runtimeMetadata, let step = metadata.stepId else { return nil }
                    return CallKey(run: metadata.runId, step: step, call: "")
                })
                for event in prefix {
                    if let metadata = event.runtimeMetadata, let step = metadata.stepId,
                       retainedSteps.contains(CallKey(run: metadata.runId, step: step, call: "")) { retained.insert(event.id) }
                    let callID = event.toolResult?.callEventId ?? event.runtimeMetadata?.callEventId
                    if retained.contains(event.id), let callID { retained.insert(callID) }
                    if let callID, retained.contains(callID) { retained.insert(event.id) }
                }
                changed = previous != retained
            }
            let references = checkpoint.artifactRefs.isEmpty ? "" : "\nArchived outputs: " + checkpoint.artifactRefs.joined(separator: ", ")
            var summaryMetadata = AgentRunMetadata(runId: metadata.runId, userTurnId: metadata.userTurnId,
                generation: metadata.generation)
            summaryMetadata.derivedSource = metadata.derivedSource
            let summary = AgentSessionEvent(id: "projection-summary-" + marker.event.id,
                agentId: journal.detail.summary.agentId, sessionId: journal.detail.summary.id, type: .message,
                createdAt: marker.event.createdAt,
                runtimeMetadata: summaryMetadata,
                message: .init(role: .assistant, segments: [.init(kind: .text,
                    text: "[Compacted session context]\n" + checkpoint.summary + references)]))
            return prefix.filter { retained.contains($0.id) } + [summary] +
                journal.records.dropFirst(covered + 1).map(\.event)
        }
        return journal.detail.events
    }
}
