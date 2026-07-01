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
}
