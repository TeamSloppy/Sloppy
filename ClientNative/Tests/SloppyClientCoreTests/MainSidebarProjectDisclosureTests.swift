import Foundation
import Testing

@Suite("Main sidebar project disclosure")
struct MainSidebarProjectDisclosureTests {
    private func source(named fileName: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClient")
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test("project collapse state is separate from show more state")
    func projectCollapseStateIsSeparateFromShowMoreState() throws {
        let mainViewSource = try source(named: "MainView.swift")
        let sidebarSource = try source(named: "MainSidebarView.swift")

        #expect(mainViewSource.contains("var collapsedProjectIds: Set<String> = []"))
        #expect(mainViewSource.contains("var expandedTaskLists: Set<String> = []"))
        #expect(mainViewSource.contains("func toggleProjectCollapse(projectId: String)"))
        #expect(mainViewSource.contains("func toggleTaskListExpansion(projectId: String)"))

        #expect(sidebarSource.contains("let isCollapsed = viewModel.collapsedProjectIds.contains(project.id)"))
        #expect(sidebarSource.contains("if !isCollapsed {"))
        #expect(sidebarSource.contains("showMoreButton(projectId: project.id, isExpanded: isExpanded, c: c, sp: sp)"))
    }

    @Test("project rows open kanban tabs and task rows open task chats")
    func projectRowsOpenKanbanTabsAndTaskRowsOpenTaskChats() throws {
        let sidebarSource = try source(named: "MainSidebarView.swift")

        #expect(sidebarSource.contains("viewModel.openProjectKanbanTab(project: project)"))
        #expect(sidebarSource.contains("viewModel.openTaskChatTab("))
        #expect(!sidebarSource.contains("viewModel.selectProject(project)"))
    }

    @Test("main view renders a native project kanban tab")
    func mainViewRendersNativeProjectKanbanTab() throws {
        let mainViewSource = try source(named: "MainView.swift")

        #expect(mainViewSource.contains("ProjectKanbanView("))
        #expect(mainViewSource.contains("case .projectKanban"))
        #expect(mainViewSource.contains("ProjectKanbanTabState"))
    }
}
