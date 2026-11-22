import Foundation

public struct ChatPromptSuggestion: Decodable, Sendable {
    public let sourceRunId: String
    public let text: String?
}

extension SloppyAPIClient {
    public func fetchPromptSuggestion(agentID: String, sessionID: String, sourceRunID: String) async throws -> ChatPromptSuggestion {
        let agent = BackendHTTPClient.encodePathSegment(agentID)
        let session = BackendHTTPClient.encodePathSegment(sessionID)
        return try await http.post("/v1/agents/\(agent)/sessions/\(session)/prompt-suggestion",
            body: ["sourceRunId": sourceRunID])
    }
}
