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

    @Test("main view registers cmd j and mounts a root terminal overlay")
    func mainViewRegistersCmdJAndMountsRootTerminalOverlay() throws {
        let app = try source("Sources", "SloppyClient", "App", "SloppyClientApp.swift")
        let mainView = try source("Sources", "SloppyClient", "Navigation", "Main", "MainView.swift")

        #expect(app.contains("@FocusedValue(\\.toggleWorkspaceTerminal)"))
        #expect(!app.contains(".keyboardShortcut(\"j\", modifiers: [.command])"))
        #expect(mainView.contains(".keyboardShortcut(\"j\", modifiers: [.command])"))
        #expect(mainView.contains(".focusedSceneValue("))
        #expect(mainView.contains("viewModel.toggleTerminalForSelectedTab()"))
        #expect(mainView.contains("private var workspaceTerminalOverlay: some View"))
        #expect(mainView.contains(".overlay(alignment: .bottom)"))
        #expect(mainView.contains("WorkspaceTerminalDrawerView"))
    }

    @Test("terminal drawer limits its stable resize handle to touch platforms")
    func terminalDrawerLimitsItsStableResizeHandleToTouchPlatforms() throws {
        let drawer = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalDrawerView.swift")

        #expect(drawer.contains("#if os(iOS) || os(visionOS)"))
        #expect(drawer.contains("Capsule()"))
        #expect(drawer.contains("DragGesture"))
        #expect(drawer.contains("let startHeight = dragStartHeight ?? height"))
        #expect(drawer.contains("startHeight - value.translation.height"))
        #expect(drawer.contains("dragStartHeight = nil"))
        #expect(drawer.contains("Project directory unavailable"))
    }
}
