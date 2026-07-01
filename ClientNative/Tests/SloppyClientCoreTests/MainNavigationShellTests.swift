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
        #expect(source.contains("var selectedAppSection: MainAppSection = .projects"))
        #expect(source.contains("func selectAppSection(_ section: MainAppSection)"))
    }

    @Test("phone layout uses system tab view")
    func phoneLayoutUsesSystemTabView() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains("private func phoneTabLayout() -> some View"))
        #expect(source.contains("TabView(selection: $viewModel.selectedAppSection)"))
        #expect(source.contains(".tag(MainAppSection.projects)"))
        #expect(source.contains(".tag(MainAppSection.agents)"))
        #expect(source.contains(".tag(MainAppSection.chats)"))
        #expect(source.contains(".tag(MainAppSection.settings)"))
    }

    @Test("regular layout switches detail content by selected section")
    func regularLayoutSwitchesDetailContentBySelectedSection() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains("private var activeDesktopTab: WorkspaceTab?"))
        #expect(source.contains("DesktopTabStripView("))
        #expect(source.contains("desktopContentArea()"))
        #expect(source.contains("desktopTabContent(for tab: WorkspaceTab)"))
        #expect(!source.contains("case .projects:\n                chatScreen(showsSidebarControl: false)"))
        #expect(!source.contains("case .workspace:\n                workspaceScreen()"))
    }

    @Test("sidebar defines navigator tabs for desktop sections")
    func sidebarDefinesNavigatorTabsForDesktopSections() throws {
        let source = try source(named: "MainSidebarView.swift")

        #expect(source.contains("navigatorTabBar(c: c, sp: sp)"))
        #expect(source.contains("navigatorTabRow("))
        #expect(source.contains("viewModel.selectAppSection(section)"))
        #expect(source.contains("switch viewModel.selectedAppSection"))
    }

    @Test("workspace toolbar button remains present in main view shell")
    func workspaceToolbarButtonRemainsPresentInMainViewShell() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains("case workspace"))
        #expect(source.contains("ToolbarItem(placement: .primaryAction)"))
    }
}
