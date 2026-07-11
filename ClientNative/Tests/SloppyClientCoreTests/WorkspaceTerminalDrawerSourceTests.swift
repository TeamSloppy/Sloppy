import Foundation
import Testing

@Suite("Workspace terminal drawer source")
struct WorkspaceTerminalDrawerSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("app registers cmd j and main view exposes the focused terminal action")
    func appRegistersCmdJAndMainViewExposesFocusedTerminalAction() throws {
        let app = try source("Sources", "SloppyClient", "App", "SloppyClientApp.swift")
        let mainView = try source("Sources", "SloppyClient", "Navigation", "Main", "MainView.swift")

        #expect(app.contains(".keyboardShortcut(\"j\", modifiers: [.command])"))
        #expect(app.contains("@FocusedValue(\\.toggleWorkspaceTerminal)"))
        #expect(mainView.contains(".focusedSceneValue("))
        #expect(mainView.contains("viewModel.toggleTerminalForSelectedTab()"))
        #expect(mainView.contains("WorkspaceTerminalDrawerView"))
    }

    @Test("terminal drawer view exposes resize handle and unavailable state")
    func terminalDrawerViewExposesResizeHandleAndUnavailableState() throws {
        let drawer = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalDrawerView.swift")

        #expect(drawer.contains("Capsule()"))
        #expect(drawer.contains("DragGesture"))
        #expect(drawer.contains("Project directory unavailable"))
    }
}
