import Foundation
import Testing

@Suite("Main sidebar project disclosure")
struct MainSidebarProjectDisclosureTests {
    private func source(named fileName: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClient")
        let sourceURL = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: nil
        )?
            .compactMap { $0 as? URL }
            .first(where: { $0.lastPathComponent == fileName })
        return try String(contentsOf: #require(sourceURL), encoding: .utf8)
    }

    @Test("project collapse state is separate from show more state")
    func projectCollapseStateIsSeparateFromShowMoreState() throws {
        let mainViewSource = try source(named: "MainView.swift")
        let sidebarSource = try source(named: "SidebarRecentsList.swift")

        #expect(mainViewSource.contains("var collapsedProjectIds: Set<String> = []"))
        #expect(mainViewSource.contains("var expandedTaskLists: Set<String> = []"))
        #expect(mainViewSource.contains("func toggleProjectCollapse(projectId: String)"))
        #expect(mainViewSource.contains("func toggleTaskListExpansion(projectId: String)"))

        #expect(sidebarSource.contains("viewModel.collapsedProjectIds.contains(group.id)"))
        #expect(sidebarSource.contains("if !isCollapsed {"))
        #expect(sidebarSource.contains("viewModel.toggleTaskListExpansion(projectId: group.id)"))
        #expect(sidebarSource.contains("if !isCollapsed {"))
    }

    @Test("project rows open kanban tabs and task rows open task chats")
    func projectRowsOpenKanbanTabsAndTaskRowsOpenTaskChats() throws {
        let sidebarSource = try source(named: "SidebarRecentsList.swift")

        #expect(sidebarSource.contains("viewModel.openProjectKanbanTab(project: group.project)"))
    }

    @Test("main view renders a native project kanban tab")
    func mainViewRendersNativeProjectKanbanTab() throws {
        let mainViewSource = try source(named: "MainView.swift")

        #expect(mainViewSource.contains("ProjectKanbanView("))
        #expect(mainViewSource.contains("case .projectKanban"))
        #expect(mainViewSource.contains("ProjectKanbanTabState"))
    }

    @Test("kanban cards open task detail from the content area")
    func kanbanCardsOpenTaskDetailFromTheContentArea() throws {
        let mainViewSource = try source(named: "MainView.swift")
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let kanbanSource = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureProjects")
                .appendingPathComponent("Screens")
                .appendingPathComponent("Projects")
                .appendingPathComponent("Kanban")
                .appendingPathComponent("ProjectKanbanView.swift"),
            encoding: .utf8
        )

        #expect(kanbanSource.contains("let onOpenTask: @MainActor (ProjectKanbanCard) -> Void"))
        #expect(kanbanSource.contains("Button {"))
        #expect(kanbanSource.contains("onOpenTask(card)"))
        #expect(kanbanSource.contains("ScrollView([.horizontal, .vertical], showsIndicators: false)"))
        #expect(mainViewSource.contains("onOpenTask: { card in"))
        #expect(mainViewSource.contains("viewModel.openTaskDetailTab("))
    }
}
