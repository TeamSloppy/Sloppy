import Foundation
import Testing
@testable import sloppy
import Protocols

struct AgentSessionResponseTimelineTests {
    @Test func responseBlocksPersistBetweenTypedActivityBoundaries() throws {
        var timeline = AgentSessionResponseTimeline()
        let start = Date(timeIntervalSince1970: 10)
        let first = AgentSessionEvent(id: "read", agentId: "agent", sessionId: "session", type: .toolCall,
                                     createdAt: start.addingTimeInterval(1))
        #expect(timeline.prependingResponse(to: [first], agentID: "agent", sessionID: "session") == [first])
        timeline.recordSnapshot("First response. ", at: start.addingTimeInterval(2))
        let second = AgentSessionEvent(id: "write", agentId: "agent", sessionId: "session", type: .toolCall,
                                      createdAt: start.addingTimeInterval(3))
        let batch = timeline.prependingResponse(to: [second], agentID: "agent", sessionID: "session")
        #expect(batch.count == 2)
        #expect(batch.first?.message?.segments.first?.text == "First response. ")
        #expect(batch.first?.createdAt == start.addingTimeInterval(2))
        #expect(batch.last == second)
        // Tool results without new text do not duplicate the previous response.
        let result = AgentSessionEvent(id: "result", agentId: "agent", sessionId: "session", type: .toolResult)
        #expect(timeline.prependingResponse(to: [result], agentID: "agent", sessionID: "session") == [result])
        timeline.recordSnapshot("First response. Second response.", at: start.addingTimeInterval(4))
        let third = AgentSessionEvent(id: "test", agentId: "agent", sessionId: "session", type: .toolCall)
        let next = timeline.prependingResponse(to: [third], agentID: "agent", sessionID: "session")
        #expect(next.first?.message?.segments.first?.text == "Second response.")
        #expect(timeline.remainingText(from: "First response. Second response. Final") == " Final")
        #expect(timeline.remainingText(from: "First response. Second response.").isEmpty)
        let stored = [first] + batch + next
        let restored = try JSONDecoder().decode([AgentSessionEvent].self, from: JSONEncoder().encode(stored))
        #expect(restored == stored)
        #expect(restored.map(\.type) == [.toolCall, .message, .toolCall, .message, .toolCall])
    }

    @Test func thinkingIsABoundaryButUsageStatusIsNot() {
        var timeline = AgentSessionResponseTimeline()
        timeline.recordSnapshot("説明👨‍👩‍👧‍👦")
        let status = AgentSessionEvent(agentId: "a", sessionId: "s", type: .runStatus)
        #expect(timeline.prependingResponse(to: [status], agentID: "a", sessionID: "s") == [status])
        let thinking = AgentSessionEvent(agentId: "a", sessionId: "s", type: .message,
                                        message: .init(role: .assistant, segments: [.init(kind: .thinking, text: "Plan")]))
        let batch = timeline.prependingResponse(to: [thinking], agentID: "a", sessionID: "s")
        #expect(batch.first?.message?.segments.first?.text == "説明👨‍👩‍👧‍👦")
        #expect(timeline.remainingText(from: "説明👨‍👩‍👧‍👦続き") == "続き")
        #expect(timeline.remainingText(from: "Revised response") == "Revised response")
    }
}
