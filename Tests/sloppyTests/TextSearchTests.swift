import Foundation
import Testing
import Protocols
import SloppyRuntime
@testable import sloppy

struct TextSearchTests {
    private func fixture() throws -> (URL, TextSearchDatabase, TextSearchIndexer) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("text-search-\(UUID())")
        let db = try TextSearchDatabase(url: root.appendingPathComponent("search/index.sqlite"))
        return (root, db, TextSearchIndexer(root: root, database: db))
    }

    private func journal(_ root: URL, agent: String = "helper", session: String = "first", text: String) throws -> URL {
        let url = root.appendingPathComponent("agents/\(agent)/sessions/\(session).jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let events: [[String: Any]] = [
            ["id": "created", "type": "session_created", "metadata": ["title": "Session \(session)", "projectId": "project"], "createdAt": "2026-10-26T10:00:00Z"],
            ["id": "event", "type": "message", "message": ["id": "message", "role": "user", "segments": [["kind": "text", "text": text]]], "createdAt": "2026-10-26T10:01:00Z"]
        ]
        try encoded(events).write(to: url)
        return url
    }

    private func encoded(_ events: [[String: Any]]) throws -> Data {
        var data = Data()
        for event in events {
            data.append(try JSONSerialization.data(withJSONObject: event, options: .sortedKeys))
            data.append(0x0A)
        }
        return data
    }

    private func hits(_ db: TextSearchDatabase, _ query: String, mode: TextSearchMode = .text, agent: String? = nil, project: String? = nil) throws -> [TextSearchHit] {
        try db.search(query: query, mode: mode, agentID: agent, projectID: project, limit: 50, offset: 0)
    }

    @Test func searchesAllSessionsLiteralUnicodeCodeAndWordPrefixes() throws {
        let (root, db, indexer) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try journal(root, text: "Исправили AgentSessionFileStore: C++ /tmp/file_name.swift и привет миру")
        _ = try journal(root, agent: "second", session: "second", text: "Another session says привет")
        #expect(try indexer.synchronize().indexed == 2)
        #expect(try hits(db, "ПРИВЕТ").count == 2)
        #expect(try hits(db, "SessionFile").count == 1)
        #expect(try hits(db, "C++").count == 1)
        #expect(try hits(db, "/tmp/file_name").count == 1)
        #expect(try hits(db, "пр", mode: .words).count == 2)
        #expect(try hits(db, "привет", agent: "helper").count == 1)
        #expect(try hits(db, "привет", project: "unknown").isEmpty)
        #expect(try hits(db, "\" OR * NOT (" ).isEmpty)
        let hit = try #require(try hits(db, "SessionFile").first)
        #expect(hit.messageId == "message")
        #expect(hit.projectId == "project")
        #expect(hit.snippet.contains("\u{E000}"))
        #expect(try db.document(id: hit.id)?.text.contains("AgentSessionFileStore") == true)
        // The projection survives closing and reopening the database.
        let reopened = try TextSearchDatabase(url: root.appendingPathComponent("search/index.sqlite"), readOnly: true)
        #expect(try hits(reopened, "ПРИВЕТ").count == 2)
    }

    @Test func catchesUpAppendsPartialWritesRewritesAndDeletions() throws {
        let (root, db, indexer) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try journal(root, text: "original needle")
        _ = try indexer.synchronize()
        let first = try #require(try hits(db, "needle").first)
        let original = try Data(contentsOf: url)
        let appended = try encoded([["id": "tool", "type": "tool_result", "toolResult": ["tool": "exec", "data": ["output": "second needle result"]]]])
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: appended.dropLast())
        _ = try indexer.synchronize()
        #expect(try hits(db, "needle").count == 1)
        try handle.write(contentsOf: Data([0x0A]))
        try handle.close()
        _ = try indexer.synchronize()
        #expect(try hits(db, "needle").count == 2)
        #expect(try hits(db, "original").first?.before == first.before)
        #expect(try indexer.synchronize().failed == 0)
        #expect(try hits(db, "needle").count == 2)
        // Rename/rewrite and truncate: old FTS rows must disappear.
        let rewritten = String(decoding: original, as: UTF8.self).replacingOccurrences(of: "original needle", with: "replacement text")
        try Data(rewritten.utf8).write(to: url, options: .atomic)
        _ = try indexer.synchronize()
        #expect(try hits(db, "needle").isEmpty)
        #expect(try hits(db, "replacement").count == 1)
        try FileManager.default.removeItem(at: url)
        #expect(try hits(db, "replacement").isEmpty)
        #expect(try db.document(id: first.id) == nil)
        _ = try indexer.synchronize()
        #expect(try db.rows("SELECT * FROM documents").isEmpty)
    }

    @Test func indexesChannelMessagesThinkingAndToolPayloads() throws {
        let (root, db, indexer) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try journal(root, text: "hello")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: encoded([
            ["id": "thinking", "type": "message", "message": ["id": "thought", "role": "assistant", "segments": [["kind": "thinking", "text": "reasoningneedle"]]]],
            ["id": "tool", "type": "tool_call", "toolCall": ["tool": "exec", "arguments": ["command": "toolneedle"]]]
        ]))
        try handle.close()
        let channel = root.appendingPathComponent("channel-sessions/channel.jsonl")
        try FileManager.default.createDirectory(at: channel.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded([["id": "channel-message", "type": "user_message", "content": "channelneedle", "userId": "user"]]).write(to: channel)
        _ = try indexer.synchronize()
        #expect(try hits(db, "reasoningneedle").first?.messageId == "thought")
        #expect(try hits(db, "toolneedle").first?.kind == "tool_call")
        let channelHits = try hits(db, "channelneedle")
        #expect(channelHits.first?.source == "channel")
    }

    @Test func measuresIndexedQueryLatency() throws {
        let (root, db, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try journal(root, text: "benchmark source")
        let count = Int(ProcessInfo.processInfo.environment["SLOPPY_SEARCH_BENCHMARK_COUNT"] ?? "10000") ?? 10000
        try db.execute("INSERT INTO sources(path,source,agent_id,session_id,title) VALUES(?,?,?,?,?)", [url.path, "agent", "helper", "first", "Benchmark"])
        try db.transaction {
            for index in 0..<count {
                try db.execute("INSERT INTO documents(id,path,event_id,before_offset,kind,created_at,text) VALUES(?,?,?,?,?,?,?)",
                    [String(index), url.path, String(index), "100", "message", "2026-10-26T10:00:00Z",
                     "Message \(index) AgentSessionFileStore /tmp/file_\(index).swift привет миру searchable needle\(index % 100)"])
            }
        }
        var samples: [Double] = []
        for _ in 0..<10 {
            for query in ["Message", "SessionFile", "needle42", "привет", "/tmp/file_999"] {
                let start = ContinuousClock.now
                _ = try hits(db, query)
                let elapsed = start.duration(to: .now).components
                samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            }
        }
        samples.sort()
        #expect(try hits(db, "SessionFile").count == 50)
        print("SEARCH_BENCHMARK documents=\(count) queries=\(samples.count) median_ms=\(samples[samples.count / 2]) p95_ms=\(samples[Int(Double(samples.count - 1) * 0.95)]) max_ms=\(samples.last ?? 0)")
    }

    @Test func validSearchRouteAndBadQueryResponses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("search-router-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var config = CoreConfig.test
        config.workspace = .init(name: root.lastPathComponent, basePath: root.deletingLastPathComponent().path)
        let service = CoreService(config: config)
        let router = CoreRouter(service: service)
        for path in ["/v1/search", "/v1/search?q=test&mode=invalid", "/v1/search?q=test&limit=1000", "/v1/search?q=test&offset=-1"] {
            let response = await router.handle(method: "GET", path: path, body: nil)
            #expect(response.status == 400)
        }
        let response = await router.handle(method: "GET", path: "/v1/search?q=hello", body: nil)
        #expect(response.status == 200)
        let missing = await router.handle(method: "GET", path: "/v1/search/document?id=unknown", body: nil)
        #expect(missing.status == 404)
        await service.stop()
    }
}
