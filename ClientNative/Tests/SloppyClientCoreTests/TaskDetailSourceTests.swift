import Foundation
import Testing

@Suite("Task detail source")
struct TaskDetailSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("task detail tab is modeled in main tabs and main view")
    func taskDetailTabIsModeledInMainTabsAndMainView() throws {
        let tabs = try source("Sources/SloppyClient/MainTabs.swift")
        let mainView = try source("Sources/SloppyClient/MainView.swift")
        let mainViewModel = try source("Sources/SloppyClient/MainViewModel.swift")

        #expect(tabs.contains("struct TaskDetailTabContext: Hashable, Sendable"))
        #expect(tabs.contains("case taskDetail(TaskDetailTabContext)"))
        #expect(tabs.contains("final class TaskDetailTabState"))
        #expect(mainViewModel.contains("var tabStates: [WorkspaceTab.ID: WorkspaceTabState] = [:]"))
        #expect(mainViewModel.contains("WorkspaceTabState(contentState: .taskDetail(detailState))"))
        #expect(mainViewModel.contains("func makeTaskDetailTabState() -> TaskDetailTabState"))
        #expect(mainView.contains("case .taskDetail:"))
        #expect(mainView.contains("TaskDetailView("))
    }

    @Test("task detail view loads project task and comments")
    func taskDetailViewLoadsProjectTaskAndComments() throws {
        let detailSource = try source("Sources/SloppyFeatureProjects/TaskDetailView.swift")
        let apiSource = try source("Sources/SloppyClientCore/SloppyAPIClient.swift")

        #expect(detailSource.contains("final class TaskDetailViewModel"))
        #expect(detailSource.contains("async let projectRequest = apiClient.fetchProject(id: projectId)"))
        #expect(detailSource.contains("async let commentsRequest = apiClient.fetchTaskComments(projectId: projectId, taskId: taskId)"))
        #expect(detailSource.contains("Text(\"Comments\")"))
        #expect(detailSource.contains("Button(\"Open Chat\")"))
        #expect(apiSource.contains("public func fetchTaskComments(projectId: String, taskId: String) async throws -> [TaskComment]"))
    }
}
