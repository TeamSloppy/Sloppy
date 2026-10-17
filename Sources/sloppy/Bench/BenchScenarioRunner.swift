import Foundation
import Protocols

struct BenchScenarioReply: Sendable {
    var text: String
    var events: [AgentSessionEvent]
}

/// Drives one throwaway agent through a scenario and exposes what it stored.
protocol BenchScenarioDriver: Sendable {
    func prepareAgent() async throws -> String
    func send(agentID: String, session: String, text: String, model: String?, mode: AgentChatMode) async throws -> BenchScenarioReply
    func checkpoint(agentID: String, session: String) async throws
    /// Notes of the agent's SQLite memory entries.
    func storedNotes(agentID: String) async -> [String]
    /// Contents of the agent's curated markdown documents, including per-user overrides, when readable.
    func documentTexts(agentID: String) async -> [String]
    func removeAgent(agentID: String) async
}

struct BenchScenarioRunner: Sendable {
    let driver: any BenchScenarioDriver
    let configuration: BenchRunConfiguration
    var tokenGenerator: @Sendable () -> String = { BenchScenarioRunner.randomToken() }
    var onResult: (@Sendable (BenchRunResult) -> Void)?

    init(
        driver: any BenchScenarioDriver,
        configuration: BenchRunConfiguration,
        tokenGenerator: (@Sendable () -> String)? = nil,
        onResult: (@Sendable (BenchRunResult) -> Void)? = nil
    ) {
        self.driver = driver
        self.configuration = configuration
        if let tokenGenerator { self.tokenGenerator = tokenGenerator }
        self.onResult = onResult
    }

    static func randomToken() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    func run(scenarios: [BenchScenario]) async -> [BenchRunResult] {
        let jobs = scenarios.flatMap { scenario in (1...max(1, configuration.attempts)).map { (scenario, $0) } }
        let limit = max(1, configuration.concurrency)
        var results: [BenchRunResult] = []
        await withTaskGroup(of: BenchRunResult.self) { group in
            var iterator = jobs.makeIterator()
            var running = 0
            while running < limit, let (scenario, attempt) = iterator.next() {
                group.addTask { await self.runOne(scenario: scenario, attempt: attempt) }
                running += 1
            }
            while let result = await group.next() {
                results.append(result)
                onResult?(result)
                if let (scenario, attempt) = iterator.next() {
                    group.addTask { await self.runOne(scenario: scenario, attempt: attempt) }
                }
            }
        }
        return results.sorted { ($0.taskId, $0.attempt) < ($1.taskId, $1.attempt) }
    }

    func runOne(scenario: BenchScenario, attempt: Int) async -> BenchRunResult {
        let started = Date()
        let spec = scenario.spec.instantiated(using: tokenGenerator)
        let modelLabel = configuration.model ?? "default"
        func result(
            _ status: BenchStatus, events: [AgentSessionEvent] = [], agentSeconds: Double = 0,
            detail: String? = nil, error: String? = nil
        ) -> BenchRunResult {
            BenchRunResult(
                taskId: scenario.id, tags: spec.tags, model: modelLabel, attempt: attempt, status: status,
                checkExitCode: nil, checkOutputTail: detail, agentSeconds: agentSeconds,
                totalSeconds: Date().timeIntervalSince(started), metrics: BenchMetrics.derive(from: events),
                diff: nil, error: error
            )
        }

        let agentID: String
        do {
            agentID = try await driver.prepareAgent()
        } catch {
            return result(.error, error: "agent: \(error.localizedDescription)")
        }
        defer { if !configuration.keepSandboxes { Task { [driver] in await driver.removeAgent(agentID: agentID) } } }

        let agentStarted = Date()
        struct Transcript: Sendable {
            var events: [AgentSessionEvent] = []
            var replies: [String: String] = [:]
        }
        let transcript: Transcript
        do {
            transcript = try await BenchRunner.withTimeout(seconds: TimeInterval(spec.timeoutSeconds)) {
                var collected = Transcript()
                for step in spec.steps {
                    let reply = try await driver.send(
                        agentID: agentID, session: step.session, text: step.say, model: configuration.model,
                        mode: step.mode.flatMap(AgentChatMode.init(rawValue:)) ?? configuration.mode
                    )
                    collected.events += reply.events
                    if let id = step.id { collected.replies[id] = reply.text }
                    if step.checkpointAfter == true { try await driver.checkpoint(agentID: agentID, session: step.session) }
                }
                return collected
            }
        } catch is BenchRunner.BenchTimeoutError {
            return result(.timeout, agentSeconds: Date().timeIntervalSince(agentStarted))
        } catch {
            return result(.error, agentSeconds: Date().timeIntervalSince(agentStarted), error: "agent: \(error.localizedDescription)")
        }
        let events = transcript.events
        let replies = transcript.replies
        let agentSeconds = Date().timeIntervalSince(agentStarted)

        let failures = Self.evaluate(spec.checks, replies: replies)
        let stored = await storageReport(tokens: spec.trackedTokens, agentID: agentID)
        let detail = (failures + (stored.isEmpty ? [] : ["stored: \(stored)"])).joined(separator: "\n")
        return result(failures.isEmpty ? .passed : .failed, events: events, agentSeconds: agentSeconds, detail: detail.isEmpty ? nil : detail)
    }

    /// One line per failed check. Matching is exact substring search for a planted random token.
    static func evaluate(_ checks: [BenchScenarioSpec.Check], replies: [String: String]) -> [String] {
        checks.compactMap { check in
            let reply = replies[check.step] ?? ""
            switch check.kind {
            case .replyHas:
                return reply.contains(check.token) ? nil : "reply to '\(check.step)' lacks \(check.token): \(reply.prefix(160))"
            case .replyLacks:
                return reply.contains(check.token) ? "reply to '\(check.step)' still contains \(check.token): \(reply.prefix(160))" : nil
            }
        }
    }

    private func storageReport(tokens: [String], agentID: String) async -> String {
        guard !tokens.isEmpty else { return "" }
        let notes = await driver.storedNotes(agentID: agentID)
        let documents = await driver.documentTexts(agentID: agentID)
        return tokens.map { token in
            var places: [String] = []
            if documents.contains(where: { $0.contains(token) }) { places.append("docs") }
            if notes.contains(where: { $0.contains(token) }) { places.append("sqlite") }
            return "\(token)->\(places.isEmpty ? "nowhere" : places.joined(separator: "+"))"
        }.joined(separator: " ")
    }
}
