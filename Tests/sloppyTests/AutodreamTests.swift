import Foundation
import Logging
import Protocols
import Testing
@testable import sloppy

@Test
func visorAutodreamConfigDefaultsAndDecodes() throws {
    let defaults = CoreConfig.Visor.Autodream()
    #expect(defaults.enabled)
    #expect(defaults.intervalSeconds == 21_600)
    #expect(defaults.jitterSeconds == 1_800)
    #expect(defaults.sessionLimitPerRun == 10)
    #expect(defaults.model == nil)

    let data = Data(
        """
        {
          "autodream": {
            "enabled": false,
            "intervalSeconds": 18000,
            "jitterSeconds": 600,
            "sessionLimitPerRun": 3,
            "model": "openai-api:gpt-4o-mini"
          }
        }
        """.utf8
    )
    let decoded = try JSONDecoder().decode(CoreConfig.Visor.self, from: data)
    #expect(!decoded.autodream.enabled)
    #expect(decoded.autodream.intervalSeconds == 18_000)
    #expect(decoded.autodream.jitterSeconds == 600)
    #expect(decoded.autodream.sessionLimitPerRun == 3)
    #expect(decoded.autodream.model == "openai-api:gpt-4o-mini")
}

@Test
func autodreamSessionReviewPersistsReviewedSessionUpdatedAt() async throws {
    let config = CoreConfig.test
    let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/sloppy/Storage/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = SQLiteStore(path: config.sqlitePath, schemaSQL: schemaSQL, fallbackProjectsPath: nil)
    let reviewedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let sessionUpdatedAt = Date(timeIntervalSince1970: 1_700_001_000)
    let record = AutodreamSessionReviewRecord(
        agentId: "agent-a",
        sessionId: "session-a",
        status: "succeeded",
        reason: "autodream",
        sessionUpdatedAt: sessionUpdatedAt,
        reviewedAt: reviewedAt,
        lastError: nil
    )

    await store.saveAutodreamSessionReview(record)
    let loaded = await store.autodreamSessionReview(agentId: "agent-a", sessionId: "session-a")

    #expect(loaded?.agentId == "agent-a")
    #expect(loaded?.sessionId == "session-a")
    #expect(loaded?.status == "succeeded")
    #expect(loaded?.reason == "autodream")
    #expect(loaded?.sessionUpdatedAt == sessionUpdatedAt)
    #expect(loaded?.reviewedAt == reviewedAt)
    #expect(loaded?.lastError == nil)
}

@Test
func autodreamReviewEligibilitySkipsHeartbeatEmptyAndUnchangedSessions() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let agentID = "autodream-eligibility-\(UUID().uuidString.lowercased())"
    _ = try await service.createAgent(AgentCreateRequest(id: agentID, displayName: "Autodream", role: "Testing"))

    let timestamp = Date(timeIntervalSince1970: 1_700_002_000)
    let empty = AgentSessionSummary(
        id: "session-empty",
        agentId: agentID,
        title: "Empty",
        updatedAt: timestamp,
        messageCount: 0
    )
    let heartbeat = AgentSessionSummary(
        id: "session-heartbeat",
        agentId: agentID,
        title: "Heartbeat",
        updatedAt: timestamp,
        messageCount: 2,
        kind: .heartbeat
    )
    let chat = AgentSessionSummary(
        id: "session-chat",
        agentId: agentID,
        title: "Chat",
        updatedAt: timestamp,
        messageCount: 2
    )

    #expect(await service.shouldAutodreamReview(agentID: agentID, session: empty) == false)
    #expect(await service.shouldAutodreamReview(agentID: agentID, session: heartbeat) == false)
    #expect(await service.shouldAutodreamReview(agentID: agentID, session: chat) == true)

    await service.store.saveAutodreamSessionReview(AutodreamSessionReviewRecord(
        agentId: agentID,
        sessionId: chat.id,
        status: "succeeded",
        reason: "test",
        sessionUpdatedAt: timestamp
    ))
    #expect(await service.shouldAutodreamReview(agentID: agentID, session: chat) == false)

    let changed = AgentSessionSummary(
        id: chat.id,
        agentId: agentID,
        title: "Chat",
        updatedAt: timestamp.addingTimeInterval(60),
        messageCount: 3
    )
    #expect(await service.shouldAutodreamReview(agentID: agentID, session: changed) == true)
}

@Test
func autodreamRunnerSkipsOverlappingRuns() async {
    let gate = AutodreamRunnerGate()
    let runner = AutodreamRunner(
        config: AutodreamRunnerConfig(interval: .seconds(60), jitter: .seconds(0)),
        logger: .init(label: "test.autodream")
    ) {
        await gate.run()
    }

    async let first: Bool = runner.triggerImmediately()
    let started = await waitForAutodreamCondition {
        await gate.startedCount() == 1
    }
    #expect(started)

    let second = await runner.triggerImmediately()
    #expect(second == false)

    await gate.release()
    #expect(await first == true)
    #expect(await gate.startedCount() == 1)
}

private actor AutodreamRunnerGate {
    private var started = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run() async {
        started += 1
        if !released {
            await withCheckedContinuation { continuation in
                if released {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    func startedCount() -> Int {
        started
    }

    func release() {
        released = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private func waitForAutodreamCondition(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
    return await condition()
}
