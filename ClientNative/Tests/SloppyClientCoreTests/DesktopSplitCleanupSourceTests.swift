import Foundation
import Testing

@Suite("Desktop split cleanup source")
struct DesktopSplitCleanupSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main view model clears temporary split when retargeting selected chat tab")
    func mainViewModelClearsTemporarySplitWhenRetargetingSelectedChatTab() throws {
        let source = try source("Sources", "SloppyClient", "MainView.swift")

        #expect(source.contains("private func retargetSelectedChatTab(to session: ChatSessionSummary)"))
        #expect(source.contains("clearDesktopSplit()"))
    }
}
