import Foundation
import Testing

@Suite("Main tabs source")
struct MainTabsSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("main tabs domain defines kinds payloads and semantic keys")
    func mainTabsDomainDefinesKindsPayloadsAndSemanticKeys() throws {
        let tabs = try source("Sources/SloppyClient/MainTabs.swift")

        #expect(tabs.contains("enum WorkspaceTabKind: String, Hashable"))
        #expect(tabs.contains("case chat"))
        #expect(tabs.contains("case projectKanban"))
        #expect(tabs.contains("case workspaceFiles"))
        #expect(tabs.contains("enum WorkspaceTabKey: Hashable"))
        #expect(tabs.contains("case chatSession(String)"))
        #expect(tabs.contains("case chatTask(projectId: String, taskId: String)"))
        #expect(tabs.contains("case projectKanban(String)"))
        #expect(tabs.contains("case workspaceFiles(String)"))
    }

    @Test("main view model owns tabs and open close selection helpers")
    func mainViewModelOwnsTabsAndOpenCloseSelectionHelpers() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(mainView.contains("var tabs: [WorkspaceTab] = []"))
        #expect(mainView.contains("var selectedTabID: WorkspaceTab.ID?"))
        #expect(mainView.contains("func openProjectKanbanTab(project: APIProjectRecord)"))
        #expect(mainView.contains("func openTaskChatTab("))
        #expect(mainView.contains("func openSessionChatTab(_ session: ChatSessionSummary)"))
        #expect(mainView.contains("func closeTab(_ tabID: WorkspaceTab.ID)"))
        #expect(mainView.contains("func selectTab(_ tabID: WorkspaceTab.ID)"))
    }

    @Test("main view model exposes blank tab and adjacent navigation helpers")
    func mainViewModelExposesBlankTabAndAdjacentNavigationHelpers() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(mainView.contains("var isMobileTabsOverviewPresented = false"))
        #expect(mainView.contains("func createBlankChatTab(select: Bool = true)"))
        #expect(mainView.contains("func selectAdjacentTab(offset: Int)"))
        #expect(mainView.contains("func nextTabID(from tabID: WorkspaceTab.ID, offset: Int) -> WorkspaceTab.ID?"))
        #expect(mainView.contains("func presentMobileTabsOverview()"))
        #expect(mainView.contains("func dismissMobileTabsOverview()"))
    }
}
