import Foundation
import Testing

@Suite("Desktop tab split state source")
struct DesktopTabSplitStateSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main tabs defines temporary desktop split state")
    func mainTabsDefinesTemporaryDesktopSplitState() throws {
        let source = try source("Sources", "SloppyClient", "MainTabs.swift")

        #expect(source.contains("struct DesktopTabSplitState"))
        #expect(source.contains("var primaryTabID: WorkspaceTab.ID"))
        #expect(source.contains("var secondaryTabID: WorkspaceTab.ID"))
        #expect(source.contains("var fraction: CGFloat"))
    }
}
