import Foundation
import Protocols

public enum SessionToolRecovery {
    public static func unresolvedCalls(in events: [AgentSessionEvent]) -> [AgentSessionEvent] {
        var pending: [AgentSessionEvent] = []
        for event in events where event.importOrigin == nil {
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
            return AgentSessionEvent(
                agentId: detail.summary.agentId, sessionId: detail.summary.id, type: .toolResult,
                toolResult: AgentToolResultEvent(
                    tool: call.tool, ok: false,
                    data: .object(["requiresReconciliation": .bool(true), "callEventId": .string(event.id)]),
                    error: .init(code: "tool_execution_interrupted", message: "Execution ended without a durable result. Side effects may already have occurred. Inspect the target before proceeding; do not replay this call.", retryable: false),
                    callEventId: event.id,
                    executionOutcome: .init(state: .interrupted, category: .unknown, code: "tool_execution_interrupted", requiresReconciliation: true)
                )
            )
        }
    }

    public static func requiresReconciliation(tool: String, arguments: [String: Protocols.JSONValue], events: [AgentSessionEvent]) -> Bool {
        if unresolvedCalls(in: events).contains(where: { $0.toolCall?.tool == tool && $0.toolCall?.arguments == arguments }) { return true }
        let calls = Dictionary(events.compactMap { event -> (String, AgentToolCallEvent)? in
            guard event.importOrigin == nil, let call = event.toolCall else { return nil }
            return (event.id, call)
        }, uniquingKeysWith: { _, latest in latest })
        let interruptedCalls = Set(events.compactMap { event in
            event.importOrigin == nil && event.toolResult?.executionOutcome?.requiresReconciliation == true
                ? event.toolResult?.callEventId : nil
        })
        return resultIndices(in: events).contains { id, index in
            guard let result = events[index].toolResult else { return false }
            let reconciliation = result.data?.asObject?["reconciliation"]?.asString
            // A late result replaces the unknown outcome in the transcript. It does not
            // authorize executing the operation again.
            guard (interruptedCalls.contains(id) && reconciliation != "not_executed")
                    || reconciliation == "completed" || reconciliation == "failed",
                  let call = calls[id] else { return false }
            return call.tool == tool && call.arguments == arguments
        }
    }

    /// A recovery marker is provisional. A real result wins even if both writers
    /// race and the marker is appended after the result.
    static func resultIndices(in events: [AgentSessionEvent]) -> [String: Int] {
        var latest: [String: Int] = [:]
        for (index, event) in events.enumerated() where event.importOrigin == nil {
            guard let result = event.toolResult, let id = result.callEventId else { continue }
            if result.executionOutcome?.requiresReconciliation == true, let prior = latest[id],
               events[prior].toolResult?.executionOutcome?.requiresReconciliation != true { continue }
            latest[id] = index
        }
        return latest
    }

    public static func result(for callEventID: String, in events: [AgentSessionEvent]) -> AgentToolResultEvent? {
        resultIndices(in: events)[callEventID].flatMap { events[$0].toolResult }
    }

    public static func confirmedResults(in events: [AgentSessionEvent]) -> [(AgentToolCallEvent, AgentToolResultEvent)] {
        let calls = Dictionary(events.compactMap { event -> (String, AgentToolCallEvent)? in
            guard event.importOrigin == nil, let call = event.toolCall else { return nil }
            return (event.id, call)
        }, uniquingKeysWith: { _, latest in latest })
        return resultIndices(in: events).values.sorted().compactMap { index in
            guard let result = events[index].toolResult, let id = result.callEventId,
                  let call = calls[id], result.ok else { return nil }
            return (call, result)
        }
    }
}
