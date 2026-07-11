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
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let mainViewModel = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(mainViewModel.contains("var workspacePanelViewModel"))
        #expect(mainViewModel.contains("var tabStates: [WorkspaceTab.ID: WorkspaceTabState] = [:]"))
        #expect(mainViewModel.contains("WorkspaceTabState(contentState: .workspaceFiles(workspaceState))"))
        #expect(mainView.contains("WorkspacePanelView("))
        #expect(mainViewModel.contains("func openWorkspaceTabForSelectedContext()"))
    }

    @Test("chat view model exposes project workspace context")
    func chatViewModelExposesWorkspaceContext() throws {
        let chatViewModel = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")

        #expect(chatViewModel.contains("public var activeProjectIdForWorkspacePanel: String?"))
        #expect(chatViewModel.contains("public var activeProjectNameForWorkspacePanel: String?"))
    }
}
