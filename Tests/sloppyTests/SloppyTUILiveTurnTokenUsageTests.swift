import Protocols
import Testing
@testable import sloppy

@Test
func liveTurnTokenUsageTracksOnlyCurrentActiveStep() {
    var tracker = SloppyTUILiveTurnTokenUsageTracker()
    let previousTurnUsage = TokenUsage(prompt: 900, completion: 90)

    tracker.handle(
        AgentRunStatusEvent(
            stage: .thinking,
            label: "Thinking"
        )
    )
    #expect(tracker.currentUsage == nil)

    tracker.handle(
        AgentRunStatusEvent(
            stage: .responding,
            label: "Responding",
            tokenUsage: .init(prompt: 120, completion: 12)
        )
    )
    #expect(tracker.currentUsage == TokenUsage(prompt: 120, completion: 12))

    tracker.handle(
        AgentRunStatusEvent(
            stage: .searching,
            label: "Searching"
        )
    )
    #expect(tracker.currentUsage == nil)

    tracker.handle(
        AgentRunStatusEvent(
            stage: .done,
            label: "Done",
            tokenUsage: previousTurnUsage
        )
    )
    #expect(tracker.currentUsage == nil)
}
