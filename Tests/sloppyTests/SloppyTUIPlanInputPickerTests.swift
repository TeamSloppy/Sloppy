import Foundation
import Protocols
import TauTUI
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
func planInputPickerBuildsOnePagePerQuestion() throws {
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

    #expect(picker.items.map(\.label) == ["Small", "Large"])
    #expect(picker.title == "1/2 · Scope")
    #expect(picker.detailText == "How much?")
    #expect(SloppyTUIPlanInputPicker.answerRequest(for: picker.items[1], request: request) == nil)

    let next = try #require(SloppyTUIPlanInputPicker.picker(for: request, questionIndex: 1))
    #expect(next.items.map(\.label) == ["Safe", "Bold"])
    #expect(next.title == "2/2 · Risk")
    let payload = try #require(SloppyTUIPlanInputPicker.answerRequest(
        for: next.items[0], request: request, previousAnswers: ["scope": "large"]))
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
    // A newer question supersedes an older unanswered request. Resolving it must
    // not bring the older form back into the composer.
    #expect(SloppyTUIPlanInputState.latestUnansweredRequest(in: [events[0], events[2],
        AgentSessionEvent(agentId: "a", sessionId: "s", type: .inputResponse,
            inputResponse: .init(requestId: second.id, status: .answered, answers: [], userId: "tui"))
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

@Suite("TUI question pages")
@MainActor
struct SloppyTUIPlanInputFlowTests {
    @Test func pagesPreserveAnswersAcrossReloadAndSubmitOnce() async throws {
        let fixture = try await PlanInputFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        let request = fixture.request
        await screen.reloadSession()
        let first = try #require(screen.activePicker)
        #expect(first.title == "1/2 · Scope")
        #expect(first.items.count == 2)
        await screen.answerPlanInput(with: first.items[1])
        #expect(screen.planInputDraft?.questionIndex == 1)
        let frame = screen.render(width: 100).map(SloppyTUISelectionRenderer.stripANSI).joined(separator: "\n")
        #expect(frame.contains("2/2 · Risk"))
        #expect(frame.contains("How risky?"))
        #expect(!frame.contains("Large / Safe"))
        let beforeSubmit = try await fixture.service.getAgentSession(agentID: screen.agent.id, sessionID: screen.session.id)
        #expect(beforeSubmit.events.compactMap(\.inputResponse).isEmpty)

        screen.activePicker?.selectedIndex = 1
        await screen.reloadSession()
        #expect(screen.planInputDraft?.questionIndex == 1)
        #expect(screen.planInputDraft?.answers == ["scope": "large"])
        #expect(screen.activePicker?.selectedIndex == 1)
        #expect(screen.handleActivePicker(input: .key(.arrowLeft, modifiers: [])))
        #expect(screen.planInputDraft?.questionIndex == 0)
        #expect(screen.activePicker?.selectedIndex == 1)
        let previous = try #require(screen.activePicker)
        await screen.answerPlanInput(with: previous.items[0])
        let last = try #require(screen.activePicker)
        #expect(last.title == "2/2 · Risk")
        await screen.answerPlanInput(with: last.items[1])

        let detail = try await fixture.service.getAgentSession(agentID: screen.agent.id, sessionID: screen.session.id)
        let responses = detail.events.compactMap(\.inputResponse).filter { $0.requestId == request.id }
        #expect(responses.count == 1)
        #expect(responses.first?.answers == [
            .init(questionId: "scope", selectedOptionId: "small"),
            .init(questionId: "risk", selectedOptionId: "bold"),
        ])
        await screen.reloadSession()
        #expect(screen.pendingPlanInputRequest == nil)
        #expect(screen.activePicker == nil)
    }

    @Test func savedAnswerIsNotReopenedWhenSubmissionFails() async throws {
        let fixture = try await PlanInputFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        _ = try await fixture.service.appendAgentSessionEvents(agentID: screen.agent.id, sessionID: screen.session.id,
            request: .init(events: [.init(agentId: screen.agent.id, sessionId: screen.session.id, type: .inputResponse,
                inputResponse: .init(requestId: fixture.request.id, status: .cancelled, answers: [], userId: "another-client"))]))
        // Simulate a stale TUI submitting after another client has already answered.
        screen.updatePendingPlanInputRequest(fixture.request)
        await screen.submitPlanInput(request: fixture.request,
            payload: .init(status: .cancelled, answers: [], userId: "tui"), busyLabel: "Submitting")
        #expect(screen.pendingPlanInputRequest == nil)
        #expect(screen.activePicker == nil)
        #expect(screen.localCards.contains { $0.block.plainText.contains("Input answer is saved") })
    }

    @Test func questionTextWrapsAndMouseRowsFollowThePrompt() async throws {
        let fixture = try await PlanInputFixture.make()
        defer { fixture.stop() }
        var request = fixture.request
        request.questions[0].question = String(repeating: "Choose the intended scope. ", count: 6)
        fixture.screen.updatePendingPlanInputRequest(request)
        let picker = try #require(fixture.screen.activePicker)
        let lines = SloppyTUITheme.pickerLines(width: 60, picker: picker, maxVisible: 9)
        let details = SloppyTUITheme.pickerDetailLines(width: 60, picker: picker)
        #expect(details.count > 1)
        #expect(lines.allSatisfy { VisibleWidth.measure($0) <= 60 })
        fixture.screen.hitRegions = []
        fixture.screen.registerPickerHitRegions(picker: picker, startRow: 2, width: 60,
            action: { .activePicker(index: $0) })
        #expect(fixture.screen.hitRegions.first?.row == 3 + details.count)
        fixture.screen.scrollRegions = []
        fixture.screen.registerPickerScrollRegion(picker: picker, startRow: 2, width: 60, target: .activePicker)
        #expect(fixture.screen.scrollRegions.first?.endRow == 2 + lines.count)
    }
}

@MainActor
private struct PlanInputFixture {
    let service: CoreService
    let screen: SloppyTUIScreen
    let terminal: VirtualTerminal
    let tui: TUI
    let root: URL
    let request: PlanInputRequest

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-input-pages-\(UUID().uuidString)")
        var config = CoreConfig.test
        config.workspace = .init(name: "workspace", basePath: root.path)
        let service = CoreService(config: config, configPath: root.appendingPathComponent("sloppy.json").path,
                                  currentDirectory: root.path, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let project = try await service.createProject(.init(id: "input-test", name: "Input test")).project
        let agent = try await service.createAgent(.init(id: "input-test", displayName: "Agent", role: "Test"))
        let session = try await service.createAgentSession(agentID: agent.id, request: .init(separateChat: true, projectId: project.id))
        let runtime = SloppyTUIRuntime(service: LocalSloppyTUIBackend(service: service), config: config,
            configPath: root.appendingPathComponent("sloppy.json").path, workspaceRoot: root, cwd: root.path)
        let terminal = VirtualTerminal(columns: 100, rows: 40)
        let tui = TUI(terminal: terminal)
        let screen = SloppyTUIScreen(runtime: runtime, project: project, agent: agent, session: session,
            hasPersistedSession: true, stateStore: .init(workspaceRoot: root), state: .init(), tui: tui, terminal: terminal)
        let request = PlanInputRequest(questions: [
            .init(id: "scope", header: "Scope", question: "How much?",
                options: [.init(id: "small", label: "Small"), .init(id: "large", label: "Large")]),
            .init(id: "risk", header: "Risk", question: "How risky?",
                options: [.init(id: "safe", label: "Safe"), .init(id: "bold", label: "Bold")]),
        ])
        _ = try await service.appendAgentSessionEvents(agentID: agent.id, sessionID: session.id,
            request: .init(events: [.init(agentId: agent.id, sessionId: session.id, type: .inputRequest, inputRequest: request)]))
        return .init(service: service, screen: screen, terminal: terminal, tui: tui, root: root, request: request)
    }

    func stop() {
        screen.stopBackgroundTasks()
        Task {
            await service.stop()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
