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

    public var id: String { project.storageID }

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

public struct ChatSidebarDayGroup: Sendable, Identifiable {
    public var day: Date
    public var sessions: [ChatSessionSummary]

    public var id: Date { day }

    public init(day: Date, sessions: [ChatSessionSummary]) {
        self.day = day
        self.sessions = sessions
    }
}

public struct ChatSidebarSections: Sendable {
    public var pinned: [ChatSessionSummary]
    public var sessions: [ChatSessionSummary]
    public var dayGroups: [ChatSidebarDayGroup]
    public var projectGroups: [ChatSidebarProjectGroup]

    public init(
        pinned: [ChatSessionSummary] = [],
        sessions: [ChatSessionSummary] = [],
        dayGroups: [ChatSidebarDayGroup] = [],
        projectGroups: [ChatSidebarProjectGroup] = []
    ) {
        self.pinned = pinned
        self.sessions = sessions
        self.dayGroups = dayGroups
        self.projectGroups = projectGroups
    }

    public static func build(
        sessions: [ChatSessionSummary],
        projects: [APIProjectRecord],
        pinnedSessionIds: Set<String>,
        mode: ChatSidebarListMode,
        projectPreviewLimit: Int? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ChatSidebarSections {
        let sortedSessions = sessions.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.id < $1.id
            }
            return $0.updatedAt > $1.updatedAt
        }
        let pinned = sortedSessions.filter { pinnedSessionIds.contains($0.storageID) }
        let unpinned = sortedSessions.filter { !pinnedSessionIds.contains($0.storageID) }

        switch mode {
        case .allChats:
            let sessionsByDay = Dictionary(grouping: unpinned) {
                calendar.startOfDay(for: $0.updatedAt)
            }
            let dayGroups = sessionsByDay.keys.sorted(by: >).map { day in
                ChatSidebarDayGroup(day: day, sessions: sessionsByDay[day] ?? [])
            }

            return ChatSidebarSections(
                pinned: pinned,
                sessions: unpinned,
                dayGroups: dayGroups,
                projectGroups: []
            )

        case .projects:
            let groups = projects.map { project in
                let projectSessions = unpinned.filter {
                    $0.projectId == project.id
                        && $0.sourceInstanceID == project.sourceInstanceID
                        && $0.messageCount > 0
                }

                let visibleSessions: [ChatSessionSummary]
                if let projectPreviewLimit {
                    visibleSessions = Array(projectSessions.prefix(projectPreviewLimit))
                } else {
                    visibleSessions = projectSessions
                }

                return ChatSidebarProjectGroup(
                    project: project,
                    visibleSessions: visibleSessions,
                    totalSessions: projectSessions
                )
            }

            return ChatSidebarSections(
                pinned: pinned,
                sessions: [],
                projectGroups: groups
            )
        }
    }
}
