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

        #expect(tabs.contains("final class ChatTabState"))
        #expect(tabs.contains("let viewModel: ChatScreenViewModel"))
        #expect(mainView.contains("makeChatTabState() -> ChatTabState"))
        #expect(mainView.contains("ChatScreen(viewModel: chatState.viewModel"))
    }

    @Test("desktop task and recent session actions open tab-local chats instead of the global chat view model")
    func desktopTaskAndRecentSessionActionsOpenTabLocalChats() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(mainView.contains("openTaskChatTab("))
        #expect(mainView.contains("openSessionChatTab("))
        #expect(!mainView.contains("chatViewModel.pickSession(session)"))
        #expect(!mainView.contains("navigateChat("))
    }
}
