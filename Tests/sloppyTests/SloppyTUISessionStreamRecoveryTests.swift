import Foundation
import Protocols
import TauTUI
import Testing
@testable import sloppy

@Suite("TUI session stream recovery")
@MainActor
struct SloppyTUISessionStreamRecoveryTests {
    #if !os(Windows)
    @Test("runtime.exec persists and streams an OS stop with the command still visible")
    func runtimeExecPublishesStoppedProcess() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let arguments: [String: JSONValue] = [
            "command": .string("/bin/sh"),
            "arguments": .array([.string("-c"), .string("echo $$ > child.pid; kill -STOP $$; printf resumed")]),
            "timeoutMs": .number(10_000)
        ]
        let call = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .toolCall,
            toolCall: .init(tool: "runtime.exec", arguments: arguments)
        )
        let store = await fixture.service.sessionStore
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [call])
        fixture.screen.streamSession()
        try await waitForSessionStream { fixture.screen.sessionStreamReadyKey != nil }
        await fixture.screen.reloadSession()
        let execution = await fixture.service.toolExecution
        let run = Task {
            await execution.invoke(
                agentID: fixture.agentID, sessionID: fixture.sessionID,
                request: .init(tool: "runtime.exec", arguments: arguments), policy: AgentToolsPolicy(),
                currentDirectoryURL: fixture.root
            )
        }
        defer { run.cancel() }
        try await waitForSessionStream { fixture.screen.liveRunStatusLine?.contains("Process stopped by OS") == true }
        let text = try #require(fixture.screen.toolActivityStatusLine())
        #expect(text.contains("child.pid"))
        #expect(text.contains("PID"))
        let detail = try await fixture.service.getAgentSession(agentID: fixture.agentID, sessionID: fixture.sessionID)
        #expect(detail.events.contains { $0.runStatus?.label == "Process stopped by OS" })
        // Cancellation exercises the existing timeout/termination path for a stopped child.
        run.cancel()
        let result = await run.value
        #expect(result.error?.code == "tool_timeout")
    }
    #endif

    @Test("a rejected send preserves the running command, elapsed time and terminal status")
    func failedSendPreservesActiveTool() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        // Keep a real cached runtime session: cold recovery correctly reconciles
        // an abandoned tool call and is a different scenario from a failed send.
        _ = try await fixture.service.postAgentSessionMessage(
            agentID: fixture.agentID, sessionID: fixture.sessionID,
            request: .init(userId: "tui", content: "Warm up the mock runtime")
        )
        #expect(try await fixture.service.hasLiveAgentRuntimeSession(agentID: fixture.agentID, sessionID: fixture.sessionID))
        let started = Date()
        let call = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .toolCall,
            createdAt: started,
            toolCall: .init(tool: "runtime.exec", arguments: [
                "command": .string("ffmpeg"), "arguments": .array([.string("-nostdin"), .string("input.png")])
            ])
        )
        let store = await fixture.service.sessionStore
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [call])
        await fixture.service.reportSessionRunStatus(
            agentID: fixture.agentID, sessionID: fixture.sessionID,
            status: .init(stage: .searching, label: "Process stopped by OS", details: "runtime.exec · PID 123")
        )
        await screen.reloadSession()
        #expect(screen.pendingToolCalls.map(\.id) == [call.id])
        screen.streamSession()
        try await waitForSessionStream { screen.sessionStreamReadyKey != nil }

        // Core rejects an empty message before starting a model turn.
        await screen.sendMessage("", context: nil, uploads: [], clearsPendingInputsOnSuccess: false)

        #expect(screen.localCards.contains { $0.block.plainText.contains("Message failed:") })
        #expect(!screen.isPosting)
        #expect(screen.terminalTitleStatus() == "searching")
        #expect(screen.liveRunStatusLine?.contains("Process stopped by OS") == true)
        let text = try #require(screen.toolActivityStatusLine(now: started.addingTimeInterval(125)))
        #expect(text.contains("ffmpeg -nostdin input.png"))
        #expect(text.contains("PID 123"))
        #expect(text.contains(SloppyTUITheme.elapsed(125)))
        screen.refreshStaticChrome()
        #expect(SloppyTUISelectionRenderer.stripANSI(screen.status.text).contains("ffmpeg"))

        screen.applySessionRunStatus(.init(stage: .done, label: "Done"))
        screen.restoreSessionRunStatusAfterSend()
        #expect(screen.pendingToolCalls.isEmpty)
        #expect(screen.toolActivityStatusLine() == nil)
        #expect(screen.terminalTitleStatus() == "idle")
    }

    @Test("tool results clear only their matching active call after history reload")
    func toolResultsAreCorrelated() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        let first = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .toolCall,
            toolCall: .init(tool: "runtime.exec", arguments: ["command": .string("first")])
        )
        let second = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .toolCall,
            toolCall: .init(tool: "runtime.exec", arguments: ["command": .string("second")])
        )
        let store = await fixture.service.sessionStore
        _ = try store.appendEvents(agentID: fixture.agentID, sessionID: fixture.sessionID, events: [
            .init(agentId: fixture.agentID, sessionId: fixture.sessionID, type: .runStatus,
                  runStatus: .init(stage: .searching, label: "Executing tool")), first, second,
            .init(agentId: fixture.agentID, sessionId: fixture.sessionID, type: .toolResult,
                  toolResult: .init(tool: "runtime.exec", ok: true, callEventId: first.id))
        ])
        await fixture.screen.reloadSession()
        #expect(fixture.screen.pendingToolCalls.map(\.id) == [second.id])
        #expect(fixture.screen.toolActivityStatusLine()?.contains("second") == true)
        let result = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .toolResult,
            toolResult: .init(tool: "runtime.exec", ok: true, callEventId: second.id)
        )
        _ = fixture.screen.handleSessionStreamUpdate(
            .init(kind: .sessionEvent, cursor: 1, event: result), streamKey: fixture.screen.currentSessionStreamKey()
        )
        #expect(fixture.screen.pendingToolCalls.isEmpty)
    }

    @Test("switching to a draft clears the previous session's active process")
    func draftClearsRunActivity() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        fixture.screen.applySessionRunStatus(.init(stage: .searching, label: "Process stopped by OS"))
        fixture.screen.trackPendingToolCall(.init(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .toolCall,
            toolCall: .init(tool: "runtime.exec", arguments: ["command": .string("ffmpeg")])
        ))
        fixture.screen.resetToDraftSession()
        fixture.screen.restoreSessionRunStatusAfterSend()
        #expect(fixture.screen.latestSessionRunStatus == nil)
        #expect(fixture.screen.pendingToolCalls.isEmpty)
        #expect(fixture.screen.terminalTitleStatus() == "draft")
    }

    @Test("completed turns and imported history do not acquire pending tools")
    func historicalCallsAreNotActive() async throws {
        let fixture = try await SessionStreamFixture.make()
        defer { fixture.stop() }
        var call = AgentSessionEvent(
            agentId: fixture.agentID, sessionId: fixture.sessionID, type: .toolCall,
            toolCall: .init(tool: "runtime.exec", arguments: ["command": .string("historical")])
        )
        fixture.screen.applySessionRunStatus(.init(stage: .done, label: "Done"))
        fixture.screen.trackPendingToolCall(call)
        #expect(fixture.screen.pendingToolCalls.isEmpty)
        fixture.screen.applySessionRunStatus(.init(stage: .searching, label: "Executing tool"))
        call.importOrigin = .init(source: .hermes, sourceID: "import", externalID: "old-call", jobID: "job")
        fixture.screen.trackPendingToolCall(call, replaying: true)
        #expect(fixture.screen.pendingToolCalls.isEmpty)
    }

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
        config.onboarding.completed = true
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
