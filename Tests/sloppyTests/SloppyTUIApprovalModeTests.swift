import Foundation
import Protocols
import TauTUI
import Testing
@testable import sloppy

@Suite("TUI approval mode")
@MainActor
struct SloppyTUIApprovalModeTests {
    @Test func liveApprovalCardResolvesAndContinuesTheWaitingCall() async throws {
        let fixture = try await ApprovalFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        screen.streamSession()
        await screen.waitForCurrentSessionStreamReady()
        let invocation = Task {
            await fixture.service.requestToolApprovalIfNeeded(agentID: screen.agent.id, sessionID: screen.session.id,
                channelID: nil, topicID: nil, request: .init(tool: "agents.delegate_task"), requireApproval: true)
        }
        for _ in 0..<100 {
            if screen.pendingToolApproval != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let approval = try #require(screen.pendingToolApproval)
        #expect(screen.activePicker?.kind == .toolApproval)
        let detail = try await fixture.service.getAgentSession(agentID: screen.agent.id, sessionID: screen.session.id)
        #expect(detail.events.last?.runStatus?.details?.contains(approval.id) == true)
        await screen.applyToolApprovalDecision("approve_once")
        guard case .approved(let resolved) = await invocation.value else {
            Issue.record("The UI decision must resume the original invocation")
            return
        }
        #expect(resolved.id == approval.id)
        #expect(screen.pendingToolApproval == nil)
        await fixture.service.stop()
    }

    @Test func pickerReadsCoreAndSavesBothModes() async throws {
        let fixture = try await ApprovalFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        await screen.submit("/approvals")
        let picker = try #require(screen.activePicker)
        #expect(picker.kind == .approvalMode)
        #expect(picker.items.map(\.label) == ["Ask for approval", "Approve for me"])
        let option = try #require(picker.items.last)
        await screen.applyPickerItem(option, kind: picker.kind)
        #expect(try await fixture.service.getSessionApprovalPolicy(agentID: screen.agent.id, sessionID: screen.session.id).mode == .approveForMe)
        #expect(screen.approvalModeStatus == "Approve for me")
        #expect(screen.render(width: 140).joined(separator: "\n").contains("Approve for me"))

        await screen.selectApprovalMode(.askForApproval)
        #expect(try await fixture.service.getSessionApprovalPolicy(agentID: screen.agent.id, sessionID: screen.session.id).mode == .askForApproval)
    }

    @Test func restoresModeAndDoesNotLeakIntoAnotherChat() async throws {
        let fixture = try await ApprovalFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        let original = screen.session
        _ = try await fixture.service.setSessionApprovalPolicy(agentID: screen.agent.id, sessionID: original.id, policy: .init(mode: .approveForMe))
        await screen.refreshApprovalMode()
        #expect(screen.approvalModeStatus == "Approve for me")
        screen.session = try await fixture.service.createAgentSession(agentID: screen.agent.id, request: .init(separateChat: true, projectId: screen.project.id))
        await screen.refreshApprovalMode()
        #expect(screen.approvalModeStatus == "Ask for approval")
        screen.session = original
        await screen.refreshApprovalMode()
        #expect(screen.approvalModeStatus == "Approve for me")
        screen.resetToDraftSession()
        #expect(screen.approvalModeStatus == "Ask for approval")
    }

    @Test func draftModeIsSavedBeforeFirstMessageCanRun() async throws {
        let fixture = try await ApprovalFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        screen.resetToDraftSession()
        await screen.selectApprovalMode(.approveForMe)
        #expect(!screen.hasPersistedSession)
        #expect(try await screen.ensurePersistedSessionForMessage())
        #expect(screen.pendingApprovalModes.isEmpty)
        #expect(try await fixture.service.getSessionApprovalPolicy(agentID: screen.agent.id, sessionID: screen.session.id).mode == .approveForMe)
    }

    @Test func draftLoadsServerDefaultWithoutOverridingItsSnapshot() async throws {
        let fixture = try await ApprovalFixture.make()
        defer { fixture.stop() }
        var config = await fixture.service.getConfig()
        config.defaultChatApprovalMode = .approveForMe
        _ = try await fixture.service.updateConfig(config)
        let screen = fixture.screen
        screen.resetToDraftSession()
        await screen.refreshApprovalMode()
        #expect(screen.approvalModeStatus == "Approve for me")
        #expect(!screen.draftApprovalModeOverrides.contains(screen.approvalModeKey))
        #expect(try await screen.ensurePersistedSessionForMessage())
        #expect(try await fixture.service.getSessionApprovalPolicy(agentID: screen.agent.id, sessionID: screen.session.id).mode == .approveForMe)
    }

    @Test func failedSavePreservesConfirmedMode() async throws {
        let fixture = try await ApprovalFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        await screen.refreshApprovalMode()
        try await fixture.service.deleteAgentSession(agentID: screen.agent.id, sessionID: screen.session.id)
        await screen.selectApprovalMode(.approveForMe)
        #expect(screen.approvalModeStatus == "Ask for approval")
        #expect(screen.approvalModeSavingKeys.isEmpty)
        #expect(screen.localCards.contains { $0.block.plainText.contains("Could not save approval mode") })
    }

    @Test func failedDraftPolicyIsRetriedBeforeSending() async throws {
        let fixture = try await ApprovalFixture.make()
        defer { fixture.stop() }
        let screen = fixture.screen
        screen.resetToDraftSession()
        await screen.selectApprovalMode(.approveForMe)
        let workspace = await fixture.service.workspaceRootURL
        let policyURL = workspace.appendingPathComponent("session-approval-policies.json")
        try FileManager.default.createDirectory(at: policyURL, withIntermediateDirectories: true)
        do {
            _ = try await screen.ensurePersistedSessionForMessage()
            Issue.record("The first message must not proceed when its approval policy cannot be saved")
        } catch {}
        #expect(screen.pendingApprovalModes[screen.approvalModeKey] == .approveForMe)
        try FileManager.default.removeItem(at: policyURL)
        let createdAgain = try await screen.ensurePersistedSessionForMessage()
        #expect(!createdAgain)
        #expect(screen.pendingApprovalModes.isEmpty)
        #expect(try await fixture.service.getSessionApprovalPolicy(agentID: screen.agent.id, sessionID: screen.session.id).mode == .approveForMe)
    }
}

@MainActor
private struct ApprovalFixture {
    let service: CoreService
    let screen: SloppyTUIScreen
    let terminal: VirtualTerminal
    let tui: TUI
    let root: URL

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-approvals-\(UUID().uuidString)")
        var config = CoreConfig.test
        config.workspace = .init(name: "workspace", basePath: root.path)
        let service = CoreService(config: config, configPath: root.appendingPathComponent("sloppy.json").path,
                                  currentDirectory: root.path, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let project = try await service.createProject(.init(id: "approval-test", name: "Approval test")).project
        let agent = try await service.createAgent(.init(id: "approval-test", displayName: "Agent", role: "Test"))
        let session = try await service.createAgentSession(agentID: agent.id, request: .init(separateChat: true, projectId: project.id))
        let runtime = SloppyTUIRuntime(service: LocalSloppyTUIBackend(service: service), config: config,
                                      configPath: root.appendingPathComponent("sloppy.json").path, workspaceRoot: root, cwd: root.path)
        let terminal = VirtualTerminal(columns: 140, rows: 40)
        let tui = TUI(terminal: terminal)
        let screen = SloppyTUIScreen(runtime: runtime, project: project, agent: agent, session: session,
                                     hasPersistedSession: true, stateStore: .init(workspaceRoot: root), state: .init(),
                                     tui: tui, terminal: terminal)
        return Self(service: service, screen: screen, terminal: terminal, tui: tui, root: root)
    }

    func stop() {
        screen.stopBackgroundTasks()
        try? FileManager.default.removeItem(at: root)
    }
}
