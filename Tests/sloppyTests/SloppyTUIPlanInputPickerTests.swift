import Protocols
import Testing
@testable import sloppy

@Test
func planInputPickerBuildsSingleQuestionOptions() throws {
    let request = PlanInputRequest(
        id: "request-1",
        title: "Need direction",
        questions: [
            PlanInputQuestion(
                id: "verdict",
                question: "What should I do?",
                options: [
                    PlanInputOption(id: "mark_as_fixed", label: "Mark as fixed"),
                    PlanInputOption(id: "bug_repeated", label: "Bug is repeated", description: "Keep debugging"),
                ]
            ),
        ]
    )

    let picker = try #require(SloppyTUIPlanInputPicker.picker(for: request))

    #expect(picker.kind == .planInput)
    #expect(picker.title == "What should I do?")
    #expect(picker.items.map(\.label) == ["Mark as fixed", "Bug is repeated"])

    let payload = try #require(SloppyTUIPlanInputPicker.answerRequest(for: picker.items[1], request: request))
    #expect(payload.status == .answered)
    #expect(payload.userId == "tui")
    #expect(payload.answers == [PlanInputAnswer(questionId: "verdict", selectedOptionId: "bug_repeated")])
}

@Test
func planInputPickerBuildsMultiQuestionCombinations() throws {
    let request = PlanInputRequest(
        id: "request-2",
        questions: [
            PlanInputQuestion(
                id: "scope",
                header: "Scope",
                question: "How much?",
                options: [
                    PlanInputOption(id: "small", label: "Small"),
                    PlanInputOption(id: "large", label: "Large"),
                ]
            ),
            PlanInputQuestion(
                id: "risk",
                header: "Risk",
                question: "How risky?",
                options: [
                    PlanInputOption(id: "safe", label: "Safe"),
                    PlanInputOption(id: "bold", label: "Bold"),
                ]
            ),
        ]
    )

    let picker = try #require(SloppyTUIPlanInputPicker.picker(for: request))

    #expect(picker.items.count == 4)
    #expect(picker.items[2].label == "Large / Safe")

    let payload = try #require(SloppyTUIPlanInputPicker.answerRequest(for: picker.items[2], request: request))
    #expect(payload.answers == [
        PlanInputAnswer(questionId: "scope", selectedOptionId: "large"),
        PlanInputAnswer(questionId: "risk", selectedOptionId: "safe"),
    ])
}

@Test
func planInputStateFindsLatestUnansweredRequest() throws {
    let first = PlanInputRequest(
        id: "request-1",
        questions: [
            PlanInputQuestion(
                id: "first",
                question: "First?",
                options: [
                    PlanInputOption(id: "yes", label: "Yes"),
                    PlanInputOption(id: "no", label: "No"),
                ]
            ),
        ]
    )
    let second = PlanInputRequest(
        id: "request-2",
        questions: [
            PlanInputQuestion(
                id: "second",
                question: "Second?",
                options: [
                    PlanInputOption(id: "small", label: "Small"),
                    PlanInputOption(id: "large", label: "Large"),
                ]
            ),
        ]
    )
    let events = [
        AgentSessionEvent(agentId: "a", sessionId: "s", type: .inputRequest, inputRequest: first),
        AgentSessionEvent(
            agentId: "a",
            sessionId: "s",
            type: .inputResponse,
            inputResponse: PlanInputResponse(requestId: first.id, status: .answered, answers: [], userId: "tui")
        ),
        AgentSessionEvent(agentId: "a", sessionId: "s", type: .inputRequest, inputRequest: second),
    ]

    #expect(SloppyTUIPlanInputState.latestUnansweredRequest(in: events)?.id == second.id)
    #expect(SloppyTUIPlanInputState.latestUnansweredRequest(in: events + [
        AgentSessionEvent(
            agentId: "a",
            sessionId: "s",
            type: .inputResponse,
            inputResponse: PlanInputResponse(requestId: second.id, status: .answered, answers: [], userId: "tui")
        )
    ]) == nil)
}

@Test
func planInputStateRestoresPickerSelectionForSameRequest() throws {
    let first = PlanInputRequest(
        id: "request-1",
        questions: [
            PlanInputQuestion(
                id: "choice",
                question: "Choose?",
                options: [
                    PlanInputOption(id: "a", label: "A"),
                    PlanInputOption(id: "b", label: "B"),
                ]
            ),
        ]
    )
    let second = PlanInputRequest(
        id: "request-2",
        questions: first.questions
    )

    let restored = try #require(SloppyTUIPlanInputState.picker(
        for: first,
        previousRequestID: first.id,
        previousSelectedIndex: 1
    ))
    let reset = try #require(SloppyTUIPlanInputState.picker(
        for: second,
        previousRequestID: first.id,
        previousSelectedIndex: 1
    ))

    #expect(restored.selectedIndex == 1)
    #expect(reset.selectedIndex == 0)
}
