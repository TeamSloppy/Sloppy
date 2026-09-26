import Foundation
import SloppyClientCore
import Testing

@Suite("Chat model preferences")
struct ChatModelPreferenceStoreTests {
    @Test("reopened sessions retain their model while new sessions use the agent choice")
    func sessionAndAgentChoices() throws {
        let suite = "chat-model-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ChatModelPreferenceStore(defaults: defaults)
        let server = "direct:http://localhost:25101"

        first.setSelection("openai:gpt-6", server: server, agentId: "agent", sessionId: "older")
        first.setSelection(ChatModelSelection.automaticJEVId, server: server, agentId: "agent", sessionId: "current")

        let reopened = ChatModelPreferenceStore(defaults: defaults)
        #expect(reopened.selection(server: server, agentId: "agent", sessionId: "older") == "openai:gpt-6")
        #expect(reopened.selection(server: server, agentId: "agent", sessionId: "current") == ChatModelSelection.automaticJEVId)
        #expect(reopened.selection(server: server, agentId: "agent", sessionId: nil) == ChatModelSelection.automaticJEVId)
        #expect(reopened.selection(server: server, agentId: "agent", sessionId: "new") == ChatModelSelection.automaticJEVId)
        #expect(reopened.selection(server: server, agentId: "other", sessionId: nil) == nil)
        #expect(reopened.selection(server: "relay:other", agentId: "agent", sessionId: nil) == nil)
    }

    @Test("removing a chat keeps the agent's choice for future chats")
    func removeSession() throws {
        let suite = "chat-model-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ChatModelPreferenceStore(defaults: defaults)
        let server = "direct:http://localhost:25101"

        store.setSelection("openai:gpt-6", server: server, agentId: "agent", sessionId: "old")
        store.setSelection(ChatModelSelection.automaticJEVId, server: server, agentId: "agent", sessionId: "new")
        store.removeSession(server: server, agentId: "agent", sessionId: "old")

        #expect(store.selection(server: server, agentId: "agent", sessionId: "old") == ChatModelSelection.automaticJEVId)
        #expect(store.selection(server: server, agentId: "agent", sessionId: nil) == ChatModelSelection.automaticJEVId)
    }
}
