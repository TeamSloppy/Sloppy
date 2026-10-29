import Foundation

public struct ClientPendingApproval: Codable, Sendable, Identifiable {
    public var id: String
    public var status: String
    public var agentId: String?
    public var sessionId: String?
    public var tool: String?
    public var reason: String?
    public var expiresAt: Date?
}

public struct ClientAccessUser: Codable, Sendable, Identifiable {
    public var id: String
    public var platform: String
    public var platformUserId: String
    public var displayName: String
    public var status: String
}

extension WorkspaceService {
    public func pendingApprovals() async throws -> [ClientPendingApproval] { try await http.get("/v1/tool-approvals/pending") }
    public func decideApproval(id: String, approved: Bool) async throws {
        struct Payload: Encodable { var decidedBy = "SloppyClient"; var scope = "once" }
        struct Response: Decodable { var id: String }
        let _: Response = try await http.post("/v1/tool-approvals/\(segment(id))/\(approved ? "approve" : "reject")", body: Payload())
    }
    public func accessUsers() async throws -> [ClientAccessUser] { try await http.get("/v1/channel-approvals/users") }
    public func removeAccessUser(id: String) async throws { try await http.delete("/v1/channel-approvals/users/\(segment(id))") }
    public func account() async throws -> AuthUserProfile { try await http.get("/v1/auth/me") }
    public func updateAccount(name: String, avatar: String, description: String) async throws -> AuthUserProfile {
        struct Payload: Encodable { var name: String; var avatar: String; var description: String }
        return try await http.patch("/v1/auth/me", body: Payload(name: name, avatar: avatar, description: description))
    }
    public func proactiveSettings(agentID: String) async throws -> ConfigJSONValue {
        try await http.get("/v1/agents/\(segment(agentID))/proactivity/settings")
    }
    public func updateProactiveSettings(agentID: String, document: ConfigJSONValue) async throws -> ConfigJSONValue {
        // Available model catalogs in the response are read-only.
        try await http.put("/v1/agents/\(segment(agentID))/proactivity/settings", body: ConfigJSONValue.object([
            "heartbeat": document["heartbeat"], "heartbeatMarkdown": document["heartbeatMarkdown"]
        ]))
    }
    public func meshTopology() async throws -> ConfigJSONValue { try await http.get("/v1/node/mesh") }
    public func voiceConfiguration() async throws -> ConfigJSONValue { try await http.get("/v1/voice/config") }
}
