#if os(macOS)
import AppKit
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyUITestSupport
import SwiftUI
import Testing
@testable import SloppyClient

@Suite("Sidebar subchat interaction", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct SidebarSubchatRenderingTests {
    @Test func streamedChildAppearsUnderParentAndOpensItsSession() async throws {
        AppKitTestAccessibility.enable()
        let fixture = SidebarLongChatFixture(agents: [APIAgentRecord(id: "agent", displayName: "Agent")])
        let cache = ClientCacheStore(path: ":memory:")
        await cache.cacheAgents([APIAgentRecord(id: "agent", displayName: "Agent")])
        let settings = ClientSettings()
        let old = (settings.discoveredInstances, settings.instanceSelection, settings.chatSidebarMode,
                   settings.lastAgentId, settings.lastProjectId, settings.lastSessionId)
        let layout = UserDefaults.standard.object(forKey: "client_chat_sidebar_layout_mode")
        settings.discoveredInstances = []
        settings.instanceSelection = .all
        settings.chatSidebarMode = .allChats
        UserDefaults.standard.set("list", forKey: "client_chat_sidebar_layout_mode")
        let model = MainViewModel(endpoint: fixture.api.endpoint, settings: settings,
            connectionMonitor: ConnectionMonitor(baseURL: fixture.api.baseURL), cacheStore: cache, apiClient: fixture.api,
            responseNotificationScheduler: SubchatTestNotifications(), onOpenSettings: { _ in }, onOpenWorkspace: {})
        defer {
            model.chatViewModel.closeSession()
            for state in model.tabStates.values { state.chatState?.viewModel.closeSession() }
            for tab in model.workspaceDockState.tabs { tab.chat?.closeSession() }
            settings.discoveredInstances = old.0; settings.instanceSelection = old.1; settings.chatSidebarMode = old.2
            settings.lastAgentId = old.3; settings.lastProjectId = old.4; settings.lastSessionId = old.5
            if let layout { UserDefaults.standard.set(layout, forKey: "client_chat_sidebar_layout_mode") }
            else { UserDefaults.standard.removeObject(forKey: "client_chat_sidebar_layout_mode") }
        }
        let root = ChatSessionSummary(id: "root-\(UUID())", agentId: "agent", title: "Main conversation")
        let child = ChatSessionSummary(id: "child-\(UUID())", agentId: "agent", title: "Implement browser zoom", parentSessionId: root.id)
        let nested = ChatSessionSummary(id: "nested-\(UUID())", agentId: "agent", title: "Review implementation", parentSessionId: child.id)
        await cache.cacheSessions(agentId: "agent", projectId: nil, sessions: [root])
        model.chatViewModel.mergeSessionSummary(root)
        model.openSessionChatTab(root)
        let tabID = try #require(model.selectedTabID)
        let parentChat = try #require(model.tabStates[tabID]?.chatState?.viewModel)
        await parentChat.waitForInitialData()
        let host = NSHostingView(rootView: SidebarRecentsList(viewModel: model, showsHeaderControls: false)
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark)
            .background(AppTheme.sloppyDark.colors.background))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))
        // Exercise the same publication callback that the worker poller uses.
        parentChat.parallelAgents.onSessionSummaryChange(child)
        parentChat.parallelAgents.onSessionSummaryChange(nested)
        model.recordSidebarSessionActivity(.working, for: child)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.sidebarSessionCatalog.contains { $0.id == child.id && $0.parentSessionId == root.id })
        let parentRow = try #require(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.\(root.storageID)"))
        let childRow = try #require(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.\(child.storageID)"))
        let parentFrame = try #require(AppKitTestAccessibility.frame(of: parentRow))
        let childFrame = try #require(AppKitTestAccessibility.frame(of: childRow))
        #expect(childFrame.minX > parentFrame.minX)
        let disclosure = try #require(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.\(root.storageID).children"))
        #expect(AppKitTestAccessibility.press(disclosure))
        try await Task.sleep(for: .milliseconds(100))
        #expect(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.\(child.storageID)") == nil)
        #expect(AppKitTestAccessibility.press(disclosure))
        try await Task.sleep(for: .milliseconds(100))
        let reopened = try #require(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.\(child.storageID)"))
        #expect(AppKitTestAccessibility.press(reopened))
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.selectedChatSessionID == root.id)
        let dock = model.workspaceDockState
        await dock.selectedTab?.chat?.waitForInitialData()
        #expect(dock.isPresented)
        #expect(dock.selectedTab?.chat?.selectedSessionId == child.id)
        #expect(model.selectedTabID == tabID)
        #expect(model.tabEndpoints[try #require(model.selectedTabID)] == fixture.api.endpoint)
        let grandchildRow = try #require(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.\(nested.storageID)"))
        #expect(AppKitTestAccessibility.press(grandchildRow))
        await dock.selectedTab?.chat?.waitForInitialData()
        #expect(model.selectedChatSessionID == root.id)
        #expect(dock.selectedTab?.chat?.selectedSessionId == nested.id)
        #expect(model.selectedTabID == tabID)
        try await Task.sleep(for: .milliseconds(100))
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_SIDEBAR_SCREENSHOTS"] {
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("sidebar-subchats.png"))
        }

        // Recover the state produced by the previous in-place worker navigation.
        parentChat.composerDraft.text = "Unsent parent draft"
        parentChat.openSessionFromSummary(child)
        let recoveryHost = NSHostingView(rootView: ChatScreen(viewModel: parentChat,
            showsContextToolbar: false, showsNavigationToolbar: false)
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let recoveryWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 650),
            styleMask: [.titled], backing: .buffered, defer: false)
        recoveryWindow.contentView = recoveryHost
        recoveryWindow.makeKeyAndOrderFront(nil)
        defer { recoveryWindow.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        let back = try #require(AppKitTestAccessibility.element(in: recoveryHost, identifier: "chat.back-to-parent"))
        #expect(AppKitTestAccessibility.press(back))
        #expect(parentChat.selectedSessionId == root.id)
        #expect(parentChat.composerDraft.text == "Unsent parent draft")
    }
}

@MainActor
private final class SubchatTestNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
