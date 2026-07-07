import Foundation
import Testing

@Suite("Desktop chat tab source")
struct DesktopChatTabSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("chat tabs own local chat screen state")
    func chatTabsOwnLocalChatScreenState() throws {
        let tabs = try source("Sources/SloppyClient/MainTabs.swift")
        let mainView = try source("Sources/SloppyClient/MainView.swift")
        let mainViewModel = try source("Sources/SloppyClient/MainViewModel.swift")
        let chatScreen = try source("Sources/SloppyFeatureChat/ChatScreen.swift")

        #expect(tabs.contains("final class WorkspaceTabState"))
        #expect(tabs.contains("var content: AnyView?"))
        #expect(tabs.contains("final class ChatTabState"))
        #expect(tabs.contains("let viewModel: ChatScreenViewModel"))
        #expect(mainViewModel.contains("var tabStates: [WorkspaceTab.ID: WorkspaceTabState] = [:]"))
        #expect(mainViewModel.contains("makeChatTabState() -> ChatTabState"))
        #expect(mainView.contains("cachedContent(for: tab)"))
        #expect(mainView.contains("mountedDesktopTabContent(activeTabID: activeDesktopTab.id)"))
        #expect(mainView.contains(".allowsHitTesting(tab.id == activeTabID)"))
        #expect(mainView.contains("ChatScreen("))
        #expect(mainView.contains("viewModel: chatState.viewModel"))
        #expect(chatScreen.contains("private let viewModel: ChatScreenViewModel"))
        #expect(!chatScreen.contains("@State private var viewModel: ChatScreenViewModel"))
    }

    @Test("desktop task and recent session actions use tab-local chats instead of the global chat view model")
    func desktopTaskAndRecentSessionActionsUseTabLocalChats() throws {
        let mainViewModel = try source("Sources/SloppyClient/MainViewModel.swift")

        #expect(mainViewModel.contains("openTaskChatTab("))
        #expect(mainViewModel.contains("openSessionChatTab("))
        #expect(mainViewModel.contains("retargetSelectedChatTab(to: session)"))
        #expect(mainViewModel.contains("private func retargetSelectedChatTab(to session: ChatSessionSummary) -> Bool"))
        #expect(!mainViewModel.contains("chatViewModel.pickSession(session)"))
        #expect(!mainViewModel.contains("navigateChat("))
    }
}
