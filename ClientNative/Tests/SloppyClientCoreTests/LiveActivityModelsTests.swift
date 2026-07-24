import Foundation
import SloppyLiveActivity
import Testing

@Suite("Live Activity models")
struct LiveActivityModelsTests {
    @Test("content state stays compact while preserving total counts")
    func contentStateStaysCompact() {
        let runs = (0..<5).map {
            SloppyActivityAgentRun(
                id: "run-\($0)",
                sessionTitle: "Session \($0)",
                agentName: "Agent",
                status: "Working"
            )
        }
        let tasks = (0..<4).map {
            SloppyActivityTask(
                id: "task-\($0)",
                title: "Task \($0)",
                projectName: "Sloppy",
                status: .inProgress
            )
        }

        let state = SloppyActivityContentState(agentRuns: runs, tasks: tasks)

        #expect(state.agentRuns.count == 3)
        #expect(state.tasks.count == 3)
        #expect(state.agentRunCount == 5)
        #expect(state.taskCount == 4)
        #expect(state.activityCount == 9)
        #expect(!state.isEmpty)
    }

    @Test("approval and error make an otherwise empty state visible")
    func approvalAndErrorMakeStateVisible() {
        let approvalState = SloppyActivityContentState(
            approval: SloppyActivityApproval(
                id: "approval",
                title: "Allow file access?",
                message: "Read Package.swift"
            )
        )
        let errorState = SloppyActivityContentState(
            error: SloppyActivityError(title: "Agent failed", message: "Connection lost")
        )

        #expect(!approvalState.isEmpty)
        #expect(!errorState.isEmpty)
        #expect(SloppyActivityContentState().isEmpty)
    }

    @Test("content state round-trips through ActivityKit-compatible coding")
    func contentStateRoundTrips() throws {
        let state = SloppyActivityContentState(
            tasks: [
                SloppyActivityTask(
                    id: "project/task",
                    title: "Ship Live Activity",
                    projectName: "Sloppy",
                    status: .needsReview
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )

        let decoded = try JSONDecoder().decode(
            SloppyActivityContentState.self,
            from: JSONEncoder().encode(state)
        )

        #expect(decoded == state)
    }
}
