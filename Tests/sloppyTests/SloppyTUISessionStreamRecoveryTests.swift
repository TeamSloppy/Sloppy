import Foundation
import Protocols
import TauTUI
import Testing
@testable import sloppy

@Suite("TUI session stream recovery")
@MainActor
struct SloppyTUISessionStreamRecoveryTests {
    @Test("updates resume after disconnection before the agent turn completes")
    func reconnectsDuringActiveTurn() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        screen.streamSession()
        try await waitForSessionStream { screen.sessionStreamReadyKey != nil }

        let gate = AsyncStream<Void>.makeStream()
        var turnFinished = false
        let agentTurn = Task {
            await fixture.publishStatus(.responding, label: "Responding")
            for await _ in gate.stream { break }
            guard !Task.isCancelled else { return }
            turnFinished = true
            await fixture.publishStatus(.interrupted, label: "Stopped")
        }
        defer {
            agentTurn.cancel()
            gate.continuation.finish()
        }
        try await waitForSessionStream { screen.liveRunStage == .responding }

        let originalListeners = await fixture.listeners()
        #expect(originalListeners.count == 1)
        for continuation in originalListeners.values { continuation.finish() }
        let store = await fixture.service.sessionStore
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [
            AgentSessionEvent(
                agentId: fixture.agentID, sessionId: fixture.sessionID, type: .message,
                message: .init(role: .assistant, segments: [.init(kind: .text, text: "Saved during disconnection")])
            )
        ])

        try await waitForSessionStream {
            let current = await fixture.listeners()
            return !current.isEmpty && Set(current.keys).isDisjoint(with: originalListeners.keys)
                && screen.sessionStreamReadyKey != nil
        }
        await fixture.publishStatus(.searching, label: "Reading project files")
        await fixture.service.publishLiveSessionDelta(
            agentID: fixture.agentID, sessionID: fixture.sessionID,
            chunk: "Update received while the agent is still working."
        )
        try await waitForSessionStream {
            screen.liveRunStage == .searching
                && screen.liveAssistantDraft?.contains("still working") == true
                && screen.sessionCards.contains { $0.plainText.contains("Saved during disconnection") }
        }

        #expect(!turnFinished)
        #expect(screen.render(width: 120).joined(separator: "\n").contains("still working"))
        gate.continuation.yield(())
        await agentTurn.value
        try await waitForSessionStream { screen.liveRunStage == nil }
    }

    @Test("stopping the TUI cancels recovery and releases readiness waiters")
    func stopCancelsRecovery() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        screen.streamSession()
        try await waitForSessionStream { screen.sessionStreamReadyKey != nil }
        let task = try #require(screen.streamTask)
        for continuation in await fixture.listeners().values { continuation.finish() }
        try await waitForSessionStream { screen.sessionStreamReadyKey == nil }

        let waiter = Task { await screen.waitForCurrentSessionStreamReady() }
        await Task.yield()
        screen.stopBackgroundTasks()
        await task.value
        await waiter.value

        #expect(screen.streamTask == nil)
        #expect(screen.sessionStreamReadyKey == nil)
        try await waitForSessionStream { await fixture.listeners().isEmpty }
    }

    @Test("an explicitly closed session is not reconnected")
    func closedSessionStopsSubscription() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        screen.streamSession()
        try await waitForSessionStream { screen.sessionStreamReadyKey != nil }

        await fixture.service.publishLiveSessionClosed(
            agentID: fixture.agentID, sessionID: fixture.sessionID, message: "Session removed"
        )
        try await waitForSessionStream { screen.streamTask == nil }

        #expect(screen.sessionStreamReadyKey == nil)
        #expect(screen.localCards.contains { $0.block.plainText.contains("Session removed") })
    }
}

@MainActor
private struct SessionStreamFixture {
    let service: CoreService
    let screen: SloppyTUIScreen
    let terminal: VirtualTerminal
    let tui: TUI
    let root: URL
    let agentID: String
    let sessionID: String

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-tui-stream-\(UUID().uuidString)", isDirectory: true)
        var config = CoreConfig.test
        config.workspace = .init(name: "workspace", basePath: root.path)
        let service = CoreService(
            config: config, configPath: root.appendingPathComponent("sloppy.json").path,
            currentDirectory: root.path, persistenceBuilder: InMemoryCorePersistenceBuilder()
        )
        let project = try await service.createProject(.init(id: "stream-test", name: "Stream test")).project
        let agent = try await service.createAgent(.init(id: "stream-test", displayName: "Agent", role: "Test"))
        let session = try await service.createAgentSession(
            agentID: agent.id, request: .init(title: "Stream test", projectId: project.id)
        )
        let runtime = SloppyTUIRuntime(
            service: LocalSloppyTUIBackend(service: service), config: config,
            configPath: root.appendingPathComponent("sloppy.json").path,
            workspaceRoot: root, cwd: root.path
        )
        let terminal = VirtualTerminal(columns: 120, rows: 40)
        let tui = TUI(terminal: terminal)
        let screen = SloppyTUIScreen(
            runtime: runtime, project: project, agent: agent, session: session,
            hasPersistedSession: true, stateStore: .init(workspaceRoot: root), state: .init(),
            tui: tui, terminal: terminal
        )
        return Self(service: service, screen: screen, terminal: terminal, tui: tui,
                    root: root, agentID: agent.id, sessionID: session.id)
    }

    func listeners() async -> [UUID: AsyncStream<AgentSessionStreamUpdate>.Continuation] {
        await service.liveSessionStreamContinuations["\(agentID)::\(sessionID)"] ?? [:]
    }

    func publishStatus(_ stage: AgentRunStage, label: String) async {
        await service.publishLiveSessionUpdate(
            agentID: agentID, sessionID: sessionID,
            update: .init(kind: .sessionEvent, cursor: 0,
                          event: AgentSessionEvent(agentId: agentID, sessionId: sessionID, type: .runStatus,
                                                   runStatus: .init(stage: stage, label: label)))
        )
    }

    func stop() {
        screen.stopBackgroundTasks()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func waitForSessionStream(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            throw SessionStreamTestTimeout()
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private struct SessionStreamTestTimeout: Error {}
