#if os(macOS)
import Foundation
import SloppyClientCore
import Testing
@testable import SloppyClient

@Suite("Desktop overlay subagent groups")
@MainActor
struct DesktopRecentChatGroupingTests {
    @Test func explicitParentsGroupSubagentsAndTheirActivityMovesTheWholeGroup() {
        let groups = SloppyDesktopRecentChatGroup.make([
            chat("root", time: 1), chat("child", parent: "root", time: 2),
            chat("grandchild", parent: "child", time: 10), chat("unrelated", time: 5),
        ])
        #expect(groups.map(\.chat.sessionID) == ["root", "unrelated"])
        #expect(groups[0].descendantCount == 2)
        #expect(groups[0].children[0].children[0].chat.sessionID == "grandchild")
        let rows = groups[0].visibleRows(expandedIDs: ["agent/root", "agent/child"])
        #expect(rows.map(\.depth) == [0, 1, 2])
        #expect(rows.map(\.chat.sessionID) == ["root", "child", "grandchild"])
    }

    @Test func namesDoNotDetermineParentageAndUnreachableParentsRemainVisible() {
        let workerLookingTitle = SloppyDesktopRecentChat(id: "agent/independent", agentID: "agent", sessionID: "independent",
            title: "task-UUID-attempt-1", agentName: "Agent", updatedAt: Date(timeIntervalSince1970: 0))
        let groups = SloppyDesktopRecentChatGroup.make([workerLookingTitle, chat("orphan", parent: "missing")])
        #expect(Set(groups.map(\.chat.sessionID)) == ["independent", "orphan"])
    }

    @Test func malformedCyclesAndRepeatedRecordsDoNotHideChatsOrRecurse() {
        let a = chat("a", parent: "b"), b = chat("b", parent: "a"), ownParent = chat("self", parent: "self")
        let groups = SloppyDesktopRecentChatGroup.make([a, a, b, ownParent])
        #expect(Set(groups.map(\.chat.sessionID)) == ["a", "b", "self"])
        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.children.isEmpty })
    }

    @Test func parentIdentitiesPreferTheirAgentAndSupportUnambiguousCrossAgentDelegation() {
        let groups = SloppyDesktopRecentChatGroup.make([
            chat("shared", agent: "one"), chat("shared", agent: "two"),
            chat("child", parent: "shared", agent: "two"),
            chat("unique", agent: "one"), chat("delegated", parent: "unique", agent: "two"),
        ])
        #expect(groups.first { $0.id == "one/shared" }?.children.isEmpty == true)
        #expect(groups.first { $0.id == "two/shared" }?.children.map(\.id) == ["two/child"])
        #expect(groups.first { $0.id == "one/unique" }?.children.map(\.id) == ["two/delegated"])
    }

    @Test func expansionSurvivesRefreshAndPreviewSlotsCountParents() {
        let state = SloppyDesktopOverlayState()
        let sessions = [chat("root", time: 5), chat("child", parent: "root", time: 10), chat("other", time: 1)]
        state.setRecentChats(sessions)
        #expect(state.recentChatRows().map(\.chat.sessionID) == ["root", "other"])
        state.toggleRecentChatGroup("agent/root")
        state.setRecentChats(Array(sessions.reversed()))
        #expect(state.recentChatRows(rootLimit: 1).map(\.chat.sessionID) == ["root", "child"])
        state.toggleRecentChatGroup("agent/root")
        #expect(state.recentChatRows(rootLimit: 1).map(\.chat.sessionID) == ["root"])
        state.setRecentChats(sessions + [chat("third", time: -1), chat("fourth", time: -2)])
        #expect(state.recentChatRows(rootLimit: 3).map(\.chat.sessionID) == ["root", "other", "third"])
        state.toggleRecentChatGroup("agent/root")
        state.resetChatContext()
        #expect(state.expandedRecentChatIDs.isEmpty)
    }

    @Test func openingASubagentKeepsItsActualSessionAndParentMetadata() {
        let state = SloppyDesktopOverlayState()
        let child = chat("child", parent: "root")
        state.openRecentChat(child)
        #expect(state.selectedChat?.sessionSummary.id == "child")
        #expect(state.selectedChat?.sessionSummary.parentSessionId == "root")
        #expect(state.selectedChat?.sessionSummary.kind == "worker")
    }

    @Test func olderParentsOutsideTheRecentPageAreRestoredThroughTypedLinks() async {
        let child = chat("child", parent: "parent").sessionSummary
        let restored = await SloppyDesktopRecentChatCatalog.restoringAncestors([child]) { agent, id in
            ChatSessionSummary(id: id, agentId: agent, title: id, parentSessionId: id == "parent" ? "root" : nil)
        }
        #expect(Set(restored.map(\.id)) == ["child", "parent", "root"])
        let unavailable = await SloppyDesktopRecentChatCatalog.restoringAncestors([child]) { _, _ in nil }
        #expect(unavailable == [child])
    }

    @Test func ancestorRecoveryIsBoundedForBrokenServerChains() async {
        let restored = await SloppyDesktopRecentChatCatalog.restoringAncestors([chat("child", parent: "parent").sessionSummary]) { agent, id in
            ChatSessionSummary(id: id, agentId: agent, title: id, parentSessionId: id + "-parent")
        }
        #expect(restored.count == 25)
    }

    private func chat(_ id: String, parent: String? = nil, agent: String = "agent", time: TimeInterval = 0) -> SloppyDesktopRecentChat {
        SloppyDesktopRecentChat(id: "\(agent)/\(id)", agentID: agent, sessionID: id, title: id,
            agentName: agent, updatedAt: Date(timeIntervalSince1970: time),
            parentSessionID: parent, kind: parent == nil ? "chat" : "worker")
    }
}
#endif
