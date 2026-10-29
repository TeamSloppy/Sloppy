import Foundation

/// A mention addresses immutable agent/session IDs, even when titles are duplicated.
public struct ChatSessionReference: Codable, Sendable, Equatable, Hashable {
    public var agentId: String
    public var sessionId: String
    public init(agentId: String, sessionId: String) {
        self.agentId = agentId
        self.sessionId = sessionId
    }
    public func markdown(title: String) -> String {
        let label = title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ")
        var url = URLComponents()
        url.scheme = "sloppy"
        url.host = "session"
        url.queryItems = [URLQueryItem(name: "agentId", value: agentId), URLQueryItem(name: "sessionId", value: sessionId)]
        return "[@\(label)](\(url.url?.absoluteString ?? ""))"
    }
}
