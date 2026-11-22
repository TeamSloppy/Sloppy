import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Suite
struct SessionWatchTests {
    @Test
    func mcpWatchUsesExactStatusAndRetainsFailureReason() throws {
        let target = SessionWatchTool.target([
            "mcpTool": .string("ci.get_run"), "mcpArguments": .string(#"{"id":"run-42"}"#),
            "statusPath": .array([.string("run"), .string("status")]),
            "pendingStates": .array([.string("queued"), .string("running")]),
            "successStates": .array([.string("success")]), "failureStates": .array([.string("failed")]),
            "detailPath": .array([.string("run"), .string("error")])
        ])
        guard case .mcp(let source) = try #require(target) else {
            Issue.record("Expected an MCP watch")
            return
        }
        #expect(source.arguments["id"]?.asString == "run-42")
        #expect(source.evaluate(output(#"{"run":{"status":"queued"}}"#)) == .pending("queued"))
        #expect(source.evaluate(output(#"{"run":{"status":"running"}}"#)) == .pending("running"))
        #expect(source.evaluate(output(#"{"run":{"status":"failed","error":"Test target exited 1"}}"#))
            == .finished(.init(state: .failed, detail: "Status: failed.\nTest target exited 1")))
        #expect(source.evaluate(output(#"{"run":{"status":"almost success"}}"#))
            == .finished(.init(state: .unavailable, detail: "Unrecognized job status: almost success.")))
    }

    @Test
    func checkpointsPreservePendingStatusAndTerminalOutcomeAcrossReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-watch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionWatchStore(root: root)
        let now = Date(timeIntervalSince1970: 10_000)
        var watch = SessionWatch(id: UUID().uuidString, agentID: "agent", sessionID: "session", title: "Build",
            target: .process(id: "process"), intervalSeconds: 60, nextCheck: now)

        watch.apply(.pending("running"), now: now)
        watch.apply(.retry, now: now.addingTimeInterval(60))
        try store.save(watch)
        let recovered = SessionWatchStore(root: root)
        #expect(try recovered.ids() == [watch.id])
        let saved = try recovered.load(watch.id)
        #expect(saved.lastStatus == "running")
        #expect(saved.nextCheck == now.addingTimeInterval(180))
        #expect(saved.outcome == nil)

        let result = SessionWatch.Outcome(state: .failed, detail: "Exit code: 1.")
        watch.apply(.finished(result), now: saved.nextCheck)
        try recovered.save(watch)
        #expect(try store.load(watch.id).outcome == result)
        try recovered.remove(watch)
        #expect(try store.ids().isEmpty)
    }

    @Test
    func recoveredTerminalWatchPublishesOnceToItsSession() async throws {
        let config = CoreConfig.test
        let root = config.resolvedWorkspaceRootURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agentID = "job-watch"
        _ = try await first.createAgent(.init(id: agentID, displayName: "Watcher", role: "Test"))
        let session = try await first.createAgentSession(agentID: agentID, request: .init())
        let id = UUID().uuidString
        _ = try await first.appendAgentSessionEvents(agentID: agentID, sessionID: session.id, request: .init(events: [
            .init(agentId: agentID, sessionId: session.id, type: .runStatus,
                runStatus: .init(id: id, stage: .paused, label: "Watching job"))
        ]))
        await first.shutdownChannelPlugins()

        let storage = SessionWatchStore(root: root)
        let watch = SessionWatch(id: id, agentID: agentID, sessionID: session.id, title: "Build",
            target: .process(id: "exited"), intervalSeconds: 60, nextCheck: .distantPast,
            outcome: .init(state: .failed, detail: "Exit code: 7.\nCompiler output."))
        try storage.save(watch)
        let restarted = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await restarted.waitForStartup()
        try await waitForDelivery(storage)
        let firstDelivery = try await restarted.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(firstDelivery.events.compactMap(\.runStatus).last?.stage == .interrupted)
        #expect(firstDelivery.events.compactMap(\.message).flatMap(\.segments).compactMap(\.text)
            .contains { $0.contains("Compiler output.") })

        await restarted.stopSessionWatchRunners()
        try storage.save(watch)
        await restarted.recoverSessionWatchesIfNeeded()
        try await waitForDelivery(storage)
        let final = try await restarted.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(final.events.filter { $0.id == "job-watch-" + id }.count == 1)
        await restarted.shutdownChannelPlugins()
    }

    private func waitForDelivery(_ storage: SessionWatchStore) async throws {
        for _ in 0..<100 {
            if try storage.ids().isEmpty { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("Core did not deliver the restored watch")
    }

    private func output(_ text: String) -> JSONValue {
        .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])])])
    }
}
