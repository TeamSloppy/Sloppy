import Foundation

/// A composer insertion keeps its wire text and a typed preview destination.
public struct ChatComposerReference: Codable, Equatable, Sendable {
    public enum Target: Codable, Equatable, Hashable, Sendable {
        case file(projectId: String, path: String)
        case session(agentId: String, sessionId: String)
        case skill(agentId: String, skillId: String)
        case command(agentId: String, name: String)
        case task(projectId: String, taskId: String)
        case website(URL)
    }

    public var rawText: String
    public var title: String
    public var detail: String
    public var target: Target
    public var endpoint: SloppyInstanceEndpoint?

    public init(rawText: String, title: String, detail: String = "", target: Target, endpoint: SloppyInstanceEndpoint? = nil) {
        self.rawText = rawText
        self.title = title
        self.detail = detail
        self.target = target
        self.endpoint = endpoint
    }

    public var systemImage: String {
        switch target {
        case .file: "doc"
        case .session: "bubble.left.and.bubble.right"
        case .skill: "sparkles"
        case .command: "command"
        case .task: "checkmark.circle"
        case .website: "globe"
        }
    }
}
