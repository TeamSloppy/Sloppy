import Foundation
import Testing

@Suite("Main sidebar project sessions")
struct MainSidebarProjectSessionsTests {
    private var source: String {
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

    @Test("project groups are built from chat sessions with messages")
    func projectGroupsAreBuiltFromChatSessionsWithMessages() throws {
        let source = try source

        #expect(source.contains("let projectSessions = viewModel.chatViewModel.sessions.filter"))
        #expect(source.contains("$0.projectId == project.id"))
        #expect(source.contains("$0.messageCount > 0"))
        #expect(source.contains("ForEach(visible) { session in"))
        #expect(source.contains("projectSessionRow(session: session, c: c, sp: sp)"))
    }
}
