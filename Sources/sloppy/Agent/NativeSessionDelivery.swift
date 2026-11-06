import Foundation
import PluginSDK
import Protocols
import SloppyRuntime

/// A different payload cannot acquire the same durable input identity.
enum NativeSessionDelivery {
    struct ActiveInput: Sendable, Equatable {
        let messageID: String
        let fingerprint: String
    }
    enum Resolution {
        case fresh
        case delivered(AgentSessionMessageResponse)
        case unfinished(AgentRunMetadata, AgentSessionMessage)
    }
    static func fingerprint(_ request: AgentSessionPostMessageRequest, peerOrigin: AgentSessionPeerOrigin?) throws -> String {
        try NativeInputCapture.fingerprint(request, peerOrigin: peerOrigin)
    }

    private static func legacyFingerprint(_ request: AgentSessionPostMessageRequest, peerOrigin: AgentSessionPeerOrigin?) throws -> String {
        guard var object = try JSONValueCoder.encode(request).asObject else {
            throw AgentSessionOrchestrator.OrchestratorError.invalidPayload
        }
        object.removeValue(forKey: "clientMessageId")
        if let peerOrigin { object["peerOrigin"] = try JSONValueCoder.encode(peerOrigin) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return "v1:" + AgentPluginSHA256.hash(try encoder.encode(JSONValue.object(object)))
    }

    static func resolve(_ request: AgentSessionPostMessageRequest, peerOrigin: AgentSessionPeerOrigin?,
        detail: AgentSessionDetail) throws -> Resolution {
        guard let messageID = request.clientMessageId else { return .fresh }
        guard UUID(uuidString: messageID) != nil else {
            throw AgentSessionOrchestrator.OrchestratorError.invalidPayload
        }
        let owned = detail.events.filter { event in
            guard !event.isHistorical, let metadata = event.runtimeMetadata else { return false }
            return metadata.inputMessageId == messageID ||
                (metadata.inputMessageId == nil && metadata.userTurnId == messageID)
        }
        let lifecycle = try SessionInputLifecycle.states(in: detail.events)[messageID]
        guard !owned.isEmpty else {
            guard !hasHistoricalMessageID(messageID, in: detail) else {
                throw AgentSessionOrchestrator.OrchestratorError.invalidPayload
            }
            if let lifecycle {
                guard lifecycle.latest.fingerprint == (try NativeInputCapture.fingerprint(request, peerOrigin: peerOrigin,
                    uiSubmission: lifecycle.context.uiSubmission, uiSnapshot: lifecycle.context.uiSnapshot,
                    sourceRequest: lifecycle.context.sourceRequest)) else {
                    throw AgentSessionOrchestrator.OrchestratorError.invalidPayload
                }
                if lifecycle.latest.disposition != .queued {
                    return .delivered(.init(summary: detail.summary,
                        appendedEvents: detail.events.filter { !$0.isHistorical && ($0.inputTransitions?.contains { $0.messageId == messageID } ?? false) },
                        routeDecision: nil, replayed: true))
                }
            }
            return .fresh
        }
        guard let accepted = owned.compactMap(\.runtimeMetadata).last(where: { $0.requestFingerprint != nil }) else {
            throw AgentSessionOrchestrator.OrchestratorError.invalidPayload
        }
        let submitted = accepted.requestFingerprint?.hasPrefix("v1:") == true
            ? try legacyFingerprint(request, peerOrigin: peerOrigin)
            : try NativeInputCapture.fingerprint(request, peerOrigin: peerOrigin,
                uiSubmission: lifecycle?.context.uiSubmission, uiSnapshot: lifecycle?.context.uiSnapshot,
                sourceRequest: lifecycle?.context.sourceRequest)
        guard accepted.requestFingerprint == submitted else {
            throw AgentSessionOrchestrator.OrchestratorError.invalidPayload
        }
        if !wasDelivered(accepted, in: detail) {
            guard let index = detail.events.firstIndex(where: {
                !$0.isHistorical && $0.message?.id == messageID && $0.message?.role == .user &&
                    ($0.runtimeMetadata == nil || ($0.runtimeMetadata?.runId == accepted.runId &&
                        $0.runtimeMetadata?.userTurnId == accepted.userTurnId))
            }), let message = detail.events[index].message else {
                throw AgentSessionOrchestrator.OrchestratorError.invalidPayload
            }
            return .unfinished(accepted, message)
        }
        let events = detail.events.filter { event in
            !event.isHistorical && event.runtimeMetadata?.runId == accepted.runId &&
                event.runtimeMetadata?.userTurnId == accepted.userTurnId &&
                event.runtimeMetadata?.presentationOnly == true && (event.message != nil || event.runStatus != nil)
        }
        return .delivered(.init(summary: detail.summary, appendedEvents: events, routeDecision: nil, replayed: true))
    }

    /// An accepted input keeps ownership until its terminal delivery is durable, even when
    /// its in-memory task no longer exists. A saved result/settled state alone is not delivery.
    static func firstUnfinishedInput(in detail: AgentSessionDetail) -> AgentRunMetadata? {
        let delivered = deliveredRuns(in: detail)
        for event in detail.events where !event.isHistorical {
            guard let metadata = event.runtimeMetadata, metadata.requestFingerprint != nil else { continue }
            if (delivered[RunIdentity(metadata)] ?? -1) < metadata.generation { return metadata }
        }
        return nil
    }

    static func hasHistoricalMessageID(_ messageID: String, in detail: AgentSessionDetail) -> Bool {
        detail.events.contains { $0.isHistorical && $0.message?.id == messageID }
    }

    private struct RunIdentity: Hashable {
        let runID: String
        let userTurnID: String
        init(_ metadata: AgentRunMetadata) { runID = metadata.runId; userTurnID = metadata.userTurnId }
    }

    private static func wasDelivered(_ accepted: AgentRunMetadata, in detail: AgentSessionDetail) -> Bool {
        (deliveredRuns(in: detail)[RunIdentity(accepted)] ?? -1) >= accepted.generation
    }

    private static func deliveredRuns(in detail: AgentSessionDetail) -> [RunIdentity: Int] {
        var delivered: [RunIdentity: Int] = [:]
        for event in detail.events {
            guard !event.isHistorical, let metadata = event.runtimeMetadata,
                  metadata.presentationOnly == true, let status = event.runStatus,
                  status.stage == .done || status.stage == .paused || status.stage == .interrupted else { continue }
            let identity = RunIdentity(metadata)
            delivered[identity] = max(delivered[identity] ?? -1, metadata.generation)
        }
        return delivered
    }

    static func hasLaterUserInput(after messageID: String, in detail: AgentSessionDetail,
        queuedInputIDs: Set<String> = []) -> Bool {
        guard let lifecycle = try? SessionInputLifecycle.states(in: detail.events) else { return true }
        guard let index = detail.events.firstIndex(where: {
            !$0.isHistorical && $0.message?.id == messageID && $0.message?.role == .user
        }) else { return true }
        let acceptedIDs = Set(detail.events.compactMap { event -> String? in
            guard !event.isHistorical, let metadata = event.runtimeMetadata,
                  metadata.requestFingerprint != nil else { return nil }
            return metadata.inputMessageId ?? metadata.userTurnId
        })
        return detail.events.dropFirst(index + 1).contains { event in
            guard !event.isHistorical, let message = event.message, message.role == .user,
                  message.id != messageID else { return false }
            if event.runtimeMetadata?.presentationOnly == true,
               event.runtimeMetadata?.inputMessageId == messageID { return false }
            if let input = lifecycle[message.id] {
                if input.context.request.deliveryIntent == .steering, let owner = input.owner,
                   let originalOwner = lifecycle[messageID]?.owner,
                   owner.runId == originalOwner.runId, owner.userTurnId == originalOwner.userTurnId {
                    return false
                }
                return input.wasAdmitted
            }
            // Only a still-queued, never-admitted follow-up is safe to exclude. A newer
            // accepted run or an unclassified user event must retain the conflict guard.
            return !queuedInputIDs.contains(message.id) || acceptedIDs.contains(message.id)
        }
    }

    static func isResumedInput(_ messageID: String, in detail: AgentSessionDetail) -> Bool {
        detail.events.contains { event in
            !event.isHistorical && event.inputResponse?.status == .answered &&
                event.runtimeMetadata?.inputMessageId == messageID && event.runtimeMetadata?.runState != nil
        }
    }

    static func settledResponse(in detail: AgentSessionDetail, metadata: AgentRunMetadata,
        generation: Int) throws -> ModelStepResponse {
        guard let raw = detail.events.last(where: {
            !$0.isHistorical && $0.runtimeMetadata?.runId == metadata.runId &&
                $0.runtimeMetadata?.userTurnId == metadata.userTurnId &&
                $0.runtimeMetadata?.generation == generation && $0.runtimeMetadata?.modelResponse != nil
        })?.runtimeMetadata?.modelResponse else { throw AgentSessionOrchestrator.OrchestratorError.invalidPayload }
        let response = try JSONValueCoder.decode(ModelStepResponse.self, from: raw)
        guard response.stopReason == .endTurn, response.toolCalls.isEmpty else {
            throw AgentSessionOrchestrator.OrchestratorError.invalidPayload
        }
        return response
    }
}
