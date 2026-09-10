import Foundation
import Testing
@testable import Protocols

@Suite("Project task column timing")
struct ProjectTaskKanbanTimingTests {
    private let originalDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func task() -> ProjectTask {
        ProjectTask(id: "task", title: "Task", description: "", priority: "medium", status: "backlog",
                    kanbanColumnEnteredAt: originalDate)
    }

    @Test("edits and status changes within a column preserve its entry date")
    func preservesEntryDate() {
        var task = task()
        task.title = "Renamed"
        task.tags = ["UI"]
        task.actorId = "agent:builder"
        task.updatedAt = Date()
        task.status = "ready"
        #expect(task.kanbanColumnEnteredAt == originalDate)
    }

    @Test("moving to a different column records the transition")
    func recordsTransition() throws {
        var task = task()
        let before = Date()
        task.status = "in_progress"
        let enteredAt = try #require(task.kanbanColumnEnteredAt)
        #expect(enteredAt >= before)
        #expect(enteredAt <= Date())
        task.status = "in_progress"
        #expect(task.kanbanColumnEnteredAt == enteredAt)
    }

    @Test("wire round trip preserves timing and legacy payloads leave it unknown")
    func codingCompatibility() throws {
        let data = try JSONEncoder().encode(task())
        let decoded = try JSONDecoder().decode(ProjectTask.self, from: data)
        #expect(decoded.kanbanColumnEnteredAt == originalDate)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "kanbanColumnEnteredAt")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let legacy = try JSONDecoder().decode(ProjectTask.self, from: legacyData)
        #expect(legacy.kanbanColumnEnteredAt == nil)
    }
}
