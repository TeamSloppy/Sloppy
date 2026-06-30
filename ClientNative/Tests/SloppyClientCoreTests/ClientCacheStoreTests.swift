import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Client cache store")
@MainActor
struct ClientCacheStoreTests {
    @Test("sqlite cache roundtrips agents projects sessions and details")
    func sqliteCacheRoundtripsCoreOfflineRecords() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-client-cache-\(UUID().uuidString).sqlite3")
        let store = ClientCacheStore(path: tempURL.path)

        let agent = APIAgentRecord(id: "agent-1", displayName: "Anton", role: "builder")
        let task = APIProjectTask(id: "task-1", title: "Ship cache", status: "in_progress", actorId: "agent-1")
        let project = APIProjectRecord(id: "project-1", name: "Sloppy", tasks: [task], actors: ["agent-1"])
        let session = ChatSessionSummary(
            id: "session-1",
            agentId: "agent-1",
            title: "Cache discussion",
            messageCount: 2,
            updatedAt: Date(timeIntervalSince1970: 100),
            kind: "chat",
            projectId: "project-1"
        )
        let detail = ChatSessionDetail(
            summary: session,
            messages: [
                ChatMessage(
                    id: "message-1",
                    role: .user,
                    segments: [.init(kind: .text, text: "Hello cache")],
                    createdAt: Date(timeIntervalSince1970: 90)
                ),
                ChatMessage(
                    id: "message-2",
                    role: .assistant,
                    segments: [.init(kind: .text, text: "Loaded from sqlite")],
                    createdAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )

        await store.cacheAgents([agent])
        await store.cacheProjects([project])
        await store.cacheSessions(agentId: "agent-1", projectId: nil, sessions: [session])
        await store.cacheSessionDetail(agentId: "agent-1", detail: detail)

        let cachedAgents = await store.loadAgents()
        let cachedProjects = await store.loadProjects()
        let cachedSessions = await store.loadSessions(agentId: "agent-1")
        let cachedDetail = await store.loadSessionDetail(agentId: "agent-1", sessionId: "session-1")

        #expect(cachedAgents.map(\.id) == ["agent-1"])
        #expect(cachedProjects.map(\.id) == ["project-1"])
        #expect(cachedProjects.first?.tasks?.map(\.id) == ["task-1"])
        #expect(cachedSessions.map(\.id) == ["session-1"])
        #expect(cachedSessions.first?.messageCount == 2)
        #expect(cachedDetail?.messages.map(\.id) == ["message-1", "message-2"])
        #expect(cachedDetail?.messages.last?.textContent == "Loaded from sqlite")
    }

    @Test("sqlite cache indexes message text for local search")
    func sqliteCacheIndexesMessageTextForLocalSearch() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-client-cache-search-\(UUID().uuidString).sqlite3")
        let store = ClientCacheStore(path: tempURL.path)

        let session = ChatSessionSummary(
            id: "session-search-1",
            agentId: "agent-1",
            title: "Search discussion",
            messageCount: 2,
            updatedAt: Date(timeIntervalSince1970: 200),
            kind: "chat",
            projectId: "project-1"
        )
        let detail = ChatSessionDetail(
            summary: session,
            messages: [
                ChatMessage(
                    id: "message-alpha",
                    role: .user,
                    segments: [.init(kind: .text, text: "Need offline cache for sessions")],
                    createdAt: Date(timeIntervalSince1970: 190)
                ),
                ChatMessage(
                    id: "message-beta",
                    role: .assistant,
                    segments: [.init(kind: .text, text: "SQLite search index is ready")],
                    createdAt: Date(timeIntervalSince1970: 200)
                )
            ]
        )

        await store.cacheSessionDetail(agentId: "agent-1", detail: detail)
        let hits = await store.searchMessages(query: "SQLite", limit: 10)

        #expect(hits.count == 1)
        #expect(hits.first?.sessionId == "session-search-1")
        #expect(hits.first?.messageId == "message-beta")
        #expect(hits.first?.text == "SQLite search index is ready")
        #expect(hits.first?.projectId == "project-1")
    }
}
