import Foundation
import Testing

@Suite("Main navigation shell")
struct MainNavigationShellTests {
    private func source(named fileName: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClient")
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test("main view defines section tabs for shell navigation")
    func mainViewDefinesSectionTabsForShellNavigation() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains("enum MainAppSection: String, CaseIterable, Hashable"))
        #expect(source.contains("var selectedAppSection: MainAppSection = .chats"))
        #expect(source.contains("func selectAppSection(_ section: MainAppSection)"))
    }

    @Test("main view uses split detail workspace container on phones")
    func mainViewUsesSplitDetailWorkspaceContainerOnPhones() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains("NavigationSplitView"))
        #expect(source.contains("desktopContentArea()"))
        #expect(source.contains("if idiom == .phone, viewModel.isMobileTabsOverviewPresented"))
        #expect(source.contains("MobileWorkspaceTabsOverview("))
    }

    @Test("regular layout uses extracted workspace host and desktop strip")
    func regularLayoutUsesExtractedWorkspaceHostAndDesktopStrip() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains("private var activeDesktopTab: WorkspaceTab?"))
        #expect(source.contains("DesktopWorkspaceTabStrip(viewModel: viewModel)"))
        #expect(source.contains("private func workspaceContentHost() -> some View"))
        #expect(source.contains("desktopTabContent(for tab: WorkspaceTab)"))
        #expect(!source.contains("private func phoneTabLayout() -> some View"))
    }

    @Test("sidebar defines section picker tabs for chats agents and projects")
    func sidebarDefinesSectionPickerTabsForChatsAgentsAndProjects() throws {
        let source = try source(named: "MainSidebarView.swift")

        #expect(source.contains("TabView(selection: $viewModel.selectedAppSection)"))
        #expect(source.contains("Tab(\"Chats\""))
        #expect(source.contains("Tab(\"Agents\""))
        #expect(source.contains("Tab(\"Projects\""))
    }

    @Test("workspace toolbar button remains present in main view shell")
    func workspaceToolbarButtonRemainsPresentInMainViewShell() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains("case workspace"))
        #expect(source.contains("ToolbarItem(placement: .primaryAction)"))
    }
}
