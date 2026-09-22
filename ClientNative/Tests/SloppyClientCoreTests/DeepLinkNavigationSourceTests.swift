import Foundation
import Testing

@Suite("Deep link navigation source")
struct DeepLinkNavigationSourceTests {
    @Test("task deep links open the matching task detail")
    func taskDeepLinksOpenTaskDetail() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/SloppyClient/Navigation/Main/MainView+Navigation.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("case .task(let projectId, let taskId):"))
        #expect(source.contains("project.tasks?.first(where: { $0.id == taskId })"))
        #expect(source.contains("viewModel.openTaskDetailTab("))
    }
}
