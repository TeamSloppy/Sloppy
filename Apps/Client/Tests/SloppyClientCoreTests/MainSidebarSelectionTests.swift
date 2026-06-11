import Foundation
import Testing

@Suite("Main sidebar selection")
struct MainSidebarSelectionTests {
    private var mainSidebarSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyClient")
                .appendingPathComponent("MainSidebarView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("recent sessions are selected only in chat sidebar mode")
    func recentSessionsAreSelectedOnlyInChatSidebarMode() throws {
        let source = try mainSidebarSource
        let rowStart = try #require(source.range(of: "private func chatSessionRow("))
        let projectsStart = try #require(source.range(of: "private func projectsSection("))
        let rowSource = source[rowStart.lowerBound..<projectsStart.lowerBound]

        #expect(rowSource.contains("viewModel.selectedSidebarItem == .chats"))
    }
}
