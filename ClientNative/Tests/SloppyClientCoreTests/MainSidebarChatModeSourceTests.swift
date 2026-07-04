import Foundation
import Testing

@Suite("Main sidebar chat mode")
struct MainSidebarChatModeSourceTests {
    private func source(named fileName: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyClient")
                .appendingPathComponent(fileName),
            encoding: .utf8
        )
    }

    @Test("chat sidebar exposes pinned and list mode controls inside chats tab")
    func chatSidebarExposesPinnedAndListModeControlsInsideChatsTab() throws {
        let source = try source(named: "MainSidebarView.swift")

        #expect(source.contains("sectionLabel(\"Pinned\""))
        #expect(source.contains("chatListModeMenu"))
        #expect(source.contains("ChatSidebarSections.build("))
    }
}
