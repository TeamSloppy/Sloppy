import Foundation
import Testing

@Suite("Chat refresh source")
struct ChatRefreshSourceTests {
    private var source: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("chat view model refreshes the current context without resetting navigation state")
    func chatViewModelRefreshesCurrentContextWithoutResettingNavigationState() throws {
        let source = try source

        #expect(source.contains("public func refreshCurrentContext() async"))
        #expect(source.contains("if let selectedSessionId"))
        #expect(source.contains("fetchAgentSession(agentId: agent.id, sessionId: selectedSessionId)"))
        #expect(source.contains("transcript.replaceAll(detail.messages)"))
    }

    @Test("chat stream appends delta chunks and exposes an interrupt path")
    func chatViewModelAppendsChunksAndCanInterrupt() throws {
        let source = try source

        #expect(source.contains("scheduleStreamingAssistantText(text, sessionId: sessionId, mode: .append)"))
        #expect(source.contains("pendingStreamingAssistantText = (pendingStreamingAssistantText ?? \"\") + text"))
        #expect(source.contains("public func stopActiveRun()"))
        #expect(source.contains("try await apiClient.interruptAgentSession("))
        #expect(source.contains("defer { isSending = false }"))
    }
}
