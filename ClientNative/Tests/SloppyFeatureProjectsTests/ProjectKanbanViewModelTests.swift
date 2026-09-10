import Foundation
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
            executionNodeId: "node_work",
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

    @Test("Kanban cards keep the execution instance separate from the actor")
    func cardsKeepExecutionInstanceSeparateFromActor() throws {
        let card = try #require(
            ProjectKanbanViewModel.buildColumns(from: tasks)
                .flatMap(\.items)
                .first { $0.id == "TASK-1" }
        )

        #expect(card.actorID == "agent:core")
        #expect(card.executionNodeID == "node_work")
    }
    @Test("cards and assignee filters use the worker claim and preserve the column entry date")
    func claimedTaskMetadata() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let task = APIProjectTask(id: "claimed", title: "Claimed task", status: "in_progress",
                                  actorId: "agent:planned", claimedActorId: "agent:worker",
                                  tags: ["ui", "macOS"], updatedAt: Date(), kanbanColumnEnteredAt: date)
        let columns = ProjectKanbanViewModel.buildColumns(from: [task],
            filters: ProjectKanbanFilters(assignee: .actor("agent:worker")))
        let card = try #require(columns.flatMap(\.items).first)
        #expect(card.actorID == "agent:planned")
        #expect(card.assigneeID == "agent:worker")
        #expect(card.isClaimed)
        #expect(card.tags == ["ui", "macOS"])
        #expect(card.kanbanColumnEnteredAt == date)
        #expect(ProjectKanbanViewModel.buildColumns(from: [task],
            filters: ProjectKanbanFilters(assignee: .unassigned)).flatMap(\.items).isEmpty)
    }

    @Test("older server responses do not substitute last edit time for column entry")
    func legacyTaskTiming() throws {
        let data = Data(#"{"id":"old","title":"Old task","status":"done","updatedAt":1234}"#.utf8)
        let task = try JSONDecoder().decode(APIProjectTask.self, from: data)
        let card = try #require(ProjectKanbanViewModel.buildColumns(from: [task]).flatMap(\.items).first)
        #expect(card.kanbanColumnEnteredAt == nil)
        #expect(card.assigneeID == nil)
    }

    @Test("empty assignment IDs render as unassigned and an agent claim remains visible")
    func emptyAssignmentAndAgentClaim() throws {
        var task = APIProjectTask(id: "task", title: "Task", status: "ready", actorId: "",
                                  claimedActorId: "", claimedAgentId: "")
        let unassigned = try #require(ProjectKanbanViewModel.buildColumns(from: [task]).flatMap(\.items).first)
        #expect(unassigned.assigneeID == nil)
        task.claimedAgentId = "builder"
        let claimed = try #require(ProjectKanbanViewModel.buildColumns(from: [task]).flatMap(\.items).first)
        #expect(claimed.assigneeID == "builder")
        #expect(claimed.isClaimed)
    }

    @Test("imported tasks retain their external assignee until a local worker claims them")
    func importedTaskAssignee() throws {
        let data = Data(#"{"id":"imported","title":"Imported task","status":"ready","externalMetadata":{"externalAssignee":"alex","externalUpdatedAt":"2026-09-09T15:00:00Z"}}"#.utf8)
        var task = try JSONDecoder().decode(APIProjectTask.self, from: data)
        let card = try #require(ProjectKanbanViewModel.buildColumns(from: [task],
            filters: ProjectKanbanFilters(assignee: .actor("alex"))).flatMap(\.items).first)
        #expect(card.assigneeID == "alex")
        #expect(!card.isClaimed)
        #expect(card.kanbanColumnEnteredAt == nil)
        task.claimedAgentId = "builder"
        #expect(task.kanbanAssigneeID == "builder")
    }

}
