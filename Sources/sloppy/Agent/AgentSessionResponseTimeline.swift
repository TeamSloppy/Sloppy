import Foundation
import Protocols

/// Persists response blocks at typed activity boundaries without storing every token.
struct AgentSessionResponseTimeline {
    private var snapshot = ""
    private var persistedPrefix = ""
    private var pendingStartedAt: Date?
    private(set) var persistedResponses: [AgentSessionEvent] = []

    mutating func recordSnapshot(_ text: String, at date: Date = Date()) {
        if pendingStartedAt == nil, text != persistedPrefix { pendingStartedAt = date }
        snapshot = text
    }

    func remainingText(from finalText: String) -> String {
        AgentSessionStreamDelta.extract(previous: persistedPrefix, snapshot: finalText)
    }

    mutating func prependingResponse(to events: [AgentSessionEvent], agentID: String, sessionID: String) -> [AgentSessionEvent] {
        let isBoundary = events.contains { event in
            event.type == .toolCall || event.type == .toolResult
                || event.message?.segments.contains(where: { $0.kind == .thinking }) == true
        }
        guard isBoundary else { return events }
        let text = remainingText(from: snapshot)
        guard !text.isEmpty else { return events }
        let startedAt = pendingStartedAt ?? events.first?.createdAt ?? Date()
        persistedPrefix = snapshot
        pendingStartedAt = nil
        let response = AgentSessionEvent(
            agentId: agentID, sessionId: sessionID, type: .message, createdAt: startedAt,
            message: AgentSessionMessage(role: .assistant, segments: [.init(kind: .text, text: text)],
                                         createdAt: startedAt, userId: "agent")
        )
        persistedResponses.append(response)
        return [response] + events
    }
}
