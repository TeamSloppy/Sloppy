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
}
