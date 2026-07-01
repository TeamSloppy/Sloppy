import Foundation
import Testing

@Suite("Main view workspace panel source")
struct MainViewWorkspacePanelSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("desktop main view exposes workspace as a tab-based surface")
    func desktopMainViewExposesWorkspaceAsATabBasedSurface() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(mainView.contains("var workspacePanelViewModel"))
        #expect(mainView.contains("var workspaceTabStates: [WorkspaceTab.ID: WorkspaceFilesTabState] = [:]"))
        #expect(mainView.contains("WorkspacePanelView("))
        #expect(mainView.contains("func openWorkspaceTabForSelectedContext()"))
    }

    @Test("chat view model exposes project workspace context")
    func chatViewModelExposesWorkspaceContext() throws {
        let chatViewModel = try source("Sources/SloppyFeatureChat/ChatScreenViewModel.swift")

        #expect(chatViewModel.contains("public var activeProjectIdForWorkspacePanel: String?"))
        #expect(chatViewModel.contains("public var activeProjectNameForWorkspacePanel: String?"))
    }
}
