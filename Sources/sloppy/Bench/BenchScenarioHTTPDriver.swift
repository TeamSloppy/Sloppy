import Foundation
import Protocols

/// Runs scenarios against a live Core: one fresh agent per run, so memory never leaks between runs.
final class BenchScenarioHTTPDriver: BenchScenarioDriver, @unchecked Sendable {
    let client: SloppyCLIClient
    /// Root of the Core's data directory (`~/.sloppy`), used only to read curated markdown documents.
    let dataDirectory: URL?
    /// Agents are isolated by default: with shared memory on, one run's facts can be recalled by another run's agent.
    let sharedMemory: Bool
    private let lock = NSLock()
    private var sessions: [String: String] = [:]

    init(client: SloppyCLIClient, dataDirectory: URL?, sharedMemory: Bool = false) {
        self.client = client
        self.dataDirectory = dataDirectory
        self.sharedMemory = sharedMemory
    }

    func prepareAgent() async throws -> String {
        let id = "memeval-\(UUID().uuidString.prefix(8).lowercased())"
        let request = AgentCreateRequest(
            id: id, displayName: "Memory eval", role: "general assistant",
            runtime: AgentRuntimeConfig(type: .native, sharedMemoryEnabled: sharedMemory)
        )
        _ = try await client.post("/v1/agents", body: client.encode(request))
        return id
    }

    func send(agentID: String, session: String, text: String, model: String?, mode: AgentChatMode) async throws -> BenchScenarioReply {
        let sessionID = try await sessionID(agentID: agentID, name: session)
        let base = "/v1/agents/\(SloppyCLIClient.escape(agentID))/sessions/\(SloppyCLIClient.escape(sessionID))"
        let data = try await client.post(
            "\(base)/messages",
            body: client.encode(AgentSessionPostMessageRequest(userId: "local", content: text, selectedModel: model, mode: mode))
        )
        let response = try BenchHTTPDriver.decode(AgentSessionMessageResponse.self, "post message", from: data)
        let reply = response.appendedEvents.last { $0.type == .message && $0.message?.role == .assistant }?
            .message?.segments.compactMap(\.text).joined(separator: "\n") ?? ""
        // The post response carries the turn's message and status events; tool events live in the session.
        let detail = try BenchHTTPDriver.decode(AgentSessionDetail.self, "load session", from: try await client.get(base))
        return BenchScenarioReply(text: reply, events: detail.events)
    }

    func checkpoint(agentID: String, session: String) async throws {
        let sessionID = try await sessionID(agentID: agentID, name: session)
        let path = "/v1/agents/\(SloppyCLIClient.escape(agentID))/sessions/\(SloppyCLIClient.escape(sessionID))/checkpoint"
        _ = try await client.post(path, body: client.encode(AgentMemoryCheckpointRequest(reason: "bench")))
    }

    func storedNotes(agentID: String) async -> [String] {
        // The agent's own list misses project, channel and shared scopes, so also browse every scope.
        var notes: [String] = []
        let agentPath = "/v1/agents/\(SloppyCLIClient.escape(agentID))/memories"
        if let data = try? await client.get(agentPath, query: ["limit": "500"]),
           let list = try? BenchHTTPDriver.decode(AgentMemoryListResponse.self, "memories", from: data) {
            notes += list.items.map { [$0.note, $0.summary ?? ""].joined(separator: "\n") }
        }
        if let data = try? await client.get("/v1/memories", query: ["limit": "500"]),
           let list = try? BenchHTTPDriver.decode(MemoryListResponse.self, "memories", from: data) {
            notes += list.items.map { [$0.note, $0.summary ?? ""].joined(separator: "\n") }
        }
        return notes
    }

    func documentTexts(agentID: String) async -> [String] {
        guard let dataDirectory else { return [] }
        return Self.markdownTexts(under: dataDirectory.appendingPathComponent("agents").appendingPathComponent(agentID))
    }

    /// Markdown files below `root`, excluding session transcripts and installed skills.
    static func markdownTexts(under root: URL) -> [String] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var texts: [String] = []
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                if ["sessions", "skills"].contains(entry.lastPathComponent) { continue }
                texts += markdownTexts(under: entry)
            } else if entry.pathExtension == "md", let text = try? String(contentsOf: entry, encoding: .utf8) {
                texts.append(text)
            }
        }
        return texts
    }

    func removeAgent(agentID: String) async {
        _ = try? await client.delete("/v1/agents/\(SloppyCLIClient.escape(agentID))")
    }

    private func sessionID(agentID: String, name: String) async throws -> String {
        let key = "\(agentID)/\(name)"
        if let existing = lock.withLock({ sessions[key] }) { return existing }
        let data = try await client.post(
            "/v1/agents/\(SloppyCLIClient.escape(agentID))/sessions",
            body: client.encode(AgentSessionCreateRequest(title: "memory eval \(name)"))
        )
        let created = try BenchHTTPDriver.decode(AgentSessionSummary.self, "create session", from: data)
        lock.withLock { sessions[key] = created.id }
        return created.id
    }
}
