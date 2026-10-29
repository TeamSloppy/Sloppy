import Foundation
import Protocols
import TauTUI
import Testing
@testable import sloppy

@Suite("TUI session stream recovery")
@MainActor
struct SloppyTUISessionStreamRecoveryTests {
    @Test("plan card shows a resolved address without requiring a slash command")
    func planCardLink() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let artifact = PlanArtifactRecord(
            projectId: "stream-test", projectName: "Stream test", agentId: fixture.agentID, sessionId: fixture.sessionID,
            messageEventId: "message", planName: "example", storageKind: "workspace", markdownPath: "/missing/plan.md",
            webUrl: "/v1/projects/stream-test/plans/example/web"
        )
        let text = fixture.screen.renderTimelineLines([.planArtifact(artifact)], width: 160)
            .map(SloppyTUISelectionRenderer.stripANSI).joined(separator: "\n")
        #expect(text.contains("http://"))
        #expect(text.contains("/v1/projects/stream-test/plans/example/web"))
        #expect(!text.contains("Run `/plan-web`"))
    }

    @Test("changes are rendered on the right during the first active turn")
    func liveChangesPane() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        let root = fixture.root.appendingPathComponent("code", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("App.swift")
        try "let value = 0\n".write(to: file, atomically: true, encoding: .utf8)
        screen.activeDiffBaseline = screen.sessionUndoManagers.makeBaseline(sessionID: screen.session.id, rootURL: root)
        screen.isPosting = true
        screen.sessionCards = [.message(role: .user, text: "Change the value")]
        screen.invalidateSessionTimelineCache()
        try "let value = 1\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(screen.updateSessionDiffPreview(rootURL: root))
        #expect(!screen.sessionUndoManagers.canUndo(sessionID: screen.session.id))
        let lines = screen.renderChatBody(width: 120, height: 30).map(SloppyTUISelectionRenderer.stripANSI)
        let changedLine = try #require(lines.first { $0.contains("+let value = 1") })
        #expect(try #require(changedLine.range(of: "+let value = 1")).lowerBound > (try #require(changedLine.firstIndex(of: "│"))))
        #expect(lines.filter { $0.contains("+let value = 1") }.count == 1)
        #expect(screen.scrollRegions.contains { $0.target == .workspaceDiff })
        try "let value = 2\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(screen.updateSessionDiffPreview(rootURL: root))
        #expect(screen.workspaceDiffPreview?.diff.contains("+let value = 2") == true)
        #expect(screen.workspaceDiffPreview?.diff.contains("+let value = 1") == false)
        #expect(screen.isPosting)
        let narrow = screen.renderChatBody(width: 80, height: 30).map(SloppyTUISelectionRenderer.stripANSI).joined(separator: "\n")
        #expect(narrow.contains("+let value = 2"))
        #expect(!narrow.contains("Changes · scroll"))
        screen.workspaceDiffPreview = nil
        screen.activeDiffBaseline = nil
        #expect(!screen.updateSessionDiffPreview(rootURL: root))
    }

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

    @Test("history recovery settles a completed turn and ignores its buffered updates")
    func recoversMissedCompletion() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        screen.streamSession()
        try await waitForSessionStream { screen.sessionStreamReadyKey != nil }
        await fixture.publishStatus(.responding, label: "Responding")
        try await waitForSessionStream { screen.liveRunStage == .responding }
        screen.setLiveAssistantDraftImmediately("Partial answer")
        screen.startThinkingAnimation()

        let store = await fixture.service.sessionStore
        let responding = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .runStatus,
            runStatus: .init(stage: .responding, label: "Responding")
        )
        let done = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .runStatus,
            runStatus: .init(stage: .done, label: "Done")
        )
        for continuation in await fixture.listeners().values { continuation.finish() }
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [
            responding,
            AgentSessionEvent(
                agentId: fixture.agentID, sessionId: fixture.sessionID, type: .message,
                message: .init(role: .assistant, segments: [.init(kind: .text, text: "Complete answer")])
            ),
            done,
        ])
        try await waitForSessionStream {
            screen.sessionStreamReadyKey != nil
                && screen.sessionCards.contains { $0.plainText.contains("Complete answer") }
        }

        #expect(screen.liveRunStage == nil)
        #expect(screen.liveRunStatusLine == nil)
        #expect(screen.liveAssistantDraft == nil)
        #expect(screen.thinkingAnimationTask == nil)
        #expect(screen.terminalTitleStatus() == "idle")
        let rendered = screen.render(width: 120).map(SloppyTUISelectionRenderer.stripANSI).joined(separator: "\n")
        #expect(rendered.contains("Complete answer"))
        #expect(!rendered.contains("Partial answer"))

        let key = screen.currentSessionStreamKey()
        _ = screen.handleSessionStreamUpdate(.init(kind: .sessionEvent, cursor: 1, event: responding), streamKey: key)
        _ = screen.handleSessionStreamUpdate(.init(kind: .sessionDelta, cursor: 2, message: "stale tail"), streamKey: key)
        #expect(screen.liveRunStage == nil)
        #expect(screen.liveAssistantDraft == nil)

        let nextRun = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .runStatus,
            runStatus: .init(stage: .thinking, label: "Thinking")
        )
        _ = screen.handleSessionStreamUpdate(.init(kind: .sessionEvent, cursor: 3, event: nextRun), streamKey: key)
        _ = screen.handleSessionStreamUpdate(.init(kind: .sessionDelta, cursor: 4, message: "Next answer"), streamKey: key)
        #expect(screen.liveRunStage == .thinking)
        #expect(screen.liveAssistantTarget == "Next answer")
    }

    @Test("replayed form events do not repeat the interactive form notice")
    func replayedFormDoesNotRepeatNotice() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        var button = AgentUIComponent(id: "root", component: .button)
        button.label = "Continue"
        button.action = "submit"
        let surface = AgentUISurfaceSnapshot(
            surfaceId: "form", revision: 1, fallbackText: "Continue", components: [button]
        )
        try surface.validate()
        let event = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .message,
            message: .init(role: .assistant, segments: [.init(kind: .text, text: "Continue")], uiSurface: surface)
        )
        let store = await fixture.service.sessionStore
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [event])
        let key = screen.currentSessionStreamKey()
        let update = AgentSessionStreamUpdate(kind: .sessionEvent, cursor: 1, event: event)

        #expect(screen.handleSessionStreamUpdate(update, streamKey: key))
        #expect(screen.transientNoticeLine == "Interactive form available: Ctrl+Y or /ui")
        await screen.reloadSession()
        try await waitForSessionStream { screen.lastRenderedSessionEventIDs.contains(event.id) }
        screen.showSystemNotice("Connection restored")

        #expect(screen.handleSessionStreamUpdate(update, streamKey: key))
        #expect(screen.transientNoticeLine == "Connection restored")
    }

    @Test("reloading old completion does not settle a newly submitted turn")
    func oldCompletionDoesNotSettleNewTurn() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let store = await fixture.service.sessionStore
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [
            AgentSessionEvent(
                agentId: fixture.agentID, sessionId: fixture.sessionID, type: .runStatus,
                runStatus: .init(stage: .done, label: "Done", createdAt: Date(timeIntervalSince1970: 1))
            ),
        ])
        fixture.screen.isPosting = true
        fixture.screen.taskStartedAt = Date()
        fixture.screen.setLiveAssistantDraftImmediately("New turn")
        await fixture.screen.reloadSession()
        #expect(fixture.screen.liveAssistantDraft == "New turn")
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
