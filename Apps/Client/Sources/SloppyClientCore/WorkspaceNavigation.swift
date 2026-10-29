import Foundation

public enum WorkspaceSection: String, CaseIterable, Sendable {
    case chats
    case projects
    case agents
    case attention
    case sites
    case pullRequests
    case scheduled
    case project

    public var title: String {
        switch self {
        case .chats: "Inbox"
        case .projects: "Projects"
        case .agents: "Agents"
        case .attention: "Attention"
        case .sites: "Sites"
        case .pullRequests: "Pull Requests"
        case .scheduled: "Scheduled"
        case .project: "Workspace"
        }
    }
}

/// Tab identity is independent of a server session: a new chat has a draft before it has a session.
public struct WorkspaceNavigation: Sendable {
    public struct ChatTab: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var title: String

        public init(id: UUID = UUID(), title: String = "New chat") {
            self.id = id
            self.title = title
        }
    }

    public private(set) var tabs: [ChatTab]
    public private(set) var selectedTabID: UUID
    public var section: WorkspaceSection = .chats

    public init() {
        let tab = ChatTab()
        tabs = [tab]
        selectedTabID = tab.id
    }

    @discardableResult
    public mutating func createChat(title: String = "New chat") -> UUID {
        let tab = ChatTab(title: title)
        tabs.append(tab)
        selectChat(tab.id)
        return tab.id
    }

    public mutating func selectChat(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        section = .chats
    }

    public mutating func renameChat(_ id: UUID, title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = title.isEmpty ? "New chat" : title
    }

    public mutating func closeChat(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            let replacement = ChatTab()
            tabs = [replacement]
            selectedTabID = replacement.id
        } else if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }
}

public struct ChatSidebarContent: Sendable {
    public var pinned: [ChatSessionSummary]
    public var recent: [ChatSessionSummary]

    public func sessions(in projectID: String) -> [ChatSessionSummary] {
        recent.filter { $0.projectId == projectID }
    }

    public var personal: [ChatSessionSummary] { recent.filter { $0.projectId == nil } }

    public init(sessions: [ChatSessionSummary], pinnedIDs: Set<String>, query: String = "") {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = sessions.filter {
            $0.kind != "heartbeat" && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.agentId != $1.agentId { return $0.agentId < $1.agentId }
            return $0.id < $1.id
        }
        pinned = visible.filter { pinnedIDs.contains($0.id) }
        recent = visible.filter { !pinnedIDs.contains($0.id) }
    }
}
