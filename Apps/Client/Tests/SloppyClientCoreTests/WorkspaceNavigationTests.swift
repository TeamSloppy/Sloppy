import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Workspace navigation")
struct WorkspaceNavigationTests {
    @Test("switching sections preserves the selected chat and its stable identity")
    func preservesChatWhenSwitchingSections() {
        var navigation = WorkspaceNavigation()
        let first = navigation.selectedTabID
        let second = navigation.createChat(title: "Build a feature")
        navigation.section = .agents
        #expect(navigation.selectedTabID == second)
        navigation.selectChat(first)
        #expect(navigation.section == .chats)
        #expect(navigation.tabs.map(\.id) == [first, second])
    }

    @Test("closing a background tab does not switch the active chat")
    func closesBackgroundTab() {
        var navigation = WorkspaceNavigation()
        let first = navigation.selectedTabID
        let second = navigation.createChat()
        navigation.closeChat(first)
        #expect(navigation.selectedTabID == second)
    }

    @Test("closing the active tab selects the nearest remaining chat")
    func closesActiveTab() {
        var navigation = WorkspaceNavigation()
        let first = navigation.selectedTabID
        let middle = navigation.createChat()
        let last = navigation.createChat()
        navigation.selectChat(middle)
        navigation.closeChat(middle)
        #expect(navigation.selectedTabID == last)
        navigation.closeChat(last)
        #expect(navigation.selectedTabID == first)
    }

    @Test("closing the final chat leaves a fresh draft tab")
    func replacesFinalTab() {
        var navigation = WorkspaceNavigation()
        let old = navigation.selectedTabID
        navigation.closeChat(old)
        #expect(navigation.tabs.count == 1)
        #expect(navigation.selectedTabID != old)
        #expect(navigation.tabs.first?.title == "New chat")
    }

    @Test("stale tab actions preserve the active section and selection")
    func ignoresStaleActions() {
        var navigation = WorkspaceNavigation()
        let initial = navigation.selectedTabID
        navigation.section = .projects
        let unknown = UUID()
        navigation.selectChat(unknown)
        navigation.closeChat(unknown)
        navigation.renameChat(unknown, title: "stale")
        #expect(navigation.section == .projects)
        #expect(navigation.selectedTabID == initial)
        #expect(navigation.tabs.count == 1)
    }

    @Test("Priority and Recents exclude heartbeats and order by recent activity")
    func groupsVisibleChats() {
        let older = ChatSessionSummary(id: "old", agentId: "a", title: "Older", updatedAt: Date(timeIntervalSince1970: 1))
        let newer = ChatSessionSummary(id: "new", agentId: "b", title: "Newer", updatedAt: Date(timeIntervalSince1970: 2))
        let heartbeat = ChatSessionSummary(id: "beat", agentId: "a", title: "Heartbeat", kind: "heartbeat")
        let content = ChatSidebarContent(sessions: [older, heartbeat, newer], pinnedIDs: ["old", "beat"])
        #expect(content.pinned.map(\.id) == ["old"])
        #expect(content.recent.map(\.id) == ["new"])
    }

    @Test("search trims whitespace and matches chat titles regardless of case")
    func searchesChats() {
        let sessions = [ChatSessionSummary(id: "one", agentId: "a", title: "Fix AdaEngine"),
                        ChatSessionSummary(id: "two", agentId: "b", title: "Plan release")]
        let content = ChatSidebarContent(sessions: sessions, pinnedIDs: ["two"], query: "  ADAengine\n")
        #expect(content.pinned.isEmpty)
        #expect(content.recent.map(\.id) == ["one"])
    }

    @Test("project groups contain sessions and keep personal chats separate")
    func groupsProjectSessions() {
        let content = ChatSidebarContent(sessions: [
            ChatSessionSummary(id: "p", agentId: "a", title: "Project", projectId: "project"),
            ChatSessionSummary(id: "personal", agentId: "a", title: "Personal"),
            ChatSessionSummary(id: "pinned", agentId: "a", title: "Pinned", projectId: "project"),
        ], pinnedIDs: ["pinned"])
        #expect(content.sessions(in: "project").map(\.id) == ["p"])
        #expect(content.personal.map(\.id) == ["personal"])
        #expect(content.pinned.map(\.id) == ["pinned"])
    }
}
