import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Chat sidebar sections")
struct ChatSidebarSectionsTests {
    @Test("builds chronological chat list with pinned sessions separated")
    func buildsChronologicalChatListWithPinnedSessionsSeparated() {
        let now = Date(timeIntervalSince1970: 300)
        let sessions = [
            ChatSessionSummary(
                id: "pinned",
                agentId: "agent",
                title: "Pinned",
                messageCount: 3,
                updatedAt: now
            ),
            ChatSessionSummary(
                id: "recent",
                agentId: "agent",
                title: "Recent",
                messageCount: 2,
                updatedAt: Date(timeIntervalSince1970: 200)
            ),
            ChatSessionSummary(
                id: "older",
                agentId: "agent",
                title: "Older",
                messageCount: 1,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ]

        let sections = ChatSidebarSections.build(
            sessions: sessions,
            projects: [],
            pinnedSessionIds: ["pinned"],
            mode: .allChats
        )

        #expect(sections.pinned.map(\.id) == ["pinned"])
        #expect(sections.sessions.map(\.id) == ["recent", "older"])
        #expect(sections.dayGroups.flatMap(\.sessions).map(\.id) == ["recent", "older"])
        #expect(sections.projectGroups.isEmpty)
    }

    @Test("groups all chats by local day with newest groups and sessions first")
    func groupsAllChatsByLocalDayWithNewestGroupsAndSessionsFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let newestDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 2)))
        let olderDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let sessions = [
            ChatSessionSummary(
                id: "older-day",
                agentId: "agent",
                title: "Older day",
                updatedAt: olderDay.addingTimeInterval(80)
            ),
            ChatSessionSummary(
                id: "newest",
                agentId: "agent",
                title: "Newest",
                updatedAt: newestDay.addingTimeInterval(120)
            ),
            ChatSessionSummary(
                id: "newer",
                agentId: "agent",
                title: "Newer",
                updatedAt: newestDay.addingTimeInterval(60)
            )
        ]

        let sections = ChatSidebarSections.build(
            sessions: sessions,
            projects: [],
            pinnedSessionIds: [],
            mode: .allChats,
            calendar: calendar
        )

        #expect(sections.dayGroups.map(\.day) == [newestDay, olderDay])
        #expect(sections.dayGroups[0].sessions.map(\.id) == ["newest", "newer"])
        #expect(sections.dayGroups[1].sessions.map(\.id) == ["older-day"])
    }

    @Test("builds project groups without pinned sessions and limits each preview")
    func buildsProjectGroupsWithoutPinnedSessionsAndLimitsEachPreview() {
        let sessions = [
            ChatSessionSummary(
                id: "pinned-project",
                agentId: "agent",
                title: "Pinned Project",
                messageCount: 4,
                updatedAt: Date(timeIntervalSince1970: 400),
                projectId: "project-a"
            ),
            ChatSessionSummary(
                id: "project-a-new",
                agentId: "agent",
                title: "Project A New",
                messageCount: 3,
                updatedAt: Date(timeIntervalSince1970: 300),
                projectId: "project-a"
            ),
            ChatSessionSummary(
                id: "project-a-old",
                agentId: "agent",
                title: "Project A Old",
                messageCount: 2,
                updatedAt: Date(timeIntervalSince1970: 200),
                projectId: "project-a"
            ),
            ChatSessionSummary(
                id: "project-b",
                agentId: "agent",
                title: "Project B",
                messageCount: 1,
                updatedAt: Date(timeIntervalSince1970: 100),
                projectId: "project-b"
            ),
            ChatSessionSummary(
                id: "no-project",
                agentId: "agent",
                title: "No Project",
                messageCount: 5,
                updatedAt: Date(timeIntervalSince1970: 350),
                projectId: nil
            )
        ]
        let projects = [
            APIProjectRecord(id: "project-a", name: "Project A"),
            APIProjectRecord(id: "project-b", name: "Project B")
        ]

        let sections = ChatSidebarSections.build(
            sessions: sessions,
            projects: projects,
            pinnedSessionIds: ["pinned-project"],
            mode: .projects,
            projectPreviewLimit: 1
        )

        #expect(sections.pinned.map(\.id) == ["pinned-project"])
        #expect(sections.sessions.isEmpty)
        #expect(sections.projectGroups.map(\.project.id) == ["project-a", "project-b"])
        #expect(sections.projectGroups.first?.visibleSessions.map(\.id) == ["project-a-new"])
        #expect(sections.projectGroups.first?.hiddenCount == 1)
        #expect(sections.projectGroups.last?.visibleSessions.map(\.id) == ["project-b"])
        #expect(sections.projectGroups.last?.hiddenCount == 0)
    }

    @Test("projects include empty groups and preserve the supplied order")
    func projectsIncludeEmptyGroupsAndPreserveTheSuppliedOrder() {
        let projects = [
            APIProjectRecord(id: "empty", name: "Empty"),
            APIProjectRecord(id: "older", name: "Older"),
            APIProjectRecord(id: "newer", name: "Newer")
        ]
        let sessions = [
            ChatSessionSummary(
                id: "older-chat",
                agentId: "agent",
                title: "Older",
                messageCount: 1,
                updatedAt: Date(timeIntervalSince1970: 100),
                projectId: "older"
            ),
            ChatSessionSummary(
                id: "newer-chat",
                agentId: "agent",
                title: "Newer",
                messageCount: 1,
                updatedAt: Date(timeIntervalSince1970: 200),
                projectId: "newer"
            )
        ]

        let sections = ChatSidebarSections.build(
            sessions: sessions,
            projects: projects,
            pinnedSessionIds: [],
            mode: .projects
        )

        #expect(sections.projectGroups.map(\.project.id) == ["empty", "older", "newer"])
        #expect(sections.projectGroups.first?.totalSessions.isEmpty == true)
    }
}
