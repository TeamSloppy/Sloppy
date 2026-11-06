import Foundation
import Protocols

public enum SessionToolRecovery {
    /// Missing starts are known not to have executed. Started and legacy unresolved calls are unknown.
    public static func unknownEffectCallIDs(in events: [AgentSessionEvent]) -> [String] {
        let live = events.filter { !$0.isHistorical }
        let started = Set(live.filter { $0.runtimeMetadata?.executionPhase == .started }.compactMap(\.runtimeMetadata?.callEventId))
        var unknown = Set(unresolvedCalls(in: live).filter {
            $0.runtimeMetadata?.executionPhase != .requested || started.contains($0.id)
        }.map(\.id))
        var lastResults: [String: AgentToolResultEvent] = [:]
        for event in live {
            if let result = event.toolResult, let id = result.callEventId { lastResults[id] = result }
        }
        for (id, result) in lastResults where result.executionOutcome?.requiresReconciliation == true {
            unknown.insert(id)
        }
        return unknown.sorted()
    }

    public static func unresolvedCalls(in events: [AgentSessionEvent]) -> [AgentSessionEvent] {
        var pending: [AgentSessionEvent] = []
        for event in events where !event.isHistorical {
            if event.type == .toolCall, event.toolCall != nil { pending.append(event) }
            guard event.type == .toolResult, let result = event.toolResult else { continue }
            if let id = result.callEventId {
                pending.removeAll { $0.id == id && $0.toolCall?.tool == result.tool }
            } else if let index = pending.firstIndex(where: { $0.toolCall?.tool == result.tool }) {
                pending.remove(at: index)
            }
        }
        return pending
    }

    public static func interruptionEvents(for detail: AgentSessionDetail) -> [AgentSessionEvent] {
        unresolvedCalls(in: detail.events).compactMap { event in
            guard let call = event.toolCall else { return nil }
            let hasStartMarker = detail.events.contains {
                !$0.isHistorical && $0.runtimeMetadata?.callEventId == event.id &&
                    $0.runtimeMetadata?.executionPhase == .started
            }
            // Legacy calls have no separate start phase and remain conservatively unknown.
            let neverStarted = event.runtimeMetadata?.executionPhase == .requested && !hasStartMarker
            let code = neverStarted ? "tool_not_started" : "tool_execution_interrupted"
            return AgentSessionEvent(
                agentId: detail.summary.agentId, sessionId: detail.summary.id, type: .toolResult,
                toolResult: AgentToolResultEvent(
                    tool: call.tool, ok: false,
                    data: .object(["requiresReconciliation": .bool(!neverStarted), "callEventId": .string(event.id)]),
                    error: .init(code: code, message: neverStarted
                        ? "The requested call never reached its durable start marker. It was not executed; current policy and approvals must be checked before trying again."
                        : "Execution ended without a durable result. Side effects may already have occurred. Inspect the target before proceeding; do not replay this call.", retryable: neverStarted),
                    callEventId: event.id,
                    executionOutcome: .init(state: .interrupted, category: neverStarted ? .incomplete : .unknown,
                        code: code, requiresReconciliation: !neverStarted)
                )
            )
        }
    }

    public static func requiresReconciliation(tool: String, arguments: [String: Protocols.JSONValue], events: [AgentSessionEvent]) -> Bool {
        if unresolvedCalls(in: events).contains(where: { $0.toolCall?.tool == tool && $0.toolCall?.arguments == arguments }) { return true }
        let calls = Dictionary(events.compactMap { event -> (String, AgentToolCallEvent)? in
            guard !event.isHistorical, let call = event.toolCall else { return nil }
            return (event.id, call)
        }, uniquingKeysWith: { _, latest in latest })
        var lastByCall: [String: AgentToolResultEvent] = [:]
        for event in events {
            guard let result = event.toolResult, let id = result.callEventId else { continue }
            lastByCall[id] = result
        }
        return lastByCall.contains { id, result in
            let reconciliation = result.data?.asObject?["reconciliation"]?.asString
            guard result.executionOutcome?.requiresReconciliation == true || reconciliation == "completed" || reconciliation == "failed", let call = calls[id] else { return false }
            return call.tool == tool && call.arguments == arguments
        }
    }
}
