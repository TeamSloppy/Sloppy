import Foundation
import Testing
@testable import SloppyClientCore

@Suite("OverviewModels")
struct OverviewModelsTests {

    @Test("APIProjectRecord toSummary computes counts")
    func projectRecordToSummary() {
        let record = APIProjectRecord(
            id: "proj-1",
            name: "TestProject",
            description: "A project",
            channels: [
                APIProjectChannel(id: "ch1", title: "General", channelId: "ch-1"),
                APIProjectChannel(id: "ch2", title: "Dev", channelId: "ch-2")
            ],
            tasks: [
                APIProjectTask(id: "t1", title: "Task 1", status: "in_progress"),
                APIProjectTask(id: "t2", title: "Task 2", status: "done"),
                APIProjectTask(id: "t3", title: "Task 3", status: "ready"),
                APIProjectTask(id: "t4", title: "Task 4", status: "backlog")
            ]
        )

        let summary = record.toSummary()

        #expect(summary.id == "proj-1")
        #expect(summary.name == "TestProject")
        #expect(summary.description == "A project")
        #expect(summary.channelCount == 2)
        #expect(summary.taskCount == 4)
        #expect(summary.activeTaskCount == 2)
    }

    @Test("APIProjectRecord toSummary handles nil collections")
    func projectRecordNilCollections() {
        let record = APIProjectRecord(id: "p1", name: "Empty")

        let summary = record.toSummary()

        #expect(summary.channelCount == 0)
        #expect(summary.taskCount == 0)
        #expect(summary.activeTaskCount == 0)
    }

    @Test("legacy projects decode with project defaults")
    func legacyProjectDefaults() throws {
        let json = #"{"id":"legacy","name":"Legacy","description":"","repoPath":"/tmp/legacy"}"#.data(using: .utf8)!
        let project = try JSONDecoder().decode(APIProjectRecord.self, from: json)

        #expect(project.kind == .project)
        #expect(project.directoryPaths.isEmpty)
        #expect(project.projectRootPath == "/tmp/legacy")
        #expect(project.semanticIconName == "folder")
    }

    @Test("workspace projects preserve roots and use workspace icon")
    func workspaceProjectCoding() throws {
        let record = APIProjectRecord(
            id: "workspace",
            name: "Workspace",
            kind: .workspace,
            directoryPaths: ["/tmp/app", "/tmp/api"],
            repoPath: "/tmp/app"
        )
        let decoded = try JSONDecoder().decode(APIProjectRecord.self, from: JSONEncoder().encode(record))

        #expect(decoded.kind == .workspace)
        #expect(decoded.directoryPaths == ["/tmp/app", "/tmp/api"])
        #expect(decoded.projectRootPath == "/tmp/app")
        #expect(decoded.semanticIconName == "square.stack.3d.up")
    }

    @Test("Material project icons map to SF Symbols")
    func materialProjectIconsMapToSystemSymbols() {
        let science = APIProjectRecord(id: "science", name: "Science", icon: "science")
        let deployedCode = APIProjectRecord(id: "deploy", name: "Deploy", icon: "deployed_code")

        #expect(science.semanticIconName == "flask")
        #expect(deployedCode.semanticIconName == "shippingbox")
    }

    @Test("unsupported project icons use the project kind fallback")
    func unsupportedProjectIconsUseFallback() {
        let project = APIProjectRecord(id: "project", name: "Project", icon: "not_an_sf_symbol")
        let workspace = APIProjectRecord(
            id: "workspace",
            name: "Workspace",
            icon: "not_an_sf_symbol",
            kind: .workspace
        )

        #expect(project.semanticIconName == "folder")
        #expect(workspace.semanticIconName == "square.stack.3d.up")
    }

    @Test("APIAgentRecord toOverview preserves fields")
    func agentRecordToOverview() {
        let record = APIAgentRecord(id: "agent-1", displayName: "Codex", role: "developer")
        let overview = record.toOverview()

        #expect(overview.id == "agent-1")
        #expect(overview.displayName == "Codex")
        #expect(overview.role == "developer")
    }

    @Test("OverviewData default initializer")
    func overviewDataDefaults() {
        let data = OverviewData()

        #expect(data.projects.isEmpty)
        #expect(data.agents.isEmpty)
        #expect(data.activeTasks == 0)
        #expect(data.completedTasks == 0)
    }

    @Test("APIAgentRecord decodes from JSON")
    func agentRecordDecoding() throws {
        let json = """
        {"id":"bot-1","displayName":"Helper","role":"qa"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(APIAgentRecord.self, from: json)

        #expect(decoded.id == "bot-1")
        #expect(decoded.displayName == "Helper")
        #expect(decoded.role == "qa")
    }

    @Test("ProjectSummary is equatable")
    func projectSummaryEquatable() {
        let a = ProjectSummary(id: "1", name: "A")
        let b = ProjectSummary(id: "1", name: "A")
        let c = ProjectSummary(id: "2", name: "B")

        #expect(a == b)
        #expect(a != c)
    }

    @Test("project task statuses normalize into stable kanban columns")
    func projectTaskStatusesNormalizeIntoStableKanbanColumns() {
        let todo = APIProjectTask(id: "t1", title: "Todo", status: "todo")
        let progress = APIProjectTask(id: "t2", title: "Build", status: "in_progress")
        let review = APIProjectTask(id: "t3", title: "Review", status: "needs_review")
        let done = APIProjectTask(id: "t4", title: "Done", status: "done")
        let unknown = APIProjectTask(id: "t5", title: "Unknown", status: "blocked")

        #expect(todo.normalizedKanbanColumnID == .todo)
        #expect(progress.normalizedKanbanColumnID == .inProgress)
        #expect(review.normalizedKanbanColumnID == .needsReview)
        #expect(done.normalizedKanbanColumnID == .done)
        #expect(unknown.normalizedKanbanColumnID == .other)
    }

    @Test("project task creation request uses the Core wire keys")
    func projectTaskCreationRequestUsesCoreWireKeys() throws {
        let request = APIProjectTaskCreateRequest(
            title: "Create filters",
            description: "Add task filters",
            priority: "high",
            status: "backlog",
            actorId: "agent:ui",
            tags: ["frontend"]
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )

        #expect(object["title"] as? String == "Create filters")
        #expect(object["actorId"] as? String == "agent:ui")
        #expect(object["status"] as? String == "backlog")
        #expect(object["tags"] as? [String] == ["frontend"])
    }

    @Test("project creation request includes IDEA markdown")
    func projectCreationRequestIncludesIdeaMarkdown() throws {
        let request = APIProjectCreateRequest(
            name: "Research Log",
            idea: "Track sources and unanswered questions."
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )

        #expect(object["idea"] as? String == "Track sources and unanswered questions.")
    }
}
