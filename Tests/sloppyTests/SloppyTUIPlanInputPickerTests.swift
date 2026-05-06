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
