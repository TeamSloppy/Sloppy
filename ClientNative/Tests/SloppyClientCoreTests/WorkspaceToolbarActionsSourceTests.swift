import Foundation
import Testing

@Suite("Workspace toolbar actions source")
struct WorkspaceToolbarActionsSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("workspace toolbar renders dedicated buttons and a separate tools menu")
    func workspaceToolbarRendersDedicatedButtonsAndToolsMenu() throws {
        let panelView = try source("Sources/SloppyClient/WorkspacePanelView.swift")

        #expect(panelView.contains("Open in Zed"))
        #expect(panelView.contains("Reveal in Finder"))
        #expect(panelView.contains("Tools"))
        #expect(panelView.contains("Menu {"))
    }

    @Test("workspace toolbar registers cmd+t to toggle the tools menu")
    func workspaceToolbarRegistersCmdT() throws {
        let panelView = try source("Sources/SloppyClient/WorkspacePanelView.swift")
        let panelVM = try source("Sources/SloppyClient/WorkspacePanelViewModel.swift")

        #expect(panelView.contains(".keyboardShortcut(\"t\", modifiers: [.command])"))
        #expect(panelVM.contains("var isToolsMenuPresented"))
        #expect(panelVM.contains("func toggleToolsMenu()"))
    }

    @Test("workspace toolbar computes selection-driven enablement")
    func workspaceToolbarComputesSelectionDrivenEnablement() throws {
        let panelVM = try source("Sources/SloppyClient/WorkspacePanelViewModel.swift")

        #expect(panelVM.contains("struct WorkspacePanelSelectionContext"))
        #expect(panelVM.contains("var canOpenInEditor"))
        #expect(panelVM.contains("var canRevealInFinder"))
        #expect(panelVM.contains("func selectionContext() -> WorkspacePanelSelectionContext"))
    }
}
