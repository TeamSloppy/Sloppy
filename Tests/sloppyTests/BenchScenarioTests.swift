import Foundation
import Testing
import Protocols
@testable import sloppy

/// A fake agent whose memory is a plain list: it stores any statement containing "remember" and answers questions
/// from that list, so the runner's plumbing can be tested without a model.
private final class FakeMemoryDriver: BenchScenarioDriver, @unchecked Sendable {
    private struct State {
        var facts: [String] = []
        var sessions: [String] = []
        var removed: [String] = []
        var checkpoints = 0
    }
    private let state = NSLock()
    private var storage = State()
    var forgetsEverything = false

    private func mutate<T>(_ body: (inout State) -> T) -> T { state.withLock { body(&storage) } }
    var sessions: [String] { mutate { $0.sessions } }
    var checkpoints: Int { mutate { $0.checkpoints } }

    func prepareAgent() async throws -> String { "fake-agent" }

    func send(agentID: String, session: String, text: String, model: String?, mode: AgentChatMode) async throws -> BenchScenarioReply {
        let forgets = forgetsEverything
        let known: [String] = mutate { state in
            if !state.sessions.contains(session) { state.sessions.append(session) }
            if text.contains("Remember"), !forgets { state.facts.append(text) }
            return state.facts
        }
        if text.contains("Remember") { return BenchScenarioReply(text: "Noted.", events: []) }
        return BenchScenarioReply(text: "Known: " + known.joined(separator: " | "), events: [])
    }

    func checkpoint(agentID: String, session: String) async throws { mutate { $0.checkpoints += 1 } }
    func storedNotes(agentID: String) async -> [String] { mutate { $0.facts } }
    func documentTexts(agentID: String) async -> [String] { [] }
    func removeAgent(agentID: String) async { mutate { $0.removed.append(agentID) } }
}

private func spec(withCheckpoint: Bool = false) -> BenchScenarioSpec {
    BenchScenarioSpec(
        title: "t",
        steps: [
            .init(session: "teach", say: "Remember {{A}} is {{B}}.", id: nil, checkpointAfter: withCheckpoint ? true : nil, mode: nil),
            .init(session: "use", say: "What is {{A}}?", id: "ask", checkpointAfter: nil, mode: nil),
        ],
        checks: [.init(kind: .replyHas, step: "ask", token: "{{B}}")],
        trackedTokens: ["{{B}}"]
    )
}

@Test
func placeholdersExpandToTheSameRandomTokenEverywhereInOneRun() {
    var counter = 0
    let instantiated = spec().instantiated { counter += 1; return "TOK\(counter)" }

    let say = instantiated.steps[0].say
    #expect(say == "Remember TOK1 is TOK2.")
    #expect(instantiated.steps[1].say == "What is TOK1?")
    #expect(instantiated.checks[0].token == "TOK2")
    #expect(instantiated.trackedTokens == ["TOK2"])
}

@Test
func scenarioPassesWhenAFreshSessionRecallsThePlantedToken() async {
    let driver = FakeMemoryDriver()
    let runner = BenchScenarioRunner(driver: driver, configuration: BenchRunConfiguration())

    let result = await runner.runOne(scenario: BenchScenario(id: "s", spec: spec(withCheckpoint: true)), attempt: 1)

    #expect(result.status == .passed)
    #expect(driver.sessions == ["teach", "use"], "the question is asked from a different session")
    #expect(driver.checkpoints == 1)
    #expect(result.checkOutputTail?.contains("->sqlite") == true)
}

@Test
func scenarioFailsAndReportsWhereNothingWasStored() async {
    let driver = FakeMemoryDriver()
    driver.forgetsEverything = true
    let runner = BenchScenarioRunner(driver: driver, configuration: BenchRunConfiguration())

    let result = await runner.runOne(scenario: BenchScenario(id: "s", spec: spec()), attempt: 1)

    #expect(result.status == .failed)
    #expect(result.checkOutputTail?.contains("lacks") == true)
    #expect(result.checkOutputTail?.contains("->nowhere") == true)
}

@Test
func eachRunGetsFreshTokensSoRunsCannotContaminateEachOther() async {
    let driver = FakeMemoryDriver()
    let runner = BenchScenarioRunner(driver: driver, configuration: BenchRunConfiguration(attempts: 2, concurrency: 1))

    let results = await runner.run(scenarios: [BenchScenario(id: "s", spec: spec())])

    #expect(results.count == 2)
    #expect(results.allSatisfy { $0.status == .passed })
    let notes = await driver.storedNotes(agentID: "x")
    #expect(Set(notes).count == 2, "both attempts planted different tokens")
}

@Test
func replyLacksCheckCatchesAStaleValue() {
    let failures = BenchScenarioRunner.evaluate(
        [.init(kind: .replyHas, step: "q", token: "NEW"), .init(kind: .replyLacks, step: "q", token: "OLD")],
        replies: ["q": "NEW and OLD"]
    )

    #expect(failures.count == 1)
    #expect(failures[0].contains("still contains OLD"))
}

@Test
func shippedMemoryScenariosLoadAndReferenceExistingSteps() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("bench/memory")

    let scenarios = try BenchScenarioLoader.loadSuite(at: root)

    #expect(scenarios.count >= 5)
    for scenario in scenarios {
        #expect(scenario.spec.steps.contains { $0.session != scenario.spec.steps[0].session },
                "\(scenario.id) must use a second session")
        #expect(!scenario.spec.checks.isEmpty)
    }
}

@Test
func loaderRejectsChecksThatPointAtUnknownSteps() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scn-\(UUID().uuidString.prefix(6))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try #"{"title":"x","steps":[{"session":"a","say":"hi"}],"checks":[{"kind":"reply_has","step":"nope","token":"T"}]}"#
        .write(to: dir.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8)

    #expect(throws: BenchTaskError.self) { try BenchScenarioLoader.loadSuite(at: dir) }
}
