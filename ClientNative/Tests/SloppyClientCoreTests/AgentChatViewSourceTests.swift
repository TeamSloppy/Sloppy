import Foundation
import Testing

@Suite("AgentChatView session actions")
struct AgentChatViewSourceTests {
    private var agentChatViewSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureAgents")
                .appendingPathComponent("AgentChatView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("session cards expose contextual management actions")
    func sessionCardsExposeContextualManagementActions() throws {
        let source = try agentChatViewSource
        let cardStart = try #require(source.range(of: "private func sessionCard("))
        let managementStart = try #require(source.range(of: "private func deleteSession("))
        let cardSource = source[cardStart.lowerBound..<managementStart.lowerBound]

        #expect(cardSource.contains(".contextMenu"))
        #expect(cardSource.contains("toggleSessionPinned(session)"))
        #expect(cardSource.contains("copyDebugSessionFileLink(session)"))
        #expect(cardSource.contains("deleteSession(session)"))
    }

    @Test("session actions use API deletion, persisted pins, and debug file links")
    func sessionActionsUseStableAPIs() throws {
        let source = try agentChatViewSource

        #expect(source.contains("apiClient.deleteAgentSession(agentId: agent.id, sessionId: session.id)"))
        #expect(source.contains("settings.setSessionPinned(session.id, isPinned: nextPinned)"))
        #expect(source.contains("UIClipboard.setString(url.absoluteString)"))
        #expect(source.contains("\"/v1/debug/session-file-path/"))
    }
}
