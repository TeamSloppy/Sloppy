import Testing
import SloppyClientCore
@testable import SloppyFeatureProjects

@Suite("Project Kanban")
struct ProjectKanbanViewModelTests {
    private let tasks = [
        APIProjectTask(
            id: "TASK-1",
            title: "Ship filters",
            status: "in_progress",
            priority: "high",
            actorId: "agent:core",
            description: "Add controls to the board",
            tags: ["frontend", "release"]
        ),
        APIProjectTask(
            id: "TASK-2",
            title: "Write documentation",
            status: "backlog",
            priority: "medium",
            actorId: nil,
            tags: ["docs"]
        ),
        APIProjectTask(
            id: "TASK-3",
            title: "Fix empty state",
            status: "needs_review",
            priority: nil,
            actorId: "agent:ui"
        ),
    ]

    @Test("default filter preserves every Kanban column and task")
    func defaultFilterPreservesBoard() {
        let columns = ProjectKanbanViewModel.buildColumns(from: tasks)

        #expect(columns.map(\.id) == ProjectKanbanColumnID.allCases)
        #expect(columns.flatMap(\.items).count == 3)
    }

    @Test("search matches title, description, actor, and tags case-insensitively")
    func searchMatchesTaskMetadata() {
        for query in ["SHIP", "controls", "agent:core", "Release"] {
            let columns = ProjectKanbanViewModel.buildColumns(
                from: tasks,
                filters: ProjectKanbanFilters(searchText: query)
            )
            #expect(columns.flatMap(\.items).map(\.id) == ["TASK-1"])
        }
    }

    @Test("priority and assignee filters compose")
    func priorityAndAssigneeFiltersCompose() {
        let unassigned = ProjectKanbanViewModel.buildColumns(
            from: tasks,
            filters: ProjectKanbanFilters(
                priority: .medium,
                assignee: .unassigned
            )
        )
        #expect(unassigned.flatMap(\.items).map(\.id) == ["TASK-2"])

        let noPriority = ProjectKanbanViewModel.buildColumns(
            from: tasks,
            filters: ProjectKanbanFilters(
                priority: .none,
                assignee: .actor("agent:ui")
            )
        )
        #expect(noPriority.flatMap(\.items).map(\.id) == ["TASK-3"])
    }

    @Test("status filter keeps only the selected column")
    func statusFilterKeepsSelectedColumn() {
        let columns = ProjectKanbanViewModel.buildColumns(
            from: tasks,
            filters: ProjectKanbanFilters(status: .column(.needsReview))
        )

        #expect(columns.map(\.id) == [.needsReview])
        #expect(columns.first?.items.map(\.id) == ["TASK-3"])
    }

    @Test("Kanban columns map to statuses accepted by the project task API")
    func kanbanColumnStatuses() {
        #expect(ProjectKanbanColumnID.todo.taskStatus == "ready")
        #expect(ProjectKanbanColumnID.inProgress.taskStatus == "in_progress")
        #expect(ProjectKanbanColumnID.needsReview.taskStatus == "needs_review")
        #expect(ProjectKanbanColumnID.done.taskStatus == "done")
        #expect(ProjectKanbanColumnID.other.taskStatus == "blocked")
    }
}
