#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import SloppyClientUI
import SloppyUITestSupport
import SloppyClientCore
import SloppyFeatureChat
import Testing
@testable import SloppyClient

@Suite("Project new chat", .serialized)
@MainActor
struct ProjectNewChatTests {
    @Test(arguments: [false, true])
    func repeatedNewChatsPreserveExistingHistoryAndDrafts(switchBeforeBootstrap: Bool) async throws {
        let agent = APIAgentRecord(id: "agent", displayName: "Agent")
        let existing = ChatSessionSummary(id: "existing", agentId: agent.id, title: "History", projectId: "project")
        let fixture = SidebarLongChatFixture(agents: [agent], sessions: [existing])
        let settings = ClientSettings()
        let previous = (settings.lastAgentId, settings.lastProjectId, settings.lastSessionId)
        let model = MainViewModel(endpoint: fixture.api.endpoint, settings: settings,
            connectionMonitor: ConnectionMonitor(baseURL: fixture.api.baseURL), cacheStore: ClientCacheStore(path: ":memory:"),
            apiClient: fixture.api, responseNotificationScheduler: NewChatNotifications(),
            onOpenSettings: { _ in }, onOpenWorkspace: {})
        defer {
            for state in model.tabStates.values { state.chatState?.viewModel.closeSession() }
            model.chatViewModel.closeSession()
            settings.lastAgentId = previous.0; settings.lastProjectId = previous.1; settings.lastSessionId = previous.2
        }
        model.openSessionChatTab(existing)
        let originalID = try #require(model.selectedTabID)
        let original = try #require(model.tabStates[originalID]?.chatState?.viewModel)
        await original.waitForInitialData()
        original.composerDraft.text = "Unsent original"
        let initialPosts = fixture.posts.count
        let project = APIProjectRecord(id: "project", name: "Project", actors: [agent.id])
        model.showNewProjectChat(project: project)
        let firstID = try #require(model.selectedTabID)
        let first = try #require(model.tabStates[firstID]?.chatState?.viewModel)
        #expect(firstID == originalID)
        #expect(model.tabs.count == 1)
        #expect(first.activeProjectIdForWorkspacePanel == project.id)
        #expect(first.selectedSessionId == nil)
        #expect(first.transcript.messages.isEmpty)
        if switchBeforeBootstrap {
            first.composerDraft.text = "Early draft"
            model.showNewProjectChat(project: APIProjectRecord(id: "early", name: "Early", actors: [agent.id]))
            model.showNewProjectChat(project: project)
        }
        await first.waitForInitialData()
        for _ in 0..<100 where first.activeProjectIdForWorkspacePanel != project.id {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(first.selectedSessionId == nil)
        #expect(first.transcript.messages.isEmpty)
        #expect(first.composerDraft.text == (switchBeforeBootstrap ? "Early draft" : ""))
        #expect(first.activeProjectIdForWorkspacePanel == project.id)
        #expect(first.sessionEndpoint == fixture.api.endpoint)
        first.composerDraft.text = "First draft"
        model.showNewProjectChat(project: project)
        let secondID = try #require(model.selectedTabID)
        let second = try #require(model.tabStates[secondID]?.chatState?.viewModel)
        await second.waitForInitialData()
        try await Task.sleep(for: .milliseconds(200))
        #expect(secondID == firstID)
        #expect(second === first)
        #expect(model.tabs.count == 1)
        #expect(second.selectedSessionId == nil)
        #expect(second.composerDraft.text == "First draft")
        #expect(first.composerDraft.text == "First draft")
        #expect(original.composerDraft.text == "Unsent original")
        #expect(original.selectedSessionId == existing.id)
        #expect(fixture.posts.count == initialPosts)
        let other = APIProjectRecord(id: "other", name: "Other", actors: [agent.id])
        model.showNewProjectChat(project: other)
        #expect(model.selectedTabID == firstID)
        #expect(model.tabs.count == 1)
        #expect(first.activeProjectIdForWorkspacePanel == other.id)
        #expect(first.composerDraft.text == "First draft")
        #expect(first.selectedSessionId == nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.posts.count == initialPosts)
        #expect(first.sendMessage(content: "First message"))
        for _ in 0..<200 where first.selectedSessionId == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(first.selectedSessionId == "created")
        let creations = fixture.posts.filter { $0.url?.path.hasSuffix("/sessions") == true }
        #expect(creations.count == 1)
        let request = try #require(creations.first)
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["projectId"] as? String == other.id)
        #expect(payload["separateChat"] as? Bool == true)
        #expect(model.tabs.count == 1)
        model.openSessionChatTab(existing)
        let reopened = try #require(model.selectedTabID.flatMap { model.tabStates[$0]?.chatState?.viewModel })
        await reopened.waitForInitialData()
        #expect(model.selectedTabID.flatMap { model.tabStates[$0]?.chatState?.viewModel.selectedSessionId } == existing.id)
        #expect(original.composerDraft.text == "Unsent original")
    }
}

@Suite("Project new chat UI", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ProjectNewChatUITests {
    @Test func plusButtonStartsOneFreshChatWithoutParentNavigation() async throws {
        AppKitTestAccessibility.enable()
        let agent = APIAgentRecord(id: "agent", displayName: "Agent")
        let existing = ChatSessionSummary(id: "history", agentId: agent.id, title: "Existing conversation", projectId: "project")
        let fixture = SidebarLongChatFixture(agents: [agent], sessions: [existing])
        let settings = ClientSettings()
        let previous = (settings.lastAgentId, settings.lastProjectId, settings.lastSessionId)
        let model = MainViewModel(endpoint: fixture.api.endpoint, settings: settings,
            connectionMonitor: ConnectionMonitor(baseURL: fixture.api.baseURL), cacheStore: ClientCacheStore(path: ":memory:"),
            apiClient: fixture.api, responseNotificationScheduler: NewChatNotifications(),
            onOpenSettings: { _ in }, onOpenWorkspace: {})
        defer {
            for state in model.tabStates.values { state.chatState?.viewModel.closeSession() }
            model.chatViewModel.closeSession()
            settings.lastAgentId = previous.0; settings.lastProjectId = previous.1; settings.lastSessionId = previous.2
        }
        model.openSessionChatTab(existing)
        let originalID = try #require(model.selectedTabID)
        let original = try #require(model.tabStates[originalID]?.chatState?.viewModel)
        await original.waitForInitialData()
        original.composerDraft.text = "Preserved draft"
        let project = APIProjectRecord(id: "project", name: "Fixture project", actors: [agent.id])
        let group = ChatSidebarProjectGroup(project: project, visibleSessions: [existing], totalSessions: [existing])
        let host = NSHostingView(rootView: SidebarProjectGroupView(viewModel: model, group: group,
            tree: .init(sessions: [existing])).environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 430, height: 230),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        let plus = try #require(AppKitTestAccessibility.element(in: host, identifier: "sidebar.project.project.new-chat"))
        let count = model.tabs.count
        #expect(AppKitTestAccessibility.press(plus))
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.tabs.count == count)
        let firstID = try #require(model.selectedTabID)
        let first = try #require(model.tabStates[firstID]?.chatState?.viewModel)
        await first.waitForInitialData()
        #expect(first.selectedSessionId == nil)
        #expect(first.activeProjectIdForWorkspacePanel == project.id)
        #expect(model.tabs.allSatisfy { $0.kind == .chat })
        #expect(original.composerDraft.text == "Preserved draft")
        #expect(AppKitTestAccessibility.press(plus))
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.tabs.count == count)
        #expect(model.selectedTabID == firstID)
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_ANNOTATION_SCREENSHOTS"] {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to:
                URL(fileURLWithPath: directory).appendingPathComponent("sidebar-new-chat.png"))
        }
    }
}

@MainActor
private final class NewChatNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
