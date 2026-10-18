import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Sidebar subchat hierarchy")
struct ChatSidebarSessionTreeTests {
    private func session(_ id: String, parent: String? = nil, source: String? = nil, project: String? = "project") -> ChatSessionSummary {
        .init(id: id, agentId: "agent", title: id, updatedAt: Date(timeIntervalSince1970: id == "root" ? 10 : 20),
              projectId: project, sourceInstanceID: source, parentSessionId: parent)
    }

    @Test func childrenAreNestedWithoutConsumingProjectPreviewSlots() {
        let root = session("root")
        let child = session("child", parent: "root", project: nil)
        let grandchild = session("grandchild", parent: "child")
        let sections = ChatSidebarSections.build(sessions: [child, root, grandchild],
            projects: [.init(id: "project", name: "Project")], pinnedSessionIds: [], mode: .projects, projectPreviewLimit: 1)
        #expect(sections.projectGroups.first?.visibleSessions.map(\.id) == ["root"])
        #expect(sections.projectGroups.first?.allSessionsCount == 1)
        #expect(sections.tree.children(of: root).map(\.id) == ["child"])
        #expect(sections.tree.children(of: child).map(\.id) == ["grandchild"])
        #expect(sections.tree.contains(grandchild.storageID, under: root))
    }

    @Test func parentIDsNeverCrossInstanceBoundaries() {
        let root = session("root", source: "one")
        let otherRoot = session("root", source: "two")
        let child = session("child", parent: "root", source: "two")
        let orphan = session("orphan", parent: "missing", source: "one")
        let tree = ChatSidebarSessionTree(sessions: [root, otherRoot, child, orphan])
        #expect(tree.children(of: root).isEmpty)
        #expect(tree.children(of: otherRoot).map(\.id) == ["child"])
        #expect(tree.roots.contains { $0.storageID == orphan.storageID })
        let defaultTree = ChatSidebarSessionTree(sessions: [session("root"), session("child", parent: "root", source: "local")],
                                                defaultSourceInstanceID: "local")
        #expect(defaultTree.children(of: session("root")).map(\.id) == ["child"])
    }

    @Test func pinnedChildrenBecomePriorityRootsExactlyOnce() {
        let root = session("root"), child = session("child", parent: "root")
        let sections = ChatSidebarSections.build(sessions: [root, child], projects: [],
            pinnedSessionIds: [child.storageID], mode: .allChats)
        #expect(sections.pinned.map(\.id) == ["child"])
        #expect(sections.sessions.map(\.id) == ["root"])
        #expect(sections.tree.children(of: root).isEmpty)
    }

    @Test func brokenParentChainsStayVisibleAndCannotRecurseForever() {
        let sessions = [session("self", parent: "self"), session("a", parent: "b"), session("b", parent: "a"),
                        session("missing", parent: "gone")]
        let tree = ChatSidebarSessionTree(sessions: sessions + sessions)
        #expect(Set(tree.roots.map(\.id)) == ["self", "a", "b", "missing"])
        #expect(tree.roots.count == 4)
        #expect(!tree.contains("a", under: session("b")))
    }

    @Test func parentMetadataSurvivesCacheCodingAndOldSummariesStillDecode() throws {
        let child = session("child", parent: "root")
        let data = try JSONEncoder().encode(child)
        #expect(try JSONDecoder().decode(ChatSessionSummary.self, from: data).parentSessionId == "root")
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "parentSessionId")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(ChatSessionSummary.self, from: legacy).parentSessionId == nil)
    }
}
