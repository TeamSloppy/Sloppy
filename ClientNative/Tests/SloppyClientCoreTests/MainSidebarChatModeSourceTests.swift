import Foundation
import Testing

@Suite("Main sidebar chat mode")
struct MainSidebarChatModeSourceTests {
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

    @Test("chat sidebar exposes pinned and list mode controls inside chats tab")
    func chatSidebarExposesPinnedAndListModeControlsInsideChatsTab() throws {
        let source = try source(named: "SidebarRecentsList.swift")

        #expect(source.contains("SidebarSectionTitle(title: \"Pinned\")"))
        #expect(source.contains("SidebarListModeMenu"))
        #expect(source.contains("ChatSidebarSections.build("))
    }
}
