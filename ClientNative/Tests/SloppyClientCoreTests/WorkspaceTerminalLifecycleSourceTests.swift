import Foundation
import Testing

@Suite("Workspace terminal lifecycle source")
struct WorkspaceTerminalLifecycleSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main view model exposes terminal lifecycle hooks")
    func mainViewModelExposesTerminalLifecycleHooks() throws {
        let viewModel = try source("Sources", "SloppyClient", "Navigation", "Main", "MainViewModel.swift")

        #expect(viewModel.contains("var terminalSessions: [WorkspaceTab.ID: WorkspaceTerminalSession] = [:]"))
        #expect(viewModel.contains("func toggleTerminalForSelectedTab()"))
        #expect(viewModel.contains("func openTerminalForSelectedTab()"))
        #expect(viewModel.contains("terminalState.selectedPanel == .terminal"))
        #expect(viewModel.contains("func openBottomPanel(_ panel: WorkspaceBottomPanelKind)"))
        #expect(viewModel.contains("func closeTerminalForSelectedTab()"))
        #expect(viewModel.contains("func ensureTerminalSessionStarted(for tabID: WorkspaceTab.ID)"))
    }

    @Test("terminal session stores per-tab shell state and cleanup hooks")
    func terminalSessionStoresPerTabShellStateAndCleanupHooks() throws {
        let session = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalSession.swift")
        let viewModel = try source("Sources", "SloppyClient", "Navigation", "Main", "MainViewModel.swift")

        #expect(session.contains("final class WorkspaceTerminalSession"))
        #expect(session.contains("let id: UUID"))
        #expect(session.contains("let workingDirectory: URL"))
        #expect(session.contains("func startIfNeeded()"))
        #expect(session.contains("func terminate()"))
        #expect(viewModel.contains("terminalSessions[tabID]?.terminate()"))
        #expect(viewModel.contains("terminalSessions.removeValue(forKey: tabID)"))
    }
}
