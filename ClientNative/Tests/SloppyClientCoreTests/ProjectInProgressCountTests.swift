import Testing
@testable import SloppyClientCore

@Suite("Project in-progress count")
struct ProjectInProgressCountTests {
    @Test func countsOnlyTasksInProgress() {
        let statuses = ["in_progress", "ready", "needs_review", "done", "backlog", "cancelled", "in_progress"]
        let project = APIProjectRecord(id: "p", name: "Project", tasks: statuses.enumerated().map {
            APIProjectTask(id: String($0.offset), title: "Task", status: $0.element)
        })
        #expect(project.inProgressTaskCount == 2)
    }

    @Test func distinguishesMissingDataFromNoRunningTasks() {
        #expect(APIProjectRecord(id: "p", name: "Project").inProgressTaskCount == nil)
        #expect(APIProjectRecord(id: "p", name: "Project", tasks: []).inProgressTaskCount == 0)
    }

    @Test func reflectsChangedTaskStatuses() {
        var project = APIProjectRecord(id: "p", name: "Project", tasks: [
            APIProjectTask(id: "1", title: "Task", status: "ready")
        ])
        #expect(project.inProgressTaskCount == 0)
        project.tasks?[0].status = "in_progress"
        #expect(project.inProgressTaskCount == 1)
        project.tasks?[0].status = "needs_review"
        #expect(project.inProgressTaskCount == 0)
    }
}
