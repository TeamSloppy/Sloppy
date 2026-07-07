import Foundation
import Testing

@Suite("Main sidebar navigation source")
struct MainSidebarNavigationSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("sidebar tab actions dismiss mobile sidebar before showing detail content")
    func sidebarTabActionsDismissMobileSidebarBeforeShowingDetailContent() throws {
        let source = try source("Sources/SloppyClient/MainViewModel.swift")

        try assertDismissesMobileSidebar(source, in: "func openSessionChatTab(_ session: ChatSessionSummary)")
        try assertDismissesMobileSidebar(source, in: "func openProjectKanbanTab(project: APIProjectRecord)")
        try assertDismissesMobileSidebar(source, in: "func openTaskChatTab(project: APIProjectRecord, task: APIProjectTask, fallbackAgentId: String?)")
        try assertDismissesMobileSidebar(source, in: "func openTaskDetailTab(project: APIProjectRecord, task: APIProjectTask, fallbackAgentId: String?)")
    }

    @Test("phone chat detail can reopen the sidebar")
    func phoneChatDetailCanReopenTheSidebar() throws {
        let source = try source("Sources/SloppyClient/MainView.swift")

        #expect(source.contains("let openSidebar: (@MainActor () -> Void)? = idiom == .phone ? viewModel.openMobileSidebar : nil"))
        #expect(source.contains("onOpenSidebar: openSidebar"))
    }

    @Test("sidebar rows use navigation links to open compact detail")
    func sidebarRowsUseNavigationLinksToOpenCompactDetail() throws {
        let sidebarSource = try source("Sources/SloppyClient/MainSidebarView.swift")
        let mainViewSource = try source("Sources/SloppyClient/MainView.swift")
        let sidebarColumnRange = try #require(mainViewSource.range(of: "private var navigationView: some View"))
        let detailColumnRange = try #require(mainViewSource.range(of: "} detail: {"))
        let sidebarColumnSource = mainViewSource[sidebarColumnRange.lowerBound..<detailColumnRange.lowerBound]

        #expect(sidebarSource.contains("navigationValue: MainSidebarSelection?"))
        #expect(sidebarSource.contains("NavigationLink(value: navigationValue)"))
        #expect(sidebarSource.contains("navigationValue: .chats"))
        #expect(sidebarSource.contains("navigationValue: .project(project.id)"))
        #expect(sidebarSource.contains("navigationValue: .task(projectId: projectId, taskId: task.id)"))
        #expect(sidebarColumnSource.contains(".navigationDestination(for: MainSidebarSelection.self)"))
        #expect(mainViewSource.contains("NavigationSplitView(columnVisibility: $viewModel.columnVisibility)"))
        #expect(!mainViewSource.contains("mobileSidebarOverlay()"))
        #expect(!mainViewSource.contains("isMobileSidebarPresented"))
    }

    private func assertDismissesMobileSidebar(_ source: String, in functionSignature: String) throws {
        let functionStart = try #require(source.range(of: functionSignature))
        let remainingSource = source[functionStart.lowerBound...]
        let dismissRange = try #require(remainingSource.range(of: "dismissMobileSidebar()"))
        let keyRange = try #require(remainingSource.range(of: "let key = WorkspaceTabKey."))

        #expect(dismissRange.lowerBound < keyRange.lowerBound)
    }
}
