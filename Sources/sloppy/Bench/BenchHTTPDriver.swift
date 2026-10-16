import Foundation
import Protocols

/// Drives a running Core over its HTTP API: one throwaway project bound to the sandbox, one session, one turn.
struct BenchHTTPDriver: BenchAgentDriver {
    let client: SloppyCLIClient
    let agentID: String

    func run(prompt: String, workspace: URL, model: String?, mode: AgentChatMode) async throws -> [AgentSessionEvent] {
        let projectRequest = ProjectCreateRequest(
            name: "bench-\(workspace.lastPathComponent)",
            repoPath: workspace.path
        )
        let project = try Self.decode(
            ProjectEnvelope.self, "create project",
            from: try await client.post("/v1/projects", body: client.encode(projectRequest))
        ).project
        defer { Task { _ = try? await client.delete("/v1/projects/\(SloppyCLIClient.escape(project.id))") } }

        let agentPath = "/v1/agents/\(SloppyCLIClient.escape(agentID))/sessions"
        let session = try Self.decode(
            AgentSessionSummary.self, "create session",
            from: try await client.post(
                agentPath,
                body: client.encode(AgentSessionCreateRequest(
                    title: "bench \(workspace.lastPathComponent)", separateChat: true, projectId: project.id
                ))
            )
        )
        let messagePath = "\(agentPath)/\(SloppyCLIClient.escape(session.id))"
        let posted = try await client.post(
            "\(messagePath)/messages",
            body: client.encode(AgentSessionPostMessageRequest(
                userId: "local", content: prompt, selectedModel: model, mode: mode
            ))
        )
        _ = try Self.decode(AgentSessionMessageResponse.self, "post message", from: posted)
        let detail = try Self.decode(AgentSessionDetail.self, "load session", from: try await client.get(messagePath))
        return detail.events
    }

    private struct ProjectEnvelope: Decodable { let project: ProjectRecord }

    struct DecodeFailure: Error, LocalizedError {
        let step: String
        let underlying: Error
        let body: String
        var errorDescription: String? { "\(step): \(underlying) body=\(body.prefix(300))" }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ step: String, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw DecodeFailure(step: step, underlying: error, body: String(decoding: data, as: UTF8.self))
        }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid date: \(raw)")
            )
        }
        return decoder
    }
}
