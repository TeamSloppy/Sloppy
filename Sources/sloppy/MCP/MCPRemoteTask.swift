import Crypto
import Foundation
import Protocols

struct MCPRemoteTask: Codable, Sendable {
    let id: String
    let agentID: String
    let sessionID: String
    let serverID: String
    let toolName: String
    let remoteID: String
    let serverFingerprint: String
    var nextPoll: Date
    var expiresAt: Date?
    var terminal: [String: JSONValue]?
    var inputResponses: [String: JSONValue] = [:]

    static func fingerprint(_ server: CoreConfig.MCP.Server) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(server)).map { String(format: "%02x", $0) }.joined()
    }

    mutating func update(_ result: [String: JSONValue], now: Date) {
        let interval = max(100, min(result["pollIntervalMs"]?.asNumber ?? 1_000, Double(Int32.max)))
        nextPoll = now.addingTimeInterval(interval / 1_000)
        if let ttl = result["ttlMs"]?.asNumber {
            let formatter = ISO8601DateFormatter()
            let timestamp = result["createdAt"]?.asString ?? ""
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let precise = formatter.date(from: timestamp)
            formatter.formatOptions = [.withInternetDateTime]
            let created = precise ?? formatter.date(from: timestamp) ?? now
            expiresAt = created.addingTimeInterval(max(0, ttl) / 1_000)
        } else if result["ttlMs"] == .null {
            expiresAt = nil
        }
        switch result["status"]?.asString {
        case "completed", "cancelled", "failed":
            terminal = result
            nextPoll = now
        default: break
        }
    }
}
