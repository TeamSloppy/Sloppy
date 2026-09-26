import Foundation
import Testing
import SloppyClientCore
@testable import SloppyFeatureProjects

@Suite("Task properties editing")
struct TaskPropertiesEditTests {
    @Test func sendsOnlyChangedFieldsAndCanClearOptionalValues() throws {
        let task = APIProjectTask(
            id: "task-1", title: "Original", status: "ready", priority: "medium",
            actorId: "agent-1", executionNodeId: "node-1",
            description: "Old description", tags: ["spec", "memory"]
        )
        var draft = TaskPropertiesDraft(task: task)
        let unchanged = draft.updateRequest(comparedTo: task)
        #expect(unchanged.title == nil)
        #expect(unchanged.status == nil)
        #expect(unchanged.actorId == nil)
        #expect(unchanged.tags == nil)

        draft.title = "  Renamed  "
        draft.description = ""
        draft.actorId = ""
        draft.executionNodeId = ""
        draft.tags = "spec, release, "
        let update = draft.updateRequest(comparedTo: task)
        #expect(update.title == "Renamed")
        #expect(update.description == "")
        #expect(update.status == nil)
        #expect(update.priority == nil)
        #expect(update.actorId == "")
        #expect(update.executionNodeId == "")
        #expect(update.tags == ["spec", "release"])

        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any])
        #expect(object["status"] == nil)
        #expect(object["actorId"] as? String == "")
        #expect(object["tags"] as? [String] == ["spec", "release"])
    }
}
