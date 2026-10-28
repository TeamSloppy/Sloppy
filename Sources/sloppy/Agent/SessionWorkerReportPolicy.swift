import Protocols

/// Uses server-owned parentage and lifecycle events, never the wording of a report.
enum SessionWorkerReportPolicy {
    static func shouldRecord(sender: AgentSessionSummary, target: AgentSessionDetail) -> Bool {
        let dispatchIndex = target.events.lastIndex { $0.subSession?.childSessionId == sender.id }
        guard sender.parentSessionId == target.summary.id || dispatchIndex != nil else { return false }
        let events = dispatchIndex.map { Array(target.events.dropFirst($0 + 1)) }
            ?? target.events.filter { $0.createdAt >= sender.createdAt }
        // A new human message may merely steer active work. Only a terminal lifecycle event
        // proves that the originating turn ended, even when a subsequent turn is now running.
        return events.contains { $0.runStatus?.stage == .done || $0.runStatus?.stage == .interrupted }
    }
}
