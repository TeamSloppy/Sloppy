import Foundation
import Testing

@Suite("Main view workspace panel source")
struct MainViewWorkspacePanelSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try mainViewAwareSourceContents(at: packageRoot.appendingPathComponent(path))
    }

    @Test("desktop main view keeps workspace inside the current window")
    func desktopMainViewKeepsWorkspaceInsideTheCurrentWindow() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let mainViewModel = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(mainViewModel.contains("var workspaceDockState: WorkspaceDockState"))
        #expect(mainView.contains("WorkspaceResizableSidePanel(state: viewModel.workspaceDockState)"))
        #expect(mainView.contains("WorkspaceDockView(state: viewModel.workspaceDockState"))
        #expect(mainView.contains("viewModel.workspaceDockState.toggleVisibility()"))
        #expect(mainView.contains(".inspector(isPresented: Binding("))
        #expect(mainView.contains("WorkspacePanelView("))
        #expect(mainView.contains("var workspaceSidePanelButton: some View"))
        #expect(mainView.contains("ToolbarItemGroup(placement: .primaryAction)"))
        #expect(mainView.contains("showsNavigationToolbar: idiom == .phone"))
    }

    @Test("desktop side panel toolbar button is circular")
    func desktopSidePanelToolbarButtonIsCircular() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let buttonStart = try #require(mainView.range(
            of: "var workspaceSidePanelButton: some View"
        ))
        let buttonEnd = try #require(mainView.range(
            of: "private func openWorkspacePanel(mode: WorkspacePanelMode)",
            range: buttonStart.upperBound..<mainView.endIndex
        ))
        let button = mainView[buttonStart.lowerBound..<buttonEnd.lowerBound]

        #expect(button.contains(".frame(width: 24, height: 24)"))
        #expect(button.contains(".buttonStyle(.glass)"))
        #expect(button.contains(".buttonBorderShape(.circle)"))
        #expect(!button.contains(".buttonStyle(.plain)"))
    }

    @Test("side panel tabs expose all supported destinations")
    func sidePanelOpensCodexStylePicker() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let picker = try source("Sources/SloppyClient/Workspace/Panel/WorkspacePanelView.swift")

        #expect(picker.contains("enum WorkspaceSidePanelItem"))
        #expect(picker.contains("case review"))
        #expect(picker.contains("case terminal"))
        #expect(picker.contains("case browser"))
        #expect(picker.contains("case files"))
        #expect(picker.contains("case sideChat"))
        #expect(picker.contains("ForEach(WorkspaceSidePanelItem.allCases)"))
        #expect(picker.contains("workspace.side-panel.picker"))
        #expect(mainView.contains("viewModel.openBottomPanel(.terminal)"))
        #expect(mainView.contains("viewModel.openWorkspaceDockTab(.sideChat)"))
        #expect(mainView.contains("ChatComposerOverlay("))
        #expect(mainView.contains("viewModel.workspaceDockState.toggleVisibility()"))
    }

    @Test("chat view model exposes project workspace context")
    func chatViewModelExposesWorkspaceContext() throws {
        let chatViewModel = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")

        #expect(chatViewModel.contains("public var activeProjectIdForWorkspacePanel: String?"))
        #expect(chatViewModel.contains("public var activeProjectNameForWorkspacePanel: String?"))
    }

    @Test("selected transcript text opens side chat and survives its initial load")
    func selectedTranscriptTextOpensSideChat() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let chatBubble = try source("Sources/SloppyFeatureChat/Screens/Chat/Views/ChatBubbleView.swift")
        let chatViewModel = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")

        #expect(mainView.contains("onAskInSideChat: askInSideChat"))
        #expect(mainView.contains("func askInSideChat(_ selectedText: String)"))
        #expect(mainView.contains("tab.chat?.addTextSelectionToComposer(selectedText)"))
        #expect(mainView.contains("viewModel.openWorkspaceDockTab(.sideChat)"))
        #expect(mainView.contains("dock.select(existing)"))
        #expect(chatBubble.contains("TextSelectionAction(\"Ask in side chat\""))
        #expect(chatViewModel.contains("pendingComposerTextMutation"))
        #expect(chatViewModel.contains("applyComposerTextMutation(pendingComposerTextMutation)"))
    }

    @Test("main macOS composer uses the 800 point desktop width without changing iOS")
    func mainMacOSComposerUsesDesktopWidth() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")

        #expect(mainView.contains("#if os(macOS)\n                        ChatComposerView.desktopPanelWidth\n#else\n                        10\n#endif"))
        #expect(mainView.contains("contentWidth: geometry.size.width"))
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
