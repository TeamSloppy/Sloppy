import Foundation
import Testing

@Suite("Main sidebar project sessions")
struct MainSidebarProjectSessionsTests {
    private var source: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources/SloppyClient/Navigation/Shared/SidebarRecentsList.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("project groups are built from chat sessions with messages")
    func projectGroupsAreBuiltFromChatSessionsWithMessages() throws {
        let source = try source

        #expect(source.contains("ChatSidebarSections.build("))
        #expect(source.contains("ForEach(sections.projectGroups.prefix(viewModel.visibleProjectCount))"))
        #expect(source.contains("ForEach(sessions)"))
    }

    @Test("project list reveals additional projects in pages")
    func projectListRevealsAdditionalProjectsInPages() throws {
        let source = try source

        #expect(source.contains("sections.projectGroups.prefix(viewModel.visibleProjectCount)"))
        #expect(source.contains("Button(\"Show more project\")"))
        #expect(source.contains("viewModel.showMoreProjects()"))
    }

    @Test("project and recents session rows open session-backed tabs")
    func projectAndRecentsSessionRowsOpenSessionBackedTabs() throws {
        let source = try source

        #expect(source.contains("viewModel.openSessionChatTab(session)"))
        #expect(!source.contains("viewModel.selectChatSession(session)"))
    }
}
