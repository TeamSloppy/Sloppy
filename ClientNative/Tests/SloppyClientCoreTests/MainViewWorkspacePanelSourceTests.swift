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

    @Test("desktop main view keeps workspace inside the current window")
    func desktopMainViewKeepsWorkspaceInsideTheCurrentWindow() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let mainViewModel = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(mainViewModel.contains("var workspacePanelViewModel"))
        #expect(mainView.contains("@State private var isWorkspacePanelPresented = false"))
        #expect(mainView.contains("private var workspacePanelContainer: some View"))
        #expect(mainView.contains(".frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)"))
        #expect(mainView.contains("HStack(spacing: 0)"))
        #expect(mainView.contains(".frame(width: 380)"))
        #expect(mainView.contains(".frame(maxHeight: .infinity)"))
        #expect(mainView.contains(".inspector(isPresented: $isWorkspacePanelPresented)"))
        #expect(mainView.contains(".inspectorColumnWidth(min: 320, ideal: 380, max: 520)"))
        #expect(mainView.contains("WorkspacePanelView("))
        #expect(mainView.contains("private var workspacePanelMenu: some View"))
        #expect(mainView.contains("Label(\"Browser\", systemImage: workspacePanelMenuImage"))
        #expect(mainView.contains("Label(\"Files\", systemImage: workspacePanelMenuImage"))
        #expect(mainView.contains("Button(\"Hide Workspace\", systemImage: \"sidebar.right\")"))
        #expect(mainView.contains("private func openWorkspacePanel(mode: WorkspacePanelMode)"))
        #expect(mainView.contains("viewModel.workspacePanelViewModel.switchMode(mode)"))
        #expect(mainView.contains("isWorkspacePanelPresented = true"))
        #expect(mainView.contains("ToolbarItemGroup(placement: .primaryAction)"))
        #expect(mainView.contains("showsNavigationToolbar: idiom == .phone"))
    }

    @Test("chat view model exposes project workspace context")
    func chatViewModelExposesWorkspaceContext() throws {
        let chatViewModel = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")

        #expect(chatViewModel.contains("public var activeProjectIdForWorkspacePanel: String?"))
        #expect(chatViewModel.contains("public var activeProjectNameForWorkspacePanel: String?"))
    }

    @Test("chat tabs synchronize with the session created by the composer")
    func chatTabsSynchronizeWithTheSessionCreatedByTheComposer() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let mainViewModel = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(mainView.contains(".onChange(of: chatState.viewModel.selectedSessionId)"))
        #expect(mainView.contains("viewModel.synchronizeChatTab(tab.id)"))
        #expect(mainViewModel.contains("func synchronizeChatTab(_ tabID: WorkspaceTab.ID)"))
        #expect(mainViewModel.contains("key: .chatSession(sessionID)"))
        #expect(mainView.contains("if let activeChatViewModel"))
        #expect(mainView.contains("ChatComposerOverlay(\n                    viewModel: activeChatViewModel"))
        #expect(!mainView.contains("ChatComposerOverlay(\n                viewModel: viewModel.chatViewModel"))
    }
}
