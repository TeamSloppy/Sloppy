import Foundation
import Protocols
import Testing
@testable import sloppy

@Test
func goalControllerStartsPausesResumesAndClearsGoal() async {
    let controller = AgentSessionGoalController()

    let started = await controller.start(
        agentID: "agent",
        sessionID: "session",
        objective: "make tests pass",
        maxAttempts: 4,
        now: Date(timeIntervalSince1970: 10)
    )
    #expect(started.objective == "make tests pass")
    #expect(started.status == .active)
    #expect(started.maxAttempts == 4)

    let paused = await controller.pause(agentID: "agent", sessionID: "session", now: Date(timeIntervalSince1970: 20))
    #expect(paused?.status == .paused)

    let resumed = await controller.resume(agentID: "agent", sessionID: "session", now: Date(timeIntervalSince1970: 30))
    #expect(resumed?.status == .active)

    let cleared = await controller.clear(agentID: "agent", sessionID: "session", now: Date(timeIntervalSince1970: 40))
    #expect(cleared?.status == .cleared)
    #expect(await controller.goal(agentID: "agent", sessionID: "session") == nil)
}

@Test
func goalControllerCompletesWhenSessionCompleteToolSucceeds() async {
    let controller = AgentSessionGoalController()
    _ = await controller.start(agentID: "agent", sessionID: "session", objective: "ship", now: Date(timeIntervalSince1970: 10))

    let evaluation = await controller.evaluateTurn(
        agentID: "agent",
        sessionID: "session",
        events: [
            toolResultEvent(tool: "session.complete", ok: true, data: .object([
                "completed": .bool(true),
                "summary": .string("verified")
            ])),
        ],
        now: Date(timeIntervalSince1970: 20)
    )

    #expect(evaluation?.status == .completed)
    #expect(evaluation?.shouldContinue == false)
    #expect(await controller.goal(agentID: "agent", sessionID: "session")?.status == .completed)
}

@Test
func goalControllerWaitsWhenTurnRequestsInput() async {
    let controller = AgentSessionGoalController()
    _ = await controller.start(agentID: "agent", sessionID: "session", objective: "ship", now: Date(timeIntervalSince1970: 10))

    let evaluation = await controller.evaluateTurn(
        agentID: "agent",
        sessionID: "session",
        events: [
            AgentSessionEvent(
                agentId: "agent",
                sessionId: "session",
                type: .inputRequest,
                inputRequest: PlanInputRequest(
                    id: "input-1",
                    title: "Which branch?",
                    questions: []
                )
            ),
        ],
        now: Date(timeIntervalSince1970: 20)
    )

    #expect(evaluation?.status == .waitingInput)
    #expect(evaluation?.shouldContinue == false)
}

@Test
func goalControllerBlocksWhenTurnIsInterrupted() async {
    let controller = AgentSessionGoalController()
    _ = await controller.start(agentID: "agent", sessionID: "session", objective: "ship", now: Date(timeIntervalSince1970: 10))

    let evaluation = await controller.evaluateTurn(
        agentID: "agent",
        sessionID: "session",
        events: [
            runStatusEvent(.interrupted, details: "Tool limit reached."),
        ],
        now: Date(timeIntervalSince1970: 20)
    )

    #expect(evaluation?.status == .blocked)
    #expect(evaluation?.shouldContinue == false)
}

@Test
func goalControllerContinuesUntilAttemptLimitThenExhausts() async {
    let controller = AgentSessionGoalController()
    _ = await controller.start(
        agentID: "agent",
        sessionID: "session",
        objective: "ship",
        maxAttempts: 2,
        now: Date(timeIntervalSince1970: 10)
    )

    let first = await controller.evaluateTurn(
        agentID: "agent",
        sessionID: "session",
        events: [runStatusEvent(.done)],
        now: Date(timeIntervalSince1970: 20)
    )
    #expect(first?.status == .active)
    #expect(first?.shouldContinue == true)
    #expect(first?.continuationPrompt?.contains("[Sloppy goal continuation]") == true)

    let second = await controller.evaluateTurn(
        agentID: "agent",
        sessionID: "session",
        events: [runStatusEvent(.done)],
        now: Date(timeIntervalSince1970: 30)
    )
    #expect(second?.status == .exhausted)
    #expect(second?.shouldContinue == false)
}

private func runStatusEvent(_ stage: AgentRunStage, details: String? = nil) -> AgentSessionEvent {
    AgentSessionEvent(
        agentId: "agent",
        sessionId: "session",
        type: .runStatus,
        runStatus: AgentRunStatusEvent(stage: stage, label: stage.rawValue, details: details)
    )
}

private func toolResultEvent(tool: String, ok: Bool, data: JSONValue?) -> AgentSessionEvent {
    AgentSessionEvent(
        agentId: "agent",
        sessionId: "session",
        type: .toolResult,
        toolResult: AgentToolResultEvent(tool: tool, ok: ok, data: data)
    )
}
