import Testing
@testable import AgentRuntime

@Suite("Stream activity tracker")
struct StreamActivityTrackerTests {
    @Test("active tool call suppresses model stream idle timeout")
    func activeToolSuppressesIdleTimeout() async throws {
        let tracker = StreamActivityTracker()

        await tracker.toolStarted()

        #expect(await tracker.shouldTriggerIdleTimeout(thresholdSeconds: 0) == false)

        await tracker.toolFinished()

        #expect(await tracker.shouldTriggerIdleTimeout(thresholdSeconds: 0) == true)
    }
}
