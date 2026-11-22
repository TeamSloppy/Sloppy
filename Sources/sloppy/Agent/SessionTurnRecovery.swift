import Foundation
import Protocols

struct SessionTurnRecovery {
    let checkpointID: String
    let checkpoint: AgentTurnCheckpoint
    let message: AgentSessionMessage
    let model: String?
    let priorInstructions: [String]
    let firstCheckpointID: String

    @TaskLocal static var active: Scope?

    struct Scope: Sendable {
        let sessionID: String
        let firstCheckpointID: String
        let sourceCheckpointID: String

        func priorEvents(in events: [AgentSessionEvent]) -> [AgentSessionEvent] {
            guard let start = events.firstIndex(where: { $0.id == firstCheckpointID }) else { return [] }
            var isCurrentAttempt = false
            return events[start...].filter { event in
                if event.runStatus?.turnCheckpoint?.resumesCheckpointId == sourceCheckpointID {
                    isCurrentAttempt = true
                }
                // Keep late results for earlier calls, while excluding calls made by this attempt.
                return !isCurrentAttempt || event.type == .toolResult
            }
        }
    }

    static func latest(in events: [AgentSessionEvent]) -> Self? {
        guard let userIndex = events.lastIndex(where: { $0.importOrigin == nil && $0.message?.role == .user }),
              let message = events[userIndex].message, message.peerOrigin == nil, message.uiAction == nil else { return nil }
        let turnIndices = events.indices.dropFirst(userIndex + 1)
        let typedStart = turnIndices.last { index in
            let event = events[index]
            return event.importOrigin == nil && event.runStatus?.stage == .responding
                && event.runStatus?.turnCheckpoint?.turnId == message.id
        }
        // Old journals wrote these two statuses together at the start of the turn.
        // Later usage updates can have the same stages, so take the first pair.
        guard let start = typedStart ?? turnIndices.first(where: { index in
            events[index].importOrigin == nil && events[index].runStatus?.stage == .responding
                && events[index].runStatus?.turnCheckpoint == nil && events[index - 1].runStatus?.stage == .thinking
        }) else { return nil }
        let event = events[start]
        let status = event.runStatus
        let checkpoint = status?.turnCheckpoint

        let tail = events.dropFirst(start + 1).filter { $0.importOrigin == nil }
        let finalStatus = tail.reversed().compactMap(\.runStatus).first {
            $0.diagnostics != nil || $0.stage == .done
                || ($0.stage == .paused && $0.executionOutcome != nil)
        }
        if let finalStatus, finalStatus.stage != .interrupted, finalStatus.executionOutcome?.state != .cancelled {
            return nil
        }
        // A started turn with no terminal status and no live runner is a process-loss checkpoint.
        let priorAttempts = events[...start].filter { event in
            guard event.importOrigin == nil, let checkpoint = event.runStatus?.turnCheckpoint,
                  checkpoint.turnId == message.id else { return false }
            return true
        }
        return Self(
            checkpointID: event.id,
            checkpoint: checkpoint ?? .init(turnId: message.id, mode: .defaultMode),
            message: message,
            model: status?.selectedModel,
            priorInstructions: priorAttempts.compactMap { $0.runStatus?.turnCheckpoint?.instruction },
            firstCheckpointID: priorAttempts.first?.runStatus?.turnCheckpoint?.resumesCheckpointId
                ?? priorAttempts.first?.id ?? event.id
        )
    }

    static func receipt(for request: AgentSessionRestoreRequest, in events: [AgentSessionEvent]) -> AgentSessionEvent? {
        events.first { event in
            guard event.importOrigin == nil, let checkpoint = event.runStatus?.turnCheckpoint else { return false }
            return checkpoint.turnId == request.turnId && checkpoint.resumesCheckpointId == request.checkpointId
        }
    }

    func instructions(_ extraInstruction: String?) -> String {
        let updates = priorInstructions + [extraInstruction].compactMap { $0 }
        return """
        Resume the interrupted turn in the transcript. Keep its objective and scope.
        Continue from persisted assistant messages and tool results. Preserve completed work and verification evidence.
        For a tool call marked as needing reconciliation, inspect its target using read-only operations and report any uncertainty.
        Replay an uncertain operation only after durable evidence confirms it did not execute.
        """ + (updates.isEmpty ? "" : "\n\nAdditional user instructions for this continuation:\n" + updates.joined(separator: "\n"))
    }
}
