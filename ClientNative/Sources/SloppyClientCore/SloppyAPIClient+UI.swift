import Foundation
import SloppyA2UI

public struct ChatUIActionReceipt: Decodable, Sendable {
    public var actionId: String
    public var revision: Int
    public var status: String
}
extension SloppyAPIClient {
    public func fetchUISurfaces(agentID: String, sessionID: String) async throws -> [A2UISurfaceSnapshot] {
        try await http.get(
            "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentID))/sessions/\(BackendHTTPClient.encodePathSegment(sessionID))/ui-surfaces"
        )
    }
    public func submitUIAction(agentID: String, sessionID: String, surfaceID: String, submission: A2UISubmission) async throws
        -> ChatUIActionReceipt
    {
        try await http.post(
            "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentID))/sessions/\(BackendHTTPClient.encodePathSegment(sessionID))/ui-surfaces/\(BackendHTTPClient.encodePathSegment(surfaceID))/actions",
            body: submission)
    }
}
