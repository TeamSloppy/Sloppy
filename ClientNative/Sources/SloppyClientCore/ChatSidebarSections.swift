import Foundation

public enum ChatSidebarListMode: String, Codable, Sendable, CaseIterable {
    case allChats = "all_chats"
    case projects

    public var title: String {
        switch self {
        case .allChats:
            "All chats"
        case .projects:
            "Projects"
        }
    }
}

public struct ChatSidebarProjectGroup: Sendable, Identifiable {
    public var project: APIProjectRecord
    public var visibleSessions: [ChatSessionSummary]
    public var totalSessions: [ChatSessionSummary]

    public var id: String { project.id }

    public var hiddenCount: Int {
        max(0, totalSessions.count - visibleSessions.count)
    }

    public init(
        project: APIProjectRecord,
        visibleSessions: [ChatSessionSummary],
        totalSessions: [ChatSessionSummary]
    ) {
        self.project = project
        self.visibleSessions = visibleSessions
        self.totalSessions = totalSessions
    }
}

public struct ChatSidebarSections: Sendable {
    public var pinned: [ChatSessionSummary]
    public var sessions: [ChatSessionSummary]
    public var projectGroups: [ChatSidebarProjectGroup]

    public init(
        pinned: [ChatSessionSummary] = [],
        sessions: [ChatSessionSummary] = [],
        projectGroups: [ChatSidebarProjectGroup] = []
    ) {
        self.pinned = pinned
        self.sessions = sessions
        self.projectGroups = projectGroups
    }

    public static func build(
        sessions: [ChatSessionSummary],
        projects: [APIProjectRecord],
        pinnedSessionIds: Set<String>,
        mode: ChatSidebarListMode,
        projectPreviewLimit: Int? = nil
    ) -> ChatSidebarSections {
        let sortedSessions = sessions.sorted { $0.updatedAt > $1.updatedAt }
        let pinned = sortedSessions.filter { pinnedSessionIds.contains($0.id) }
        let unpinned = sortedSessions.filter { !pinnedSessionIds.contains($0.id) }

        switch mode {
        case .allChats:
            return ChatSidebarSections(
                pinned: pinned,
                sessions: unpinned,
                projectGroups: []
            )

        case .projects:
            let groups = projects.enumerated().map { index, project in
                let projectSessions = unpinned.filter {
                    $0.projectId == project.id && $0.messageCount > 0
                }

                let visibleSessions: [ChatSessionSummary]
                if let projectPreviewLimit {
                    visibleSessions = Array(projectSessions.prefix(projectPreviewLimit))
                } else {
                    visibleSessions = projectSessions
                }

                return (
                    index: index,
                    latestActivity: projectSessions.first?.updatedAt,
                    group: ChatSidebarProjectGroup(
                        project: project,
                        visibleSessions: visibleSessions,
                        totalSessions: projectSessions
                    )
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.latestActivity, rhs.latestActivity) {
                case let (lhsDate?, rhsDate?):
                    lhsDate == rhsDate ? lhs.index < rhs.index : lhsDate > rhsDate
                case (.some, .none):
                    true
                case (.none, .some):
                    false
                case (.none, .none):
                    lhs.index < rhs.index
                }
            }
            .map { $0.group }

            return ChatSidebarSections(
                pinned: pinned,
                sessions: [],
                projectGroups: groups
            )
        }
    }
}
