#if os(macOS)
import Foundation
import SloppyClientCore

struct SloppyDesktopRecentChatGroup: Identifiable {
    let chat: SloppyDesktopRecentChat
    let children: [Self]
    let updatedAt: Date
    let descendantCount: Int
    var id: String { chat.id }

    static func make(_ chats: [SloppyDesktopRecentChat]) -> [Self] {
        let sorted = chats.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
        var byID: [String: SloppyDesktopRecentChat] = [:]
        for chat in sorted where byID[chat.id] == nil { byID[chat.id] = chat }
        let bySessionID = Dictionary(grouping: Array(byID.values), by: \.sessionID)
        // Adapt the overlay's agent/session identities to the shared cycle-safe tree.
        // The adapted summaries are only tree keys; opening a chat uses its original summary.
        let summaries = byID.values.map { chat in
            var summary = chat.sessionSummary
            summary.id = chat.id
            let candidates = chat.parentSessionID.flatMap { bySessionID[$0] } ?? []
            let parent = candidates.first { $0.agentID == chat.agentID }
                ?? (candidates.count == 1 ? candidates.first : nil)
            summary.parentSessionId = parent?.id
            return summary
        }
        let tree = ChatSidebarSessionTree(sessions: summaries)
        func branch(_ summary: ChatSessionSummary) -> Self? {
            guard let chat = byID[summary.id] else { return nil }
            let children = tree.children(of: summary).compactMap(branch).sorted(by: ordered)
            return Self(chat: chat, children: children,
                updatedAt: max(chat.updatedAt, children.map(\.updatedAt).max() ?? chat.updatedAt),
                descendantCount: children.reduce(0) { $0 + 1 + $1.descendantCount })
        }
        return tree.roots.compactMap(branch).sorted(by: ordered)
    }

    private static func ordered(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
    }

    func visibleRows(expandedIDs: Set<String>, depth: Int = 0) -> [SloppyDesktopRecentChatRow] {
        let expanded = expandedIDs.contains(id)
        let row = SloppyDesktopRecentChatRow(chat: chat, depth: depth,
            subagentCount: descendantCount, isExpanded: expanded)
        return [row] + (expanded ? children.flatMap { $0.visibleRows(expandedIDs: expandedIDs, depth: depth + 1) } : [])
    }
}

struct SloppyDesktopRecentChatRow: Identifiable {
    let chat: SloppyDesktopRecentChat
    let depth: Int
    let subagentCount: Int
    let isExpanded: Bool
    var id: String { chat.id }
}

enum SloppyDesktopRecentChatCatalog {
    /// A busy child must not lose its group just because its parent fell out of the recent page.
    static func restoringAncestors(
        _ sessions: [ChatSessionSummary],
        fetch: @escaping @Sendable (String, String) async -> ChatSessionSummary?
    ) async -> [ChatSessionSummary] {
        struct Parent: Hashable, Sendable { let agentID: String; let sessionID: String }
        var result = sessions
        var attempted: Set<Parent> = []
        while attempted.count < 24, !Task.isCancelled {
            let knownIDs = Set(result.map(\.id))
            let missing = result.compactMap { session -> Parent? in
                guard let parent = session.parentSessionId, !parent.isEmpty, !knownIDs.contains(parent) else { return nil }
                return Parent(agentID: session.agentId, sessionID: parent)
            }
            let requests = Array(Set(missing).subtracting(attempted))
                .sorted { ($0.agentID, $0.sessionID) < ($1.agentID, $1.sessionID) }
                .prefix(24 - attempted.count)
            guard !requests.isEmpty else { break }
            attempted.formUnion(requests)
            let parents = await withTaskGroup(of: ChatSessionSummary?.self, returning: [ChatSessionSummary].self) { group in
                for parent in requests {
                    group.addTask {
                        guard let summary = await fetch(parent.agentID, parent.sessionID),
                              summary.id == parent.sessionID, summary.agentId == parent.agentID else { return nil }
                        return summary
                    }
                }
                var fetched: [ChatSessionSummary] = []
                for await parent in group { if let parent { fetched.append(parent) } }
                return fetched
            }
            result += parents
        }
        return result
    }
}
#endif
