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
        #expect(sidebarSource.contains("let isCollapsed = viewModel.collapsedProjectIds.contains(group.project.id)"))
        #expect(sidebarSource.contains("projectChatHeader(group: group, c: c, sp: sp)"))
        #expect(sidebarSource.contains("if !isCollapsed {"))
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
