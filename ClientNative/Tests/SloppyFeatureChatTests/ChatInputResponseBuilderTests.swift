import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Suite("Chat input response builder")
struct ChatInputResponseBuilderTests {
    @Test("builds selected and custom answers in question order")
    func buildsSelectedAndCustomAnswers() throws {
        let request = makeRequest()
        let answers = try ChatInputResponseBuilder.answers(
            for: request,
            drafts: [
                "framework": ChatInputDraftAnswer(selectedOptionID: "swiftui"),
                "notes": ChatInputDraftAnswer(customAnswer: "  Keep keyboard navigation  "),
            ]
        )

        #expect(answers == [
            ChatPlanInputAnswer(questionId: "framework", selectedOptionId: "swiftui"),
            ChatPlanInputAnswer(questionId: "notes", customAnswer: "Keep keyboard navigation"),
        ])
    }

    @Test("requires an answer for every question")
    func requiresEveryAnswer() {
        #expect(throws: ChatInputResponseBuilder.ValidationError.self) {
            try ChatInputResponseBuilder.answers(
                for: makeRequest(),
                drafts: ["framework": ChatInputDraftAnswer(selectedOptionID: "swiftui")]
            )
        }
    }

    @Test("rejects custom text when the question disables it")
    func rejectsDisallowedCustomText() {
        var request = makeRequest()
        request.questions[0].allowCustomAnswer = false

        #expect(throws: ChatInputResponseBuilder.ValidationError.self) {
            try ChatInputResponseBuilder.answers(
                for: request,
                drafts: [
                    "framework": ChatInputDraftAnswer(customAnswer: "Something else"),
                    "notes": ChatInputDraftAnswer(customAnswer: "No notes"),
                ]
            )
        }
    }

    private func makeRequest() -> ChatPlanInputRequest {
        ChatPlanInputRequest(
            id: "request-1",
            questions: [
                ChatPlanInputQuestion(
                    id: "framework",
                    question: "Which framework?",
                    options: [
                        ChatPlanInputOption(id: "swiftui", label: "SwiftUI"),
                        ChatPlanInputOption(id: "appkit", label: "AppKit"),
                    ]
                ),
                ChatPlanInputQuestion(
                    id: "notes",
                    question: "Anything else?",
                    options: [
                        ChatPlanInputOption(id: "none", label: "Nothing"),
                        ChatPlanInputOption(id: "tests", label: "Add tests"),
                    ]
                ),
            ]
        )
    }
}
