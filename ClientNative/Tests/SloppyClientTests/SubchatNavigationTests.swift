#if os(macOS)
import Foundation
import SloppyClientCore
import SloppyFeatureChat
import Testing
@testable import SloppyClient

@Suite("Subchat navigation", .serialized)
@MainActor
struct SubchatNavigationTests {
    @Test func workerAndNestedSubchatKeepPrimaryChatAndDraft() async throws {
        try await withModel { model, primary, root, child in
            let primaryID = model.selectedTabID
            primary.composerDraft.text = "Unsent parent message"
            primary.openLongChatWorker(child.id)
            let dock = model.workspaceDockState
            try await waitUntil { dock.selectedTab?.chat?.selectedSessionId == child.id }
            let firstTab = try #require(dock.selectedTab)
            #expect(dock.isPresented)
            #expect(primary.selectedSessionId == root.id)
            #expect(primary.composerDraft.text == "Unsent parent message")
            #expect(model.selectedTabID == primaryID)
            #expect(firstTab.chat?.sessionEndpoint == primary.sessionEndpoint)

            model.openSessionChatTab(child)
            #expect(dock.selectedID == firstTab.id)
            #expect(dock.tabs.count == 1)
            let nested = ChatSessionSummary(id: "nested", agentId: child.agentId, title: "Nested review", parentSessionId: child.id)
            model.openSessionChatTab(nested)
            await dock.selectedTab?.chat?.waitForInitialData()
            #expect(dock.selectedTab?.chat?.selectedSessionId == nested.id)
            #expect(primary.selectedSessionId == root.id)
            #expect(primary.composerDraft.text == "Unsent parent message")
            dock.hide()
            #expect(primary.selectedSessionId == root.id)
        }
    }

    @Test(arguments: [false, true])
    func lateWorkerResponseDoesNotOpenAfterLeavingParent(switchesTab: Bool) async throws {
        try await withModel { model, primary, _, child in
            primary.openLongChatWorker(child.id)
            if switchesTab { model.createBlankChatTab() }
            else { primary.startNewMessage() }
            try await Task.sleep(for: .milliseconds(350))
            #expect(primary.selectedSessionId == (switchesTab ? "root" : nil))
            #expect(model.workspaceDockState.tabs.isEmpty)
        }
    }

    @Test func strandedChildCanReturnToParentAndRestoreItsDraft() async throws {
        try await withModel { _, primary, root, child in
            primary.composerDraft.text = "Parent draft"
            primary.openSessionFromSummary(child)
            #expect(primary.activeParentSessionID == root.id)
            primary.returnToParentChat()
            #expect(primary.selectedSessionId == root.id)
            #expect(primary.activeParentSessionID == nil)
            #expect(primary.composerDraft.text == "Parent draft")
        }
    }

    @Test func sameSessionIDOnDifferentServersHasSeparateSideTabs() async throws {
        try await withModel { model, primary, root, child in
            let other = SloppyInstanceEndpoint.direct(baseURL: URL(string: "http://localhost:9")!)
            model.openSessionInSidePanel(child, endpoint: primary.sessionEndpoint)
            let localTab = try #require(model.workspaceDockState.selectedTab)
            model.openSessionInSidePanel(child, endpoint: other)
            let remoteTab = try #require(model.workspaceDockState.selectedTab)
            #expect(remoteTab.id != localTab.id)
            #expect(remoteTab.chat?.sessionEndpoint == other)
            #expect(localTab.chat?.sessionEndpoint == primary.sessionEndpoint)
            #expect(primary.selectedSessionId == root.id)
        }
    }

    private func withModel(
        _ body: (MainViewModel, ChatScreenViewModel, ChatSessionSummary, ChatSessionSummary) async throws -> Void
    ) async throws {
        let root = ChatSessionSummary(id: "root", agentId: "agent", title: "Main chat", kind: "long_chat")
        let child = ChatSessionSummary(id: "child", agentId: "agent", title: "Review", parentSessionId: root.id)
        let fixture = SidebarLongChatFixture(agents: [.init(id: "agent", displayName: "Agent")],
            sessions: [root, child], delayedSessionID: child.id)
        let settings = ClientSettings()
        let previous = (settings.lastAgentId, settings.lastProjectId, settings.lastSessionId)
        let model = MainViewModel(endpoint: fixture.api.endpoint, settings: settings,
            connectionMonitor: ConnectionMonitor(baseURL: fixture.api.baseURL), cacheStore: ClientCacheStore(path: ":memory:"),
            apiClient: fixture.api, responseNotificationScheduler: SubchatNavigationNotifications(),
            onOpenSettings: { _ in }, onOpenWorkspace: {})
        model.openSessionChatTab(root)
        let primary = try #require(model.selectedTabID.flatMap { model.tabStates[$0]?.chatState?.viewModel })
        defer {
            for tab in model.workspaceDockState.tabs { tab.chat?.closeSession() }
            for state in model.tabStates.values { state.chatState?.viewModel.closeSession() }
            primary.closeSession()
            model.chatViewModel.closeSession()
            settings.lastAgentId = previous.0
            settings.lastProjectId = previous.1
            settings.lastSessionId = previous.2
        }
        await primary.waitForInitialData()
        try await body(model, primary, root, child)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

@MainActor
private final class SubchatNavigationNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
