import Foundation
import Testing

@Suite("Main sidebar refresh")
struct MainSidebarRefreshTests {
    private func source(named fileName: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClient")
        let sourceURL = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: nil
        )?
            .compactMap { $0 as? URL }
            .first(where: { $0.lastPathComponent == fileName })
        return try String(
            contentsOf: #require(sourceURL),
            encoding: .utf8
        )
    }

    @Test("main view model exposes a unified refresh entry point")
    func mainViewModelExposesUnifiedRefreshEntryPoint() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains("func refreshContent() async"))
        #expect(source.contains("await loadProjects(force: true)"))
        #expect(source.contains("if chatViewModel.selectedAgent == nil"))
        #expect(source.contains("chatViewModel.loadInitialData()"))
        #expect(source.contains("await chatViewModel.refreshCurrentContext()"))
    }

    @Test("sidebar supports pull to refresh")
    func sidebarSupportsPullToRefresh() throws {
        let source = try source(named: "MacMainSidebar.swift")

        #expect(source.contains(".refreshable"))
        #expect(source.contains("await viewModel.refreshContent()"))
    }

    @Test("main view wires cmd+r to the same refresh flow")
    func mainViewWiresCmdRToRefresh() throws {
        let source = try source(named: "MainView.swift")

        #expect(source.contains(".keyboardShortcut(\"r\", modifiers: [.command])"))
        #expect(source.contains("Task { await viewModel.refreshContent() }"))
    }
}
