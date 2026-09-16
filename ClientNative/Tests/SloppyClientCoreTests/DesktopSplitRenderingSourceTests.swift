import Foundation
import Testing

@Suite("Desktop split rendering source")
struct DesktopSplitRenderingSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try mainViewAwareSourceContents(at: url)
    }

    @Test("main view renders two desktop panes with a center split handle")
    func mainViewRendersTwoDesktopPanesWithCenterSplitHandle() throws {
        let source = try source("Sources", "SloppyClient", "Navigation", "Main", "MainView.swift")

        #expect(source.contains("if let desktopSplitState = viewModel.desktopSplitState"))
        #expect(source.contains("DesktopSplitHandle("))
        #expect(source.contains("desktopTabContent(for: primaryTab)"))
        #expect(source.contains("desktopTabContent(for: secondaryTab)"))
    }
}
