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
                .appendingPathComponent("MainView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("recent sessions are selected only in chat sidebar mode")
    func recentSessionsAreSelectedOnlyInChatSidebarMode() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClient")
            .appendingPathComponent("MainSidebarView.swift")
        let source = try String(contentsOf: sidebarURL, encoding: .utf8)
        let rowStart = try #require(source.range(of: "private func chatSessionRow("))
        let projectsStart = try #require(source.range(of: "private func projectsSection("))
        let rowSource = source[rowStart.lowerBound..<projectsStart.lowerBound]

        #expect(rowSource.contains("viewModel.selectedSidebarItem == .chats"))
    }

    @Test("main view switches to compact layout on phones")
    func mainViewSwitchesToCompactLayoutOnPhones() throws {
        let source = try mainSidebarSource

        #expect(source.contains("if idiom == .phone"))
        #expect(source.contains("fullScreenCompactLayout()"))
        #expect(source.contains("chatScreen(showsSidebarControl: true)"))
        #expect(!source.contains("compactLayout(availableWidth: proxy.size.width)"))
    }

    @Test("overlay sidebar uses dedicated close button styling")
    func overlaySidebarUsesDedicatedCloseButtonStyling() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClient")
            .appendingPathComponent("MainSidebarView.swift")
        let source = try String(contentsOf: sidebarURL, encoding: .utf8)

        #expect(source.contains("MobileSidebarOverlayIconButtonStyle"))
    }
}
